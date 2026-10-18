import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let watcher = DragWatcher()
    private var shelves: [ShelfWindow] = []
    /// Das zuletzt per Ziehen geöffnete Fenster, solange noch nichts darin gelandet ist.
    private weak var dragShelf: ShelfWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "tray.and.arrow.down", accessibilityDescription: "DropMe")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        watcher.onTrigger = { [weak self] point in
            self?.dragShelf = self?.openShelf(at: point)
        }
        watcher.onDragEnded = { [weak self] in self?.closeAbandonedShelf() }
        watcher.start()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(withTitle: "Neues Fenster", action: #selector(newShelf), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Alle Fenster schließen", action: shelves.isEmpty ? nil : #selector(closeAll), keyEquivalent: "").target = self
        menu.addItem(.separator())
        let login = menu.addItem(withTitle: "Beim Anmelden starten", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(.separator())
        menu.addItem(withTitle: "DropMe beenden", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    /// „Öffnen mit DropMe“ bzw. `open -a DropMe <Dateien>` legt die Dateien in ein neues Fenster.
    func application(_ application: NSApplication, open urls: [URL]) {
        let fileURLs = urls.filter(\.isFileURL)
        guard !fileURLs.isEmpty else { return }
        openShelf(at: NSEvent.mouseLocation).shelf.add(fileURLs)
    }

    @discardableResult
    private func openShelf(at point: NSPoint) -> ShelfWindow {
        let shelf = ShelfWindow(center: point)
        shelf.onClose = { [weak self, weak shelf] in self?.shelves.removeAll { $0 === shelf } }
        shelves.append(shelf)
        shelf.present()
        return shelf
    }

    /// Wurde das Ziehen abgebrochen oder woanders abgelegt, verschwindet das leere Fenster wieder.
    private func closeAbandonedShelf() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let shelf = self?.dragShelf else { return }
            self?.dragShelf = nil
            if shelf.shelf.items.isEmpty, !shelf.shelf.hasReceivedDrop { shelf.dismiss() }
        }
    }

    @objc private func newShelf() {
        // Mehrere neue Fenster leicht versetzt, damit sie nicht genau übereinander liegen.
        let frame = NSScreen.main?.visibleFrame ?? .zero
        let offset = CGFloat(shelves.count % 6) * 24
        openShelf(at: NSPoint(x: frame.midX + offset, y: frame.midY - offset))
    }

    @objc private func closeAll() {
        shelves.forEach { $0.dismiss() }
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSApp.activate(ignoringOtherApps: true)
            NSAlert(error: error).runModal()
        }
    }
}
