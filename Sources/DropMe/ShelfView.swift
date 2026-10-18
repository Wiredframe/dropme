import AppKit
import Quartz
import QuickLookThumbnailing

/// Inhalt eines Fensters: nimmt Dateien an, zeigt sie als Stapel, gibt sie per Ziehen wieder ab.
final class ShelfView: NSView, NSDraggingSource, QLPreviewPanelDataSource {
    private(set) var items: [URL] = []
    private var thumbnails: [URL: NSImage] = [:]
    /// Echte Vorschauen (keine Symbole) bekommen runde Ecken und Schatten.
    private var framed: Set<URL> = []
    private var dragStart: NSPoint?
    /// Wurde schon einmal etwas abgelegt? Sonst schließt ein abgebrochenes Ziehen das leere Fenster.
    private(set) var hasReceivedDrop = false

    private let handle = NSView()
    private let closeButton = CircleButton(symbol: "xmark")
    private let menuButton = CircleButton(symbol: "chevron.down")
    private let stack = StackView()
    private let pill = PillView()
    private let emptyLabel = NSTextField(labelWithString: "Hierher ziehen")

    private var isTargeted = false {
        didSet {
            guard isTargeted != oldValue else { return }
            let color = isTargeted ? resolved(NSColor.controlAccentColor.withAlphaComponent(0.18)) : nil
            animate(layer, key: "backgroundColor", to: color, duration: 0.15) { $0.backgroundColor = color }
            if isTargeted { stack.pop(from: 1.04) }
        }
    }

    private static let acceptedTypes: [NSPasteboard.PasteboardType] =
        [.fileURL] + NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = ShelfWindow.cornerRadius

        handle.wantsLayer = true
        handle.layer?.cornerRadius = 2.5

        closeButton.target = self
        closeButton.action = #selector(closeShelf)
        closeButton.toolTip = "Fenster schließen"
        menuButton.target = self
        menuButton.action = #selector(showActionMenu(_:))
        menuButton.toolTip = "Aktionen"

        pill.onClick = { [weak self] in self?.showItemMenu() }

        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.font = .systemFont(ofSize: 13, weight: .medium)
        emptyLabel.alignment = .center

        stack.shelf = self
        [handle, closeButton, menuButton, stack, pill, emptyLabel].forEach(addSubview)
        registerForDraggedTypes(Self.acceptedTypes)
        reload()
        updateColors()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    private func updateColors() {
        handle.layer?.backgroundColor = resolved(.tertiaryLabelColor)
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: Layout

    override func layout() {
        super.layout()
        let w = bounds.width, h = bounds.height
        handle.frame = NSRect(x: (w - 36) / 2, y: h - 13, width: 36, height: 5)
        closeButton.frame = NSRect(x: 12, y: h - 46, width: 34, height: 34)
        menuButton.frame = NSRect(x: w - 46, y: h - 46, width: 34, height: 34)
        stack.frame = NSRect(x: 40, y: 54, width: w - 80, height: h - 104)
        pill.frame = pillFrame()
        emptyLabel.sizeToFit()
        emptyLabel.frame.origin = NSPoint(x: (w - emptyLabel.frame.width) / 2, y: (h - emptyLabel.frame.height) / 2 - 6)
    }

    private func pillFrame() -> NSRect {
        let width = min(bounds.width - 40, pill.fittingWidth)
        return NSRect(x: (bounds.width - width) / 2, y: 14, width: width, height: 28)
    }

    private func reload() {
        if emptyLabel.isHidden != items.isEmpty {
            crossfade(layer, duration: 0.18)
        }
        emptyLabel.isHidden = !items.isEmpty
        stack.isHidden = items.isEmpty
        pill.isHidden = items.isEmpty
        pill.title = items.count == 1 ? items[0].lastPathComponent : "\(items.count) Objekte"
        stack.images = items.suffix(3).map { (image(for: $0), framed.contains($0)) }
        // Die Pille gleitet auf ihre neue Breite.
        let target = pillFrame()
        if window != nil, !reduceMotion, !pill.isHidden, pill.frame.width > 0, pill.frame != target {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                pill.animator().frame = target
            }
        }
        needsLayout = true
        if QLPreviewPanel.sharedPreviewPanelExists(), QLPreviewPanel.shared().isVisible {
            QLPreviewPanel.shared().reloadData()
        }
    }

    // MARK: Inhalt

    func add(_ urls: [URL]) {
        let new = urls.filter { !items.contains($0) }
        guard !new.isEmpty else { return }
        items.append(contentsOf: new)
        new.forEach(loadThumbnail)
        reload()
        stack.pop(from: 0.9)
    }

    private func setItems(_ urls: [URL]) {
        items = urls
        let kept = Set(urls)
        thumbnails = thumbnails.filter { kept.contains($0.key) }
        framed.formIntersection(kept)
        items.filter { thumbnails[$0] == nil }.forEach(loadThumbnail)
        reload()
    }

    private func image(for url: URL) -> NSImage {
        thumbnails[url] ?? NSWorkspace.shared.icon(forFile: url.path)
    }

    private func loadThumbnail(for url: URL) {
        let scale = window?.backingScaleFactor ?? 2
        let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: 240, height: 240),
                                                   scale: scale, representationTypes: .all)
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak self] rep, _ in
            guard let rep else { return }
            DispatchQueue.main.async {
                guard let self, self.items.contains(url) else { return }
                self.thumbnails[url] = rep.nsImage
                if rep.type == .thumbnail { self.framed.insert(url) }
                self.stack.images = self.items.suffix(3).map { (self.image(for: $0), self.framed.contains($0)) }
            }
        }
    }

    /// Ablage für zugesagte Dateien (z. B. Anhänge aus Mail), räumt das System selbst auf.
    private static func promiseDirectory() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DropMe", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: Hineinziehen

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if (sender.draggingSource as? ShelfView) === self { return [] }
        isTargeted = true
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) { isTargeted = false }
    override func draggingEnded(_ sender: NSDraggingInfo) { isTargeted = false }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        isTargeted = false
        guard receive(from: sender.draggingPasteboard) else { return false }
        hasReceivedDrop = true
        return true
    }

    @discardableResult
    private func receive(from pasteboard: NSPasteboard) -> Bool {
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           !urls.isEmpty {
            add(urls)
            return true
        }
        if let promises = pasteboard.readObjects(forClasses: [NSFilePromiseReceiver.self]) as? [NSFilePromiseReceiver],
           !promises.isEmpty {
            let dir = Self.promiseDirectory()
            for promise in promises {
                promise.receivePromisedFiles(atDestination: dir, options: [:], operationQueue: .main) { [weak self] url, error in
                    if error == nil { self?.add([url]) }
                }
            }
            return true
        }
        return false
    }

    // MARK: Herausziehen

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        guard !items.isEmpty, stack.frame.contains(point) else {
            window?.performDrag(with: event)
            return
        }
        if event.clickCount == 2 {
            items.forEach { NSWorkspace.shared.open($0) }
            return
        }
        dragStart = point
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard hypot(point.x - start.x, point.y - start.y) > 3 else { return }
        dragStart = nil

        let draggingItems = items.enumerated().map { index, url -> NSDraggingItem in
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            let image = image(for: url)
            let offset = CGFloat(min(index, 6)) * 3
            let frame = StackView.fit(image.size, in: stack.frame.insetBy(dx: 10, dy: 10)).offsetBy(dx: offset, dy: -offset)
            item.setDraggingFrame(frame, contents: image)
            return item
        }
        let session = beginDraggingSession(with: draggingItems, event: event, source: self)
        session.draggingFormation = .pile
        session.animatesToStartingPositionsOnCancelOrFail = true
    }

    override func mouseUp(with event: NSEvent) { dragStart = nil }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? [.copy, .move, .link, .generic] : .copy
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        guard !operation.isEmpty else { return }
        // Hat das Ziel die Dateien bewegt, verschwinden sie hier; der Finder braucht dafür einen Moment.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self else { return }
            let remaining = self.items.filter { FileManager.default.fileExists(atPath: $0.path) }
            guard remaining.count != self.items.count else { return }
            if remaining.isEmpty { self.dismiss() } else { self.setItems(remaining) }
        }
    }

    // MARK: Tastatur

    override func keyDown(with event: NSEvent) {
        switch event.charactersIgnoringModifiers {
        case " ": showQuickLook()
        case "\u{1b}": closeShelf()
        default: super.keyDown(with: event)
        }
    }

    /// DropMe hat kein Hauptmenü, darum laufen ⌘C, ⌘V und ⌘W hier direkt.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
              window?.isKeyWindow == true else { return super.performKeyEquivalent(with: event) }
        switch event.charactersIgnoringModifiers {
        case "c" where !items.isEmpty: copyToClipboard()
        case "v": addFromClipboard()
        case "w": closeShelf()
        default: return super.performKeyEquivalent(with: event)
        }
        return true
    }

    // MARK: Menüs

    @objc private func showActionMenu(_ sender: NSButton) {
        popUp(actionMenu(), from: sender)
    }

    private func showItemMenu() {
        let menu = NSMenu()
        for url in items {
            let entry = NSMenuItem(title: url.lastPathComponent, action: nil, keyEquivalent: "")
            entry.image = smallIcon(NSWorkspace.shared.icon(forFile: url.path))
            let sub = NSMenu()
            sub.addItem(item("Öffnen", "arrow.up.forward.app", #selector(openItem(_:)), url))
            sub.addItem(item("Im Finder anzeigen", "folder", #selector(revealItem(_:)), url))
            sub.addItem(.separator())
            sub.addItem(item("Aus Fenster entfernen", "minus.circle", #selector(removeItem(_:)), url))
            entry.submenu = sub
            menu.addItem(entry)
        }
        popUp(menu, from: pill)
    }

    private func popUp(_ menu: NSMenu, from view: NSView) {
        let y = view.isFlipped ? view.bounds.maxY + 4 : -4
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: y), in: view)
    }

    private func actionMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let hasItems = !items.isEmpty

        if hasItems {
            let openWith = NSMenuItem(title: "Öffnen mit", action: nil, keyEquivalent: "")
            openWith.image = NSImage(systemSymbolName: "arrow.up.forward.app", accessibilityDescription: nil)
            openWith.submenu = openWithMenu()
            menu.addItem(openWith)
            menu.addItem(item("Im Finder anzeigen", "folder", #selector(revealAll)))
            menu.addItem(item("Schnellansicht", "eye", #selector(showQuickLook)))
            menu.addItem(.separator())

            let services = NSSharingService.sharingServices(forItems: items)
            for service in services.prefix(4) { menu.addItem(shareItem(service)) }
            if services.count > 4 {
                let more = NSMenuItem(title: "Mehr", action: nil, keyEquivalent: "")
                more.image = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: nil)
                more.submenu = NSMenu()
                for service in services.dropFirst(4) { more.submenu?.addItem(shareItem(service)) }
                menu.addItem(more)
            }
            menu.addItem(.separator())
        }

        let paste = item("Aus Zwischenablage hinzufügen", "doc.on.clipboard", #selector(addFromClipboard))
        paste.isEnabled = NSPasteboard.general.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
        menu.addItem(paste)

        if hasItems {
            let title = items.count == 1 ? "„\(shortName(items[0]))“ kopieren" : "\(items.count) Objekte kopieren"
            menu.addItem(item(title, "doc.on.doc", #selector(copyToClipboard)))
            menu.addItem(transferMenu(title: "Kopieren nach", symbol: "arrow.right.doc.on.clipboard", move: false))
            menu.addItem(transferMenu(title: "Bewegen nach", symbol: "arrow.right.circle", move: true))
            for dest in Destination.quick {
                menu.addItem(item(dest.name, "arrow.right.circle.fill", #selector(quickCopy(_:)), dest.url))
            }
            menu.addItem(.separator())
            menu.addItem(item("Fenster leeren", "delete.left", #selector(clear)))
        } else {
            menu.addItem(.separator())
        }
        menu.addItem(item("Einstellungen …", "gearshape", #selector(openSettings)))
        return menu
    }

    private func openWithMenu() -> NSMenu {
        let menu = NSMenu()
        guard let first = items.first else { return menu }
        let workspace = NSWorkspace.shared
        var apps = workspace.urlsForApplications(toOpen: first)
        if let preferred = workspace.urlForApplication(toOpen: first) {
            apps.removeAll { $0 == preferred }
            apps.insert(preferred, at: 0)
        }
        for app in apps {
            let name = FileManager.default.displayName(atPath: app.path).replacingOccurrences(of: ".app", with: "")
            let entry = item(name, nil, #selector(openWithApp(_:)), app)
            entry.image = smallIcon(workspace.icon(forFile: app.path))
            menu.addItem(entry)
            if app == apps.first, apps.count > 1 { menu.addItem(.separator()) }
        }
        return menu
    }

    private func transferMenu(title: String, symbol: String, move: Bool) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        entry.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        let sub = NSMenu()
        let action = move ? #selector(moveTo(_:)) : #selector(copyTo(_:))
        for dest in Destination.standard + Destination.quick {
            let target = item(dest.name, nil, action, dest.url)
            target.image = smallIcon(NSWorkspace.shared.icon(forFile: dest.url.path))
            sub.addItem(target)
        }
        sub.addItem(.separator())
        sub.addItem(item("Anderer Ordner …", nil, action, nil))
        entry.submenu = sub
        return entry
    }

    private func item(_ title: String, _ symbol: String?, _ action: Selector, _ object: Any? = nil) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: action, keyEquivalent: "")
        entry.target = self
        entry.representedObject = object
        if let symbol { entry.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
        return entry
    }

    private func shareItem(_ service: NSSharingService) -> NSMenuItem {
        let entry = item(service.menuItemTitle, nil, #selector(share(_:)), service)
        entry.image = smallIcon(service.image)
        return entry
    }

    private func smallIcon(_ image: NSImage) -> NSImage {
        let copy = image.copy() as! NSImage
        copy.size = NSSize(width: 16, height: 16)
        return copy
    }

    private func shortName(_ url: URL) -> String {
        let name = url.lastPathComponent
        guard name.count > 22 else { return name }
        return "\(name.prefix(10))…\(name.suffix(10))"
    }

    // MARK: Aktionen

    @objc private func closeShelf() { dismiss() }

    func dismiss() {
        if let shelf = window as? ShelfWindow { shelf.dismiss() } else { window?.close() }
    }

    @objc private func clear() { setItems([]) }

    @objc private func revealAll() { NSWorkspace.shared.activateFileViewerSelecting(items) }

    @objc private func openItem(_ sender: NSMenuItem) {
        if let url = sender.representedObject as? URL { NSWorkspace.shared.open(url) }
    }

    @objc private func revealItem(_ sender: NSMenuItem) {
        if let url = sender.representedObject as? URL { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    }

    @objc private func removeItem(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        setItems(items.filter { $0 != url })
    }

    @objc private func openWithApp(_ sender: NSMenuItem) {
        guard let app = sender.representedObject as? URL else { return }
        NSWorkspace.shared.open(items, withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
    }

    @objc private func share(_ sender: NSMenuItem) {
        NSApp.activate(ignoringOtherApps: true)
        (sender.representedObject as? NSSharingService)?.perform(withItems: items)
    }

    @objc private func copyToClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects(items as [NSURL])
        stack.pop(from: 0.95)
    }

    @objc private func addFromClipboard() {
        receive(from: .general)
    }

    @objc private func quickCopy(_ sender: NSMenuItem) {
        guard let dir = sender.representedObject as? URL else { return }
        if transfer(to: dir, move: false) { dismiss() }
    }

    @objc private func copyTo(_ sender: NSMenuItem) {
        if let dir = (sender.representedObject as? URL) ?? pickFolder() { transfer(to: dir, move: false) }
    }

    @objc private func moveTo(_ sender: NSMenuItem) {
        if let dir = (sender.representedObject as? URL) ?? pickFolder(), transfer(to: dir, move: true) {
            dismiss()
        }
    }

    @objc private func openSettings() {
        SettingsWindow.show()
    }

    private func pickFolder() -> URL? {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Auswählen"
        return panel.runModal() == .OK ? panel.url : nil
    }

    /// Kopiert oder bewegt alle Objekte in den Ordner. Liefert true, wenn alles geklappt hat.
    @discardableResult
    private func transfer(to dir: URL, move: Bool) -> Bool {
        let fm = FileManager.default
        var result: [URL] = []
        var failure: Error?
        for url in items {
            if url.deletingLastPathComponent().standardizedFileURL == dir.standardizedFileURL {
                result.append(url)
                continue
            }
            let target = Destination.freeURL(for: url.lastPathComponent, in: dir)
            do {
                if move { try fm.moveItem(at: url, to: target) } else { try fm.copyItem(at: url, to: target) }
                result.append(move ? target : url)
            } catch {
                failure = failure ?? error
                result.append(url)
            }
        }
        setItems(result)
        if let failure {
            NSApp.activate(ignoringOtherApps: true)
            NSAlert(error: failure).runModal()
            return false
        }
        return true
    }

    // MARK: Schnellansicht

    @objc private func showQuickLook() {
        guard !items.isEmpty, let panel = QLPreviewPanel.shared() else { return }
        if panel.isVisible {
            panel.orderOut(nil)
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKey()
        window?.makeFirstResponder(self)
        panel.makeKeyAndOrderFront(nil)
    }

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = self
        panel.reloadData()
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = nil
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { items.count }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        items[index] as NSURL
    }
}

/// Runder Knopf mit Symbol, wie oben links und rechts im Fenster.
final class CircleButton: NSButton {
    private var hover = HoverFill()

    init(symbol: String) {
        super.init(frame: .zero)
        isBordered = false
        wantsLayer = true
        layer?.cornerRadius = 17
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 13, weight: .semibold))
        contentTintColor = .secondaryLabelColor
        hover.apply(to: self, animated: false)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        hover.track(self)
    }

    override func mouseEntered(with event: NSEvent) { hover.isHovered = true; hover.apply(to: self) }
    override func mouseExited(with event: NSEvent) { hover.isHovered = false; hover.apply(to: self) }

    override func mouseDown(with event: NSEvent) {
        hover.isPressed = true
        hover.apply(to: self, animated: false)
        super.mouseDown(with: event)
        hover.isPressed = false
        hover.apply(to: self)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        hover.apply(to: self, animated: false)
    }
}

/// Dezente Fläche hinter Knöpfen, heller beim Überfahren, dunkler beim Drücken.
struct HoverFill {
    var isHovered = false
    var isPressed = false
    private var area: NSTrackingArea?

    func apply(to view: NSView, animated: Bool = true) {
        let alpha: CGFloat = isPressed ? 0.18 : isHovered ? 0.13 : 0.08
        let color = view.resolved(NSColor.labelColor.withAlphaComponent(alpha))
        view.animate(view.layer, key: "backgroundColor", to: color, duration: animated ? 0.12 : 0) { $0.backgroundColor = color }
    }

    mutating func track(_ view: NSView) {
        if let area { view.removeTrackingArea(area) }
        let new = NSTrackingArea(rect: view.bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                 owner: view, userInfo: nil)
        view.addTrackingArea(new)
        area = new
    }
}

/// Zeigt bis zu drei Vorschaubilder leicht gefächert übereinander.
final class StackView: NSView {
    weak var shelf: ShelfView?
    var images: [(image: NSImage, framed: Bool)] = [] { didSet { needsDisplay = true } }

    private static let angles: [CGFloat] = [0, -7, 7]

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    static func fit(_ size: NSSize, in rect: NSRect) -> NSRect {
        guard size.width > 0, size.height > 0 else { return rect }
        let scale = min(rect.width / size.width, rect.height / size.height)
        let w = size.width * scale, h = size.height * scale
        return NSRect(x: rect.midX - w / 2, y: rect.midY - h / 2, width: w, height: h)
    }

    override func draw(_ dirtyRect: NSRect) {
        let box = bounds.insetBy(dx: 12, dy: 10)
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.22)
        shadow.shadowBlurRadius = 5
        shadow.shadowOffset = NSSize(width: 0, height: -1.5)

        let count = images.count
        for (index, entry) in images.enumerated() {
            let image = entry.image
            // Das zuletzt hinzugefügte Bild liegt oben und gerade.
            let angle = Self.angles[count - 1 - index]
            NSGraphicsContext.saveGraphicsState()
            let transform = NSAffineTransform()
            transform.translateX(by: box.midX, yBy: box.midY)
            transform.rotate(byDegrees: angle)
            transform.translateX(by: -box.midX, yBy: -box.midY)
            transform.concat()
            let rect = Self.fit(image.size, in: box)
            if entry.framed {
                let path = NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5)
                NSGraphicsContext.saveGraphicsState()
                shadow.set()
                NSColor.white.setFill()
                path.fill()
                NSGraphicsContext.restoreGraphicsState()
                path.addClip()
            } else {
                shadow.set()
            }
            image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
            NSGraphicsContext.restoreGraphicsState()
        }
    }
}

/// Pille unten im Fenster: Name bzw. Anzahl, dahinter ein Chevron. Klick öffnet die Liste.
final class PillView: NSView {
    var onClick: (() -> Void)?
    var title = "" {
        didSet {
            guard title != oldValue else { return }
            if window != nil { crossfade(label.layer, duration: 0.15) }
            label.stringValue = title
            needsLayout = true
        }
    }
    private var hover = HoverFill()

    private let label = NSTextField(labelWithString: "")
    private let chevron = NSImageView()
    private static let padding: CGFloat = 12, gap: CGFloat = 4, chevronWidth: CGFloat = 7

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        label.wantsLayer = true
        hover.apply(to: self, animated: false)
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byTruncatingMiddle
        chevron.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 9, weight: .bold))
        chevron.contentTintColor = .tertiaryLabelColor
        addSubview(label)
        addSubview(chevron)
    }

    required init?(coder: NSCoder) { fatalError() }

    var fittingWidth: CGFloat {
        ceil(label.intrinsicContentSize.width) + 6 + Self.gap + Self.chevronWidth + 2 * Self.padding
    }

    override func layout() {
        super.layout()
        layer?.cornerRadius = bounds.height / 2
        let labelHeight = label.intrinsicContentSize.height
        let labelWidth = bounds.width - 2 * Self.padding - Self.gap - Self.chevronWidth
        label.frame = NSRect(x: Self.padding, y: (bounds.height - labelHeight) / 2, width: labelWidth, height: labelHeight)
        chevron.frame = NSRect(x: label.frame.maxX + Self.gap, y: (bounds.height - 10) / 2, width: Self.chevronWidth, height: 10)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        frame.contains(point) ? self : nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        hover.track(self)
    }

    override func mouseEntered(with event: NSEvent) { hover.isHovered = true; hover.apply(to: self) }
    override func mouseExited(with event: NSEvent) { hover.isHovered = false; hover.apply(to: self) }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        hover.apply(to: self, animated: false)
    }

    override func mouseDown(with event: NSEvent) {
        hover.isPressed = true
        hover.apply(to: self, animated: false)
    }

    override func mouseUp(with event: NSEvent) {
        hover.isPressed = false
        hover.apply(to: self)
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onClick?() }
    }
}
