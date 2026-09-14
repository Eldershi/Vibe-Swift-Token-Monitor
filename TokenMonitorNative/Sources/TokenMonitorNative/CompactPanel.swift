import AppKit

/// Enforce the viewport minimum for both interactive resizing and restored frames.
@MainActor final class CompactPanel: NSPanel, NSWindowDelegate {
    static let minimumContentSize = NSSize(width: 320, height: 400)

    func installSizeConstraints() {
        delegate = self
        contentMinSize = Self.minimumContentSize
        minSize = frameRect(forContentRect: NSRect(origin: .zero, size: Self.minimumContentSize)).size
        setFrame(frame, display: false)
    }

    private func boundedSize(_ proposed: NSSize) -> NSSize {
        let minimum = frameRect(forContentRect: NSRect(origin: .zero, size: Self.minimumContentSize)).size
        return NSSize(width: max(proposed.width, minimum.width), height: max(proposed.height, minimum.height))
    }

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        var bounded = frameRect
        bounded.size = boundedSize(frameRect.size)
        bounded.origin.y += frameRect.height - bounded.height // Keep the top edge in place.
        super.setFrame(bounded, display: flag)
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        boundedSize(frameSize)
    }
}
