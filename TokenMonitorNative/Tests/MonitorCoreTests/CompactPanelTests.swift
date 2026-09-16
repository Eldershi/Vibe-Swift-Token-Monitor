import XCTest
import SwiftUI
@testable import TokenMonitorNative

@MainActor final class CompactPanelTests: XCTestCase {
    func testHostedWindowLocksWidthAndStillResizesVertically() async {
        let panel = CompactPanel(contentRect: NSRect(x: 0, y: 0, width: 320, height: 460), styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.toolbar = NSToolbar(identifier: "MinimumWidthTest")
        let host = NSHostingView(rootView: Text("Empty state").frame(minWidth: 320))
        host.sizingOptions = []
        panel.contentView = host
        panel.installSizeConstraints()
        defer { panel.orderOut(nil) }
        for width in [200.0, 320, 1000, 180] {
            panel.setFrame(NSRect(x: 20, y: 20, width: width, height: 700), display: false)
            host.layoutSubtreeIfNeeded()
            try? await Task.sleep(for: .milliseconds(20))
            XCTAssertEqual(panel.contentRect(forFrameRect: panel.frame).width, 320, accuracy: 1)
            XCTAssertEqual(panel.frame.height, 700, accuracy: 1)
        }
        // AppKit's interactive resize delegate must enforce the same boundary.
        let size = panel.windowWillResize(panel, to: NSSize(width: 100, height: 700))
        XCTAssertEqual(size.width, 320, accuracy: 1)
        XCTAssertEqual(size.height, 700, accuracy: 1)
        panel.setContentSize(NSSize(width: 100, height: 600))
        XCTAssertEqual(panel.contentRect(forFrameRect: panel.frame).width, 320, accuracy: 1)
    }
}
