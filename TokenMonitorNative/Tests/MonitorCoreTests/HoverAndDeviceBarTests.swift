import XCTest
import SwiftUI
@testable import MonitorCore
@testable import TokenMonitorNative

final class DeviceUsageComparisonTests: XCTestCase {
    private func device(_ id: String, _ value: String, expired: Bool = false) throws -> Device {
        try JSONDecoder().decode(Device.self, from: Data("""
        {"deviceId":"\(id)","periods":{"month":{"totalTokens":\(value),"clients":{"codex":\(value),"claude":0}},"allTime":{"totalTokens":100}},"periodWindows":{"month":{"endsAt":"\(expired ? "2000" : "2099")-01-01T00:00:00Z"}}}
        """.utf8))
    }
    func testRatiosAndToolPeriodChanges() throws {
        let devices = try [device("a", "100"), device("b", "25"), device("c", "0"), device("d", "100"), device("old", "1000", expired: true), device("invalid", "-5")]
        let month = DeviceUsageComparison.fractions(devices: devices, tool: "codex", period: .month, now: Date())
        XCTAssertEqual(month, ["a":1, "b":0.25, "c":0, "d":1])
        let zero = DeviceUsageComparison.fractions(devices: devices, tool: "claude", period: .month, now: Date())
        XCTAssertTrue(zero.values.allSatisfy { $0 == 0 })
        XCTAssertTrue(DeviceUsageComparison.fractions(devices: devices, tool: "missing", period: .month, now: Date()).isEmpty)
        XCTAssertEqual(DeviceUsageComparison.fractions(devices: devices, tool: "", period: .allTime, now: Date()).count, 6)
    }
    @MainActor func testPreferenceDefaultAndDiskRoundTrip() throws {
        let old = try JSONDecoder().decode(Preferences.self, from: Data(#"{"schemaVersion":3}"#.utf8))
        XCTAssertFalse(old.showHomeDeviceUsageBars)
        let runtime = RuntimePreferences(old)
        runtime.showHomeDeviceUsageBars = true
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = PreferencesFile(url: directory.appendingPathComponent("prefs.json"))
        try file.save(runtime.snapshot)
        XCTAssertTrue(try file.load().showHomeDeviceUsageBars)
        XCTAssertTrue(runtime.snapshot.hiddenHomeSections.contains(.devices))
    }
}

@MainActor final class HeatmapHoverTests: XCTestCase {
    func testExactCellHitTestingIncludingGapsAndEdges() {
        for index in [0, 6, 7, 111] {
            let rect = HeatmapHitTesting.rect(at: index)
            XCTAssertEqual(HeatmapHitTesting.index(at: NSPoint(x: rect.midX, y: rect.midY), count: 112), index)
            XCTAssertNil(HeatmapHitTesting.index(at: NSPoint(x: rect.maxX + 1, y: rect.midY), count: 112))
        }
        for point in [NSPoint(x: 15, y: 10), NSPoint(x: 20, y: 78), NSPoint(x: 20, y: 88), NSPoint(x: 18, y: 16)] {
            XCTAssertNil(HeatmapHitTesting.index(at: point, count: 112))
        }
    }
    func testTooltipStaysInsideNarrowWindowAndAvoidsCell() {
        let bounds = NSRect(x: 50, y: 40, width: 320, height: 500)
        for pointer in [NSPoint(x: 60, y: 80), NSPoint(x: 360, y: 520), NSPoint(x: 200, y: 260)] {
            let cell = NSRect(x: pointer.x - 3, y: pointer.y - 3, width: 7, height: 7)
            let frame = HeatmapHitTesting.tooltipFrame(pointer: pointer, cell: cell, size: NSSize(width: 160, height: 52), bounds: bounds)
            XCTAssertTrue(bounds.contains(frame)); XCTAssertFalse(frame.intersects(cell))
        }
    }
    func testOverlayLifecycleAndScrolledCoordinates() async {
        let view = HistoryNativeScroll(content: AnyView(Color.clear))
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 320, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        view.documentSize = NSSize(width: 600, height: 104)
        let points = (0..<350).map { TrendPoint(date: Date(timeIntervalSince1970: Double($0) * 86400), tokens: $0 == 0 ? nil : Double($0), cost: nil) }
        view.configureHeatmapHover(enabled: true, points: points)
        window.orderFront(nil); view.layout()
        defer { view.heatmapOverlay?.clear(); window.orderOut(nil) }
        let overlay = view.heatmapOverlay!
        let cell = HeatmapHitTesting.rect(at: 210)
        overlay.show(at: NSPoint(x: cell.midX, y: cell.midY))
        XCTAssertEqual(overlay.selectedIndex, 210)
        let stableFrame = overlay.tooltip?.frame
        overlay.show(at: NSPoint(x: cell.midX + 1, y: cell.midY + 1))
        XCTAssertEqual(overlay.tooltip?.frame, stableFrame)
        XCTAssertTrue(overlay.tooltip?.superview === window.contentView?.superview)
        XCTAssertNil(overlay.tooltip?.hitTest(.zero))
        XCTAssertTrue(window.childWindows?.isEmpty ?? true)
        let offset = view.position.offset
        overlay.clear()
        XCTAssertEqual(view.position.offset, offset)
        XCTAssertNil(overlay.selectedIndex)
        XCTAssertNil(overlay.tooltip?.superview)
        overlay.show(at: NSPoint(x: cell.midX, y: cell.midY))
        view.contentView.scroll(to: NSPoint(x: 270, y: 0))
        XCTAssertNil(overlay.selectedIndex)
        overlay.show(at: NSPoint(x: cell.midX, y: cell.midY))
        overlay.points = []
        XCTAssertNil(overlay.selectedIndex)
    }
    func testBarHitRegionsKeepZeroAndMissingDaysQueryable() {
        let points = [100.0, 50, 0, nil].enumerated().map { TrendPoint(date: Date(timeIntervalSince1970: Double($0.offset) * 86400), tokens: $0.element, cost: nil) }
        let geometry = ChartHoverGeometry.bars(ceiling: 100, slot: 7, height: 136)
        for index in points.indices {
            XCTAssertEqual(geometry.index(at: NSPoint(x: 19 + index * 7, y: 20), points: points), index)
        }
        XCTAssertNil(geometry.index(at: NSPoint(x: 22.5, y: 20), points: points))
        XCTAssertNil(geometry.index(at: NSPoint(x: 19, y: 145), points: points))
        XCTAssertEqual(geometry.rect(at: 1, points: points).height, 68)
        XCTAssertEqual(geometry.rect(at: 2, points: points).height, 1)
    }
    func testBarTooltipAnchorsToBarWithoutCreatingPopupWindow() throws {
        let view = HistoryNativeScroll(content: AnyView(Color.clear))
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 320, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = view
        view.documentSize = NSSize(width: 320, height: 160)
        let points = [100.0, 50].enumerated().map { TrendPoint(date: Date(timeIntervalSince1970: Double($0.offset) * 86400), tokens: $0.element, cost: nil) }
        view.configureHeatmapHover(enabled: true, points: points, tint: .purple, geometry: .bars(ceiling: 100, slot: 7, height: 136))
        window.orderFront(nil); view.layout()
        defer { view.heatmapOverlay?.clear(); window.orderOut(nil) }
        let overlay = try XCTUnwrap(view.heatmapOverlay)
        overlay.show(at: NSPoint(x: 26, y: 40))
        let panel = try XCTUnwrap(overlay.tooltip)
        let frame = panel.frame
        XCTAssertGreaterThan(frame.width, 0); XCTAssertGreaterThan(frame.height, 0)
        XCTAssertTrue(window.childWindows?.isEmpty ?? true)
        overlay.show(at: NSPoint(x: 26, y: 130))
        XCTAssertEqual(panel.frame, frame)
        XCTAssertEqual(overlay.selectedIndex, 1)
        overlay.show(at: NSPoint(x: 19, y: 100))
        XCTAssertTrue(overlay.tooltip === panel)
        XCTAssertEqual(overlay.selectedIndex, 0)
    }

    func testBarHighlightUsesTheSameCapsuleGeometryIncludingShortBars() {
        let geometry = ChartHoverGeometry.bars(ceiling: 100, slot: 7, height: 136)
        let points = [100.0, 1, 0.01].map { TrendPoint(date: Date(), tokens: $0, cost: nil) }
        for index in points.indices {
            let rect = geometry.rect(at: index, points: points)
            XCTAssertEqual(geometry.cornerRadius(for: rect), min(2.5, rect.height / 2))
            let line = min(1, rect.height)
            XCTAssertEqual(max(0, geometry.cornerRadius(for: rect) - line / 2), min((rect.width - line) / 2, (rect.height - line) / 2), accuracy: 0.0001)
        }
    }
    func testHomeChartsAfterVerticalScrollAndDetailChartUseSameTooltipLayer() throws {
        let page = NSScrollView(frame: NSRect(x: 0, y: 0, width: 320, height: 400))
        let document = FlippedChartTestDocument(frame: NSRect(x: 0, y: 0, width: 320, height: 1200))
        page.documentView = document
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 320, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = page
        let heatmap = HistoryNativeScroll(content: AnyView(Color.clear))
        let bars = HistoryNativeScroll(content: AnyView(Color.clear))
        heatmap.frame = NSRect(x: 0, y: 0, width: 320, height: 104)
        bars.frame = NSRect(x: 0, y: 700, width: 320, height: 160)
        document.addSubview(heatmap); document.addSubview(bars)
        let points = [100.0, 50].map { TrendPoint(date: Date(), tokens: $0, cost: nil) }
        heatmap.documentSize = NSSize(width: 320, height: 104)
        bars.documentSize = NSSize(width: 320, height: 160)
        heatmap.configureHeatmapHover(enabled: true, points: points)
        bars.configureHeatmapHover(enabled: true, points: points, geometry: .bars(ceiling: 100, slot: 7, height: 136))
        window.orderFront(nil); heatmap.layout(); bars.layout()
        defer { heatmap.heatmapOverlay?.clear(); bars.heatmapOverlay?.clear(); window.orderOut(nil) }
        page.contentView.scroll(to: NSPoint(x: 0, y: 650))
        bars.heatmapOverlay?.show(at: NSPoint(x: 19, y: 70))
        XCTAssertEqual(bars.heatmapOverlay?.selectedIndex, 0)
        XCTAssertTrue(bars.heatmapOverlay?.tooltip?.superview === window.contentView?.superview)
        heatmap.heatmapOverlay?.show(at: NSPoint(x: 19, y: 10))
        XCTAssertNil(heatmap.heatmapOverlay?.selectedIndex)
        XCTAssertEqual(bars.heatmapOverlay?.selectedIndex, 0)
        page.contentView.scroll(to: .zero)
        bars.heatmapOverlay?.show(at: NSPoint(x: 19, y: 70))
        XCTAssertNil(bars.heatmapOverlay?.selectedIndex)
        heatmap.heatmapOverlay?.show(at: NSPoint(x: 19, y: 10))
        XCTAssertEqual(heatmap.heatmapOverlay?.selectedIndex, 0)
        XCTAssertTrue(window.childWindows?.isEmpty ?? true)
    }

}

private final class FlippedChartTestDocument: NSView { override var isFlipped: Bool { true } }
