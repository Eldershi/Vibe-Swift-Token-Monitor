import XCTest
import SwiftUI
@testable import MonitorCore
@testable import TokenMonitorNative

@MainActor final class BarRenderingTests: XCTestCase {
    func testStrokeColorContrastsWithTheFillInBothAppearances() throws {
        let accent = NSColor(srgbRed: 0.2, green: 0.4, blue: 0.8, alpha: 1)
        for (name, red, green, blue) in [(NSAppearance.Name.aqua, 0.14, 0.28, 0.56), (.darkAqua, 0.56, 0.67, 0.89)] {
            let color = try XCTUnwrap(HeatmapHoverView.barStrokeColor(accent: accent, appearance: NSAppearance(named: name)!).usingColorSpace(.sRGB))
            XCTAssertEqual(color.redComponent, red, accuracy: 0.002)
            XCTAssertEqual(color.greenComponent, green, accuracy: 0.002)
            XCTAssertEqual(color.blueComponent, blue, accuracy: 0.002)
        }
    }

    func testRenderedHighlightChangesVisiblePixelsWithoutEscapingCapsule() async throws {
        _ = NSApplication.shared
        let points = [100.0, 50, 1, 0.1, 0, nil].enumerated().map {
            TrendPoint(date: Date(timeIntervalSince1970: Double($0.offset) * 86400), tokens: $0.element, cost: nil)
        }
        let geometry = ChartHoverGeometry.bars(ceiling: 100, slot: 7, height: 136)
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            let host = NSHostingView(rootView: FixedBarChart(points: points, monthly: false, tint: .blue).padding(20))
            host.sizingOptions = []
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.appearance = NSAppearance(named: name)
            window.contentView = host; window.orderFront(nil)
            defer { window.orderOut(nil) }
            for _ in 0..<5 { host.layoutSubtreeIfNeeded(); try await Task.sleep(for: .milliseconds(30)) }
            func find(_ view: NSView) -> HeatmapHoverView? {
                if let overlay = view as? HeatmapHoverView { return overlay }
                return view.subviews.lazy.compactMap { find($0) }.first
            }
            let overlay = try XCTUnwrap(find(host))
            XCTAssertTrue(overlay.wantsLayer)
            let parent = try XCTUnwrap(overlay.superview)
            XCTAssertTrue(parent.subviews.last === overlay)
            func snapshot() throws -> NSBitmapImageRep {
                host.displayIfNeeded()
                let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: bitmap)
                return bitmap
            }
            let baseline = try snapshot()
            for index in 0..<4 {
                let rect = geometry.rect(at: index, points: points)
                overlay.show(at: NSPoint(x: rect.midX, y: rect.midY))
                XCTAssertEqual(overlay.selectedIndex, index)
                overlay.displayIfNeeded()
                let highlighted = try snapshot()
                XCTAssertNotEqual(baseline.tiffRepresentation, highlighted.tiffRepresentation, "Actual hosted chart must visibly change")
                if let output = ProcessInfo.processInfo.environment["TOKEN_MONITOR_RENDER_DIR"] {
                    let directory = URL(fileURLWithPath: output)
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    try highlighted.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent("bar-\(name.rawValue)-\(index).png"))
                }
                // Overlay-only raster verifies that its drawing never extends beyond the capsule.
                let image = try XCTUnwrap(overlay.bitmapImageRepForCachingDisplay(in: overlay.bounds))
                overlay.cacheDisplay(in: overlay.bounds, to: image)
                let scaleX = CGFloat(image.pixelsWide) / overlay.bounds.width
                let scaleY = CGFloat(image.pixelsHigh) / overlay.bounds.height
                var painted = 0
                for y in 0..<image.pixelsHigh {
                    for x in 0..<image.pixelsWide where image.colorAt(x: x, y: y)!.alphaComponent > 0.01 {
                        painted += 1
                        let pixel = NSRect(x: CGFloat(x) / scaleX, y: CGFloat(y) / scaleY, width: 1 / scaleX, height: 1 / scaleY)
                        XCTAssertTrue(rect.insetBy(dx: -1 / scaleX, dy: -1 / scaleY).intersects(pixel), "Highlight may not expand beyond bar bounds")
                    }
                }
                XCTAssertGreaterThan(painted, 0)
                overlay.clear()
            }
        }
    }
}
