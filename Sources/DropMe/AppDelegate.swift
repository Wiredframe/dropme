import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let watcher = DragWatcher()
    private var shelves: [ShelfWindow] = []
    /// The shelf last opened by dragging, as long as nothing has been dropped on it.
    private weak var dragShelf: ShelfWindow?
    private var hideIcon: Bool {
        get { UserDefaults.standard.bool(forKey: "hideIcon") }
        set { UserDefaults.standard.set(newValue, forKey: "hideIcon"); statusItem.isVisible = !newValue }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "tray.and.arrow.down", accessibilityDescription: "DropMe")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        statusItem.isVisible = !hideIcon

        watcher.onTrigger = { [weak self] point in
            self?.dragShelf = self?.openShelf(at: point)
        }
        watcher.onDragEnded = { [weak self] in self?.closeAbandonedShelf() }
        watcher.start()
    }

    /// With the icon hidden, launching the app again (Finder, `open -a DropMe`) brings it back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        hideIcon = false
        return false
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(withTitle: "Neues Fenster", action: #selector(newShelf), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Alle Fenster schließen", action: shelves.isEmpty ? nil : #selector(closeAll), keyEquivalent: "").target = self
        menu.addItem(.separator())
        let login = menu.addItem(withTitle: "Beim Anmelden starten", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        let hide = menu.addItem(withTitle: "Menüsymbol ausblenden", action: #selector(hideStatusItem), keyEquivalent: "")
        hide.target = self
        hide.toolTip = "DropMe im Finder erneut öffnen, um es zurückzuholen."
        menu.addItem(.separator())
        menu.addItem(withTitle: "DropMe beenden", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    /// “Open With DropMe” or `open -a DropMe <files>` puts the files on a new shelf.
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

    /// If the drag was cancelled or dropped elsewhere, the empty shelf goes away again.
    private func closeAbandonedShelf() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let shelf = self?.dragShelf else { return }
            self?.dragShelf = nil
            if shelf.shelf.items.isEmpty, !shelf.shelf.hasReceivedDrop { shelf.dismiss() }
        }
    }

    @objc private func newShelf() {
        // Offset new shelves slightly so they don't sit exactly on top of each other.
        let frame = NSScreen.main?.visibleFrame ?? .zero
        let offset = CGFloat(shelves.count % 6) * 24
        openShelf(at: NSPoint(x: frame.midX + offset, y: frame.midY - offset))
    }

    @objc private func closeAll() {
        shelves.forEach { $0.dismiss() }
    }

    @objc private func hideStatusItem() {
        hideIcon = true
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
