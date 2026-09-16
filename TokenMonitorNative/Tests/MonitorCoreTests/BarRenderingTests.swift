import XCTest
import SwiftUI
import Observation
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
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            let host = NSHostingView(rootView: FixedBarChart(points: points, granularity: .day, tint: .blue).padding(20))
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
            let geometry = ChartHoverGeometry.fittedBars(ceiling: 100, width: overlay.bounds.width, height: overlay.bounds.height, hourly: false)
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

    func testDetailPlotRetainsPreviousTargetWhenSiblingsChangeStructure() async throws {
        _ = NSApplication.shared
        var oldValues = Array(repeating: 0.0, count: 31)
        var nextValues = Array(repeating: 0.0, count: 31)
        for index in 0..<24 { oldValues[index] = 0.2 + Double(index % 4) * 0.1 }
        for index in 0..<30 { nextValues[index] = 0.1 + Double((29 - index) % 6) * 0.12 }
        let old = BarAnimationTarget(vector: .init(values: oldValues), count: 24)
        let next = BarAnimationTarget(vector: .init(values: nextValues), count: 30)
        let model = BarAnimationHarnessModel(target: old, expanded: false)
        let memory = BarAnimationMemory()
        let host = NSHostingView(rootView: BarAnimationHarness(model: model, memory: memory))
        host.sizingOptions = []
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 240, height: 500), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host; window.orderFront(nil)
        defer { window.orderOut(nil) }
        func settle(_ milliseconds: Int) async {
            let steps = max(1, milliseconds / 10)
            for _ in 0..<steps { host.layoutSubtreeIfNeeded(); try? await Task.sleep(for: .milliseconds(10)) }
        }
        func chartSnapshot() throws -> Data {
            host.displayIfNeeded()
            let rect = NSRect(x: 0, y: host.bounds.height - 136, width: 240, height: 136)
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: rect))
            host.cacheDisplay(in: rect, to: bitmap)
            return try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        }
        await settle(60)
        let before = try chartSnapshot()
        XCTAssertEqual(memory.displayed, old)
        model.target = next
        model.expanded = true // Mirrors the activity detail rows changing type and height.
        XCTAssertEqual(memory.displayed, old, "The prior frame must survive the parent update until the plot starts its transition")
        await settle(400)
        let after = try chartSnapshot()
        XCTAssertEqual(memory.displayed, next)
        XCTAssertNotEqual(after, before)
    }
}

@MainActor @Observable private final class BarAnimationHarnessModel {
    var target: BarAnimationTarget
    var expanded: Bool
    init(target: BarAnimationTarget, expanded: Bool) { self.target = target; self.expanded = expanded }
}

private struct BarAnimationHarness: View {
    @Bindable var model: BarAnimationHarnessModel
    let memory: BarAnimationMemory
    var body: some View {
        VStack(spacing: 0) {
            AnimatedBarPlot(target: model.target, tint: .blue, memory: memory)
                .frame(width: 240, height: 136)
                .id("activity-detail-trend-chart")
            if model.expanded {
                ForEach(0..<30, id: \.self) { Text("Day \($0)").frame(height: 12) }
            } else {
                Text("Collapsed").frame(height: 12)
            }
        }.frame(width: 240, alignment: .top)
    }
}
