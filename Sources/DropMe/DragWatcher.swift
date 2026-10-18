import AppKit

/// Reports when files are dragged in another app while Shift is held down.
/// Only looks at the types on the drag pasteboard, never at its contents.
final class DragWatcher {
    var onTrigger: ((NSPoint) -> Void)?
    /// Mouse button released after a shelf was opened.
    var onDragEnded: (() -> Void)?

    private let pasteboard = NSPasteboard(name: .drag)
    private var changeCountAtMouseDown = 0
    private var fired = false
    private var monitors: [Any] = []

    private static let fileTypes = Set<NSPasteboard.PasteboardType>(
        [.fileURL] + NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) }
    )

    func start() {
        monitor(.leftMouseDown) { [weak self] in
            guard let self else { return }
            self.changeCountAtMouseDown = self.pasteboard.changeCount
            self.fired = false
        }
        monitor(.leftMouseDragged) { [weak self] in self?.dragged() }
        monitor(.leftMouseUp) { [weak self] in
            guard let self, self.fired else { return }
            self.fired = false
            self.onDragEnded?()
        }
    }

    private func monitor(_ mask: NSEvent.EventTypeMask, _ handler: @escaping () -> Void) {
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { _ in handler() }) {
            monitors.append(monitor)
        }
    }

    private func dragged() {
        guard !fired,
              NSEvent.modifierFlags.contains(.shift),
              pasteboard.changeCount != changeCountAtMouseDown,
              let types = pasteboard.types,
              !Self.fileTypes.isDisjoint(with: types)
        else { return }
        fired = true
        onTrigger?(NSEvent.mouseLocation)
    }
}
