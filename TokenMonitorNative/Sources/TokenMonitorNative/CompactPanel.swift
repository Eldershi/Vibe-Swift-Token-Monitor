import AppKit

/// Keep the compact panel at one content width while allowing vertical resizing.
@MainActor final class CompactPanel: NSPanel, NSWindowDelegate {
    static let contentWidth: CGFloat = 320
    static let minimumContentSize = NSSize(width: contentWidth, height: 400)

    func installSizeConstraints() {
        delegate = self
        contentMinSize = Self.minimumContentSize
        contentMaxSize = NSSize(width: Self.contentWidth, height: .greatestFiniteMagnitude)
        minSize = frameRect(forContentRect: NSRect(origin: .zero, size: Self.minimumContentSize)).size
        maxSize = NSSize(width: minSize.width, height: .greatestFiniteMagnitude)
        setFrame(frame, display: false)
    }

    private func boundedSize(_ proposed: NSSize) -> NSSize {
        let minimum = frameRect(forContentRect: NSRect(origin: .zero, size: Self.minimumContentSize)).size
        return NSSize(width: minimum.width, height: max(proposed.height, minimum.height))
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
