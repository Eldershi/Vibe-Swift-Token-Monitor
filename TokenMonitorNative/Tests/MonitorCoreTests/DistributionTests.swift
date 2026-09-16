import XCTest
import AppKit
@testable import MonitorCore
@testable import TokenMonitorNative

final class DistributionTests: XCTestCase {
    func testSharedDataMotionUsesSlowEndpoints() {
        XCTAssertEqual(DataMotion.progress(0), 0)
        XCTAssertEqual(DataMotion.progress(1), 1)
        XCTAssertLessThan(DataMotion.progress(0.25), 0.25)
        XCTAssertGreaterThan(DataMotion.progress(0.75), 0.75)
        XCTAssertEqual(DataMotion.duration, 0.28)
    }
    func testTopFiveConserveTotalAndExcludeInvalidValues() {
        let rows = (1...8).map { DistributionItem(id: "\($0)", name: "Item \($0)", value: Double($0)) }
        let result = Distribution(rows + [.init(id: "bad", name: "Bad", value: .nan), .init(id: "negative", name: "Negative", value: -1)])
        XCTAssertEqual(result.total, 36)
        XCTAssertEqual(result.items.map(\.id), ["8", "7", "6", "5", "4", "aggregate:other"])
        XCTAssertEqual(result.items.last?.value, 6)
        XCTAssertEqual(result.items.reduce(0) { $0 + result.fraction($1) }, 1, accuracy: 1e-12)
    }
    func testZerosTiesAndOverflow() {
        let result = Distribution([.init(id: "b", name: "B", value: 0), .init(id: "a", name: "A", value: 0)])
        XCTAssertEqual(result.items.map(\.id), ["a", "b"])
        XCTAssertEqual(result.fraction(result.items[0]), 0)
        XCTAssertTrue(Distribution([.init(id: "a", name: "A", value: .greatestFiniteMagnitude), .init(id: "b", name: "B", value: .greatestFiniteMagnitude)]).items.isEmpty)
    }
    func testDonutHitGeometryMatchesSectorsAndExcludesHoleAndGap() {
        let result = Distribution([.init(id: "a", name: "A", value: 1), .init(id: "b", name: "B", value: 1)])
        let paths = DonutGeometry.paths(result, size: NSSize(width: 184, height: 184))
        XCTAssertTrue(paths[0].contains(CGPoint(x: 170, y: 92)))
        XCTAssertTrue(paths[1].contains(CGPoint(x: 14, y: 92)))
        for point in [CGPoint(x: 92, y: 92), CGPoint(x: 92, y: 10), CGPoint(x: 0, y: 0)] {
            XCTAssertFalse(paths.contains { $0.contains(point) })
        }
        let single = DonutGeometry.paths(Distribution([.init(id: "a", name: "A", value: 1)]), size: NSSize(width: 184, height: 184))
        XCTAssertTrue(single[0].contains(CGPoint(x: 92, y: 10)))
        XCTAssertFalse(single[0].contains(CGPoint(x: 92, y: 92)))
    }
    func testRoundedCornersAndTinySectors() {
        let chart = Distribution([.init(id: "a", name: "A", value: 1), .init(id: "b", name: "B", value: 1)])
        let paths = DonutGeometry.paths(chart, size: NSSize(width: 184, height: 184))
        // Near the sharp outer corner, inside the original unrounded sector.
        XCTAssertFalse(paths[0].contains(CGPoint(x: 94, y: 9.1)))
        XCTAssertTrue(paths[0].contains(CGPoint(x: 100, y: 11)))
        let tiny = Distribution([.init(id: "a", name: "A", value: 100), .init(id: "b", name: "B", value: 0.00001)])
        for path in DonutGeometry.paths(tiny, size: NSSize(width: 184, height: 184)) {
            XCTAssertTrue(path.boundingBox.minX.isFinite)
            XCTAssertTrue(path.boundingBox.maxY.isFinite)
            XCTAssertFalse(path.contains(CGPoint(x: 92, y: 92)))
        }
    }
    func testDonutTransitionMatchesStableIdentitiesAndConservesSweep() {
        let old = [DistributionItem(id: "a", name: "A", value: 3), .init(id: "b", name: "B", value: 1)]
        let target = Distribution([.init(id: "b", name: "B", value: 1), .init(id: "c", name: "C", value: 1)])
        let state = DonutTransition.state(currentItems: old, currentFractions: [0.75, 0.25], target: target)
        XCTAssertEqual(state.items.map(\.id), ["a", "b", "c"])
        XCTAssertEqual(state.start, [0.75, 0.25, 0])
        XCTAssertEqual(state.end, [0, 0.5, 0.5])
        XCTAssertEqual(DonutTransition.interpolate(state, progress: 0.5).reduce(0, +), 1, accuracy: 1e-12)
    }
    @MainActor func testPreferenceCompatibilityAndRuntimeRoundTrip() throws {
        let old = try JSONDecoder().decode(Preferences.self, from: Data(#"{"schemaVersion":3}"#.utf8))
        XCTAssertTrue(old.menuBarTokens); XCTAssertTrue(old.menuBarShortQuota); XCTAssertFalse(old.menuBarWeeklyQuota)
        XCTAssertEqual(old.menuBarStyle, .text)
        let runtime = RuntimePreferences(old)
        runtime.menuBarTokens = false; runtime.menuBarShortQuota = false; runtime.menuBarWeeklyQuota = true; runtime.menuBarStyle = .rings
        let decoded = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(runtime.snapshot))
        XCTAssertFalse(decoded.menuBarTokens); XCTAssertFalse(decoded.menuBarShortQuota); XCTAssertTrue(decoded.menuBarWeeklyQuota)
        XCTAssertEqual(decoded.menuBarStyle, .rings); XCTAssertEqual(decoded.schemaVersion, 4)
        let unknown = try JSONDecoder().decode(Preferences.self, from: Data(#"{"menuBarStyle":"future"}"#.utf8))
        XCTAssertEqual(unknown.menuBarStyle, .text)
    }
}

final class QuotaPresentationTests: XCTestCase {
    let now = DateCodec.parse("2026-09-16T00:00:00Z")!
    func provider(percent: String = "0", resets: String = "2026-09-17T00:00:00Z", extra: String = "") throws -> QuotaProvider {
        try JSONDecoder().decode(QuotaProvider.self, from: Data("""
        {"provider":"codex","status":"ok","updatedAt":"2026-09-16T00:00:00Z","windows":[{"kind":"session","windowMinutes":300,"remainingPercent":\(percent),"resetsAt":"\(resets)"\(extra)},{"kind":"weekly","remainingPercent":48}]}
        """.utf8))
    }
    func testZeroExpiredMissingAndHiddenMeter() throws {
        let zero = try provider()
        XCTAssertEqual(QuotaPresentation.percent(zero.windows[0], provider: zero, now: now, threshold: 600_000), 0)
        for report in try [provider(percent: "null"), provider(percent: "101"), provider(resets: "2026-09-16T00:00:00Z"), provider(extra: ",\"showMeter\":false")] {
            XCTAssertNil(QuotaPresentation.percent(report.windows[0], provider: report, now: now, threshold: 600_000))
        }
        XCTAssertNil(QuotaPresentation.percent(zero.windows[0], provider: zero, now: now.addingTimeInterval(601), threshold: 600_000))
    }
    func testTopologyIgnoresValuesAndResetChangesButTracksWindows() throws {
        let first = try provider()
        XCTAssertEqual(QuotaPresentation.topology([first]), QuotaPresentation.topology([try provider(percent: "72", resets: "2026-09-18T00:00:00Z")]))
        XCTAssertNotEqual(QuotaPresentation.topology([first]), QuotaPresentation.topology([first, first]))
        XCTAssertEqual(QuotaPresentation.shortLabel(first.windows[0], weekly: false), "5h")
        XCTAssertEqual(QuotaPresentation.shortLabel(first.windows[1], weekly: true), "7d")
    }
    @MainActor func testMenuSelectionDoesNotMixAccountsAndExpires() throws {
        let reports = try [provider(percent: "72"), provider(percent: "20")]
        let store = AppStore(ephemeral: true)
        store.now = now
        func snapshot(_ providers: [QuotaProvider]) throws -> Stats {
            let limits = String(decoding: try JSONEncoder().encode(providers), as: UTF8.self)
            return try JSONDecoder().decode(Stats.self, from: Data("""
            {"updatedAt":"2026-09-16T00:00:00Z","periods":{},"devices":[],"limits":{"providers":\(limits)}}
            """.utf8))
        }
        store.stats = try snapshot(reports)
        store.preferences.menuBarWeeklyQuota = true
        XCTAssertEqual(store.menuQuotaMetrics.map(\.percent), [72, 48])
        store.selectMenuQuotaReport(1)
        XCTAssertEqual(store.menuQuotaMetrics.map(\.percent), [20, 48])
        store.stats = try snapshot([reports[0]])
        XCTAssertNil(store.menuQuotaSelection)
        XCTAssertEqual(store.menuQuotaMetrics.map(\.percent), [72, 48])
        store.now = now.addingTimeInterval(601)
        XCTAssertTrue(store.menuQuotaMetrics.allSatisfy { $0.percent == nil })
        store.preferences.menuBarTokens = false; store.preferences.menuBarShortQuota = false; store.preferences.menuBarWeeklyQuota = false
        XCTAssertTrue(store.menuQuotaMetrics.isEmpty)
    }
    @MainActor func testMenuImagesReuseUnchangedDataAndRender() throws {
        let cache = MenuBarImageCache()
        let metrics = [MenuQuotaMetric(label: "5h", percent: 72), MenuQuotaMetric(label: "7d", percent: 0)]
        let image = cache.image(tokens: "12.3M", metrics: metrics, suffix: " β")
        XCTAssertTrue(image.isTemplate); XCTAssertEqual(image.size.height, 18)
        XCTAssertGreaterThan(image.size.width, 100)
        XCTAssertNotNil(image.tiffRepresentation)
        XCTAssertTrue(image === cache.image(tokens: "12.3M", metrics: metrics, suffix: " β"))
        XCTAssertFalse(image === cache.image(tokens: nil, metrics: metrics, suffix: " β"))
    }
}

final class ChartStyleTests: XCTestCase {
    func testStableSlotsAcrossSortSubsetRestartAndNewItems() throws {
        var style = ChartStyle()
        let ids = ["model:a", "model:b", "model:c", "model:d", "model:e"]
        style.slots = style.resolvedSlots(ids)
        XCTAssertEqual(Set(ids.compactMap { style.slots[$0] }).count, 5)
        let decoded = try JSONDecoder().decode(ChartStyle.self, from: JSONEncoder().encode(style))
        XCTAssertEqual(decoded.resolvedSlots(ids.reversed()), style.slots)
        let changed = decoded.resolvedSlots(["model:z", "model:a", "model:c"])
        for id in ids { XCTAssertEqual(changed[id], style.slots[id]) }
        XCTAssertEqual(style.color(id: "aggregate:other", activeIDs: ids), style.other)
        XCTAssertEqual(style.color(id: "quota:remaining", activeIDs: ids), style.remaining)
    }
    func testPresetsHaveEightDistinctColorsAndCustomRoundTrip() throws {
        for preset in ["vivid", "soft", "contrast"] {
            let colors = ChartStyle.palette(preset)
            XCTAssertEqual(colors.count, 8)
            XCTAssertEqual(Set(colors.map { "\($0.red):\($0.green):\($0.blue)" }).count, 8)
        }
        var style = ChartStyle(); style.preset = "custom"; style.customColors[0] = .init(red: 0.2, green: 0.4, blue: 0.6)
        XCTAssertEqual(try JSONDecoder().decode(ChartStyle.self, from: JSONEncoder().encode(style)), style)
    }
}

final class DonutHoverRegressionTests: XCTestCase {
    @MainActor func testExpandedEdgeKeepsTooltipAndCenterClearsIt() async throws {
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 184, height: 184), styleMask: [.titled], backing: .buffered, defer: false)
        let view = DonutNativeView(frame: NSRect(x: 0, y: 0, width: 184, height: 184))
        window.contentView = view
        view.configure(Distribution([.init(id: "a", name: "A", value: 1), .init(id: "b", name: "B", value: 1)]), cost: false, quota: false, style: ChartStyle())
        defer { window.contentView = nil }
        func tooltipVisible() -> Bool { view.superview?.subviews.contains { $0 is ChartTooltipView } == true }
        // Enter the base outline, then move beyond it but inside the enlarged outline.
        view.show(at: NSPoint(x: 172, y: 92))
        XCTAssertTrue(tooltipVisible())
        try await Task.sleep(for: .milliseconds(250))
        view.show(at: NSPoint(x: 178, y: 92))
        XCTAssertTrue(tooltipVisible())
        view.show(at: NSPoint(x: 92, y: 92))
        XCTAssertFalse(tooltipVisible())
        // The enlarged outline cannot start a new hover after leaving the chart.
        try await Task.sleep(for: .milliseconds(250))
        view.show(at: NSPoint(x: 178, y: 92))
        XCTAssertFalse(tooltipVisible())
    }
}
