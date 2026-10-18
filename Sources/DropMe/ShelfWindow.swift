import AppKit
import Quartz

/// Schwebendes Fenster ohne Rahmen, das die App nicht aktiviert.
final class ShelfWindow: NSPanel {
    static let size = NSSize(width: 200, height: 210)
    static let cornerRadius: CGFloat = 34

    var onClose: (() -> Void)?
    let shelf = ShelfView(frame: NSRect(origin: .zero, size: ShelfWindow.size))

    init(center: NSPoint) {
        var frame = NSRect(origin: .zero, size: Self.size)
        frame.origin = NSPoint(x: center.x - frame.width / 2, y: center.y - frame.height / 2)
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(center, $0.frame, false) }) ?? NSScreen.main {
            let visible = screen.visibleFrame
            frame.origin.x = min(max(frame.origin.x, visible.minX + 8), visible.maxX - frame.width - 8)
            frame.origin.y = min(max(frame.origin.y, visible.minY + 8), visible.maxY - frame.height - 8)
        }
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)

        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovable = true
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        contentView = makeBackground()
        initialFirstResponder = shelf
    }

    private var isDismissing = false

    /// Erscheint mit kurzem Einblenden und federt dabei aus leicht kleinerer Größe auf.
    func present() {
        alphaValue = 0
        orderFrontRegardless()
        DispatchQueue.main.async { self.invalidateShadow() }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            animator().alphaValue = 1
        }
        contentView?.pop(from: 0.92)
    }

    /// Blendet aus und schrumpft minimal, dann wird geschlossen.
    func dismiss() {
        guard !isDismissing else { return }
        isDismissing = true
        if let content = contentView, let layer = content.layer, !content.reduceMotion {
            let shrink = CABasicAnimation(keyPath: "transform")
            shrink.toValue = content.centeredScale(0.95)
            shrink.duration = 0.14
            shrink.timingFunction = CAMediaTimingFunction(name: .easeIn)
            shrink.fillMode = .forwards
            shrink.isRemovedOnCompletion = false
            layer.add(shrink, forKey: "dismiss")
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.14
            animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.close()
        })
    }

    override var canBecomeKey: Bool { true }

    override func close() {
        if QLPreviewPanel.sharedPreviewPanelExists(),
           let panel = QLPreviewPanel.shared(), panel.isVisible,
           (panel.dataSource as AnyObject?) === shelf {
            panel.orderOut(nil)
        }
        super.close()
        onClose?()
        onClose = nil
    }

    /// Hintergrund in einer abgerundeten, beschnittenen Hülle, damit Schatten und Ecken sauber rund sind.
    private func makeBackground() -> NSView {
        let container = NSView(frame: shelf.frame)
        container.wantsLayer = true
        container.layer?.cornerRadius = Self.cornerRadius
        container.layer?.cornerCurve = .continuous
        container.layer?.masksToBounds = true
        let background = makeMaterial()
        background.frame = container.bounds
        background.autoresizingMask = [.width, .height]
        container.addSubview(background)
        return container
    }

    private func makeMaterial() -> NSView {
        shelf.autoresizingMask = [.width, .height]
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView(frame: shelf.frame)
            glass.cornerRadius = Self.cornerRadius
            glass.contentView = shelf
            return glass
        }
        let effect = NSVisualEffectView(frame: shelf.frame)
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.addSubview(shelf)
        return effect
    }
}
