import XCTest
import AppKit
@testable import MonitorCore
@testable import TokenMonitorNative

final class DistributionTests: XCTestCase {
    func testQuotaAllocationPreservesOfficialRemainingAndUnknownUsage() {
        func row(_ id: String, _ quota: Double, tokens: Double = 1) -> ConversionSnapshot.Row {
            .init(id: id, tokens: tokens, weight: 1, share: nil, quota: quota, basis: nil, sampleFrom: nil, sampleTo: nil)
        }
        let partial = QuotaChartData.allocation(remaining: 17, rows: [row("A", 40), row("B", 30)])
        XCTAssertEqual(partial.total, 100, accuracy: 1e-9)
        XCTAssertEqual(partial.items.first { $0.id == "quota:remaining" }?.value, 17)
        XCTAssertEqual(partial.items.first { $0.id == "quota:used" }?.value, 13)
        let many = QuotaChartData.allocation(remaining: 1, rows: (1...9).map { row(String($0), 11) })
        XCTAssertEqual(many.total, 100, accuracy: 1e-9)
        XCTAssertEqual(many.items.count, 10)
        XCTAssertEqual(many.items.filter { $0.id.hasPrefix("device:") }.count, 9)
        let legend = QuotaChartData.allocationLegend(many)
        XCTAssertEqual(legend.count, 4)
        XCTAssertEqual(legend.filter { $0.id.hasPrefix("device:") }.count, 3)
        XCTAssertEqual(legend.last?.id, "quota:remaining")
        XCTAssertFalse(legend.contains { $0.id.hasPrefix("aggregate:") })
        XCTAssertEqual(many.items.first { $0.id == "quota:remaining" }?.value, 1)
        let invalid = QuotaChartData.allocation(remaining: 17, rows: [row("A", 95)])
        XCTAssertEqual(invalid.items.first { $0.id == "quota:used" }?.value, 83)
        XCTAssertTrue(QuotaChartData.allocation(remaining: nil, rows: [row("A", 83)]).items.isEmpty)
        let raw = Data(#"[{"deviceId":"A","periods":{"allTime":{"clients":{"codex":100},"totalTokens":900}}},{"deviceId":"B","periods":{"allTime":{"clients":{"codex":300},"totalTokens":500}}},{"deviceId":"unknown","periods":{"allTime":{"totalTokens":999}}}]"#.utf8)
        let devices = try! JSONDecoder().decode([Device].self, from: raw)
        let tokens = QuotaChartData.tokens(devices: devices)
        XCTAssertEqual(tokens.total, 400)
        XCTAssertEqual(tokens.fraction(tokens.items.first { $0.id == "device:A" }!), 0.25)
        XCTAssertEqual(QuotaChartPage.overview.advanced(by: -1), .tokens)
        XCTAssertEqual(QuotaChartPage.tokens.advanced(by: 1), .overview)
    }
    func testThinRingHitTestingKeepsTheLargerCenterEmpty() {
        let ring = Distribution([.init(id: "a", name: "A", value: 1)])
        let path = DonutGeometry.paths(ring, size: NSSize(width: 110, height: 110), strokeWidth: 6)[0]
        XCTAssertTrue(path.contains(CGPoint(x: 98, y: 55)))
        XCTAssertFalse(path.contains(CGPoint(x: 90, y: 55)))
        XCTAssertFalse(path.contains(CGPoint(x: 55, y: 55)))
    }
    func testCompactActivityShowsFourOrTopThreeAndOther() {
        for count in 0...9 {
            let rows = (0..<count).map { DistributionItem(id: String($0), name: String($0), value: Double($0 + 1)) }
            let chart = Distribution.compactActivity(rows, otherID: "aggregate:other:test")
            XCTAssertEqual(chart.total, rows.reduce(0) { $0 + $1.value })
            XCTAssertEqual(chart.items.count, min(4, count))
            XCTAssertEqual(chart.items.contains { $0.id == "aggregate:other:test" }, count >= 5)
            if count >= 5 { XCTAssertEqual(chart.items.prefix(3).map(\.id), rows.suffix(3).reversed().map(\.id)) }
        }
    }
    func testDisplayAliasesPreserveIdentityValuesOrderAndLegacySettings() throws {
        var style = ChartStyle()
        style.objectNames = ["model:a": "Short", "device:a": "Desk", "quota:remaining": "Free"]
        let raw = Distribution((0..<6).map { .init(id: "model:" + String($0), name: String($0), value: 10) }, limit: 3)
        style.objectNames?[raw.items[0].id] = "Short"
        let named = style.named(raw)
        XCTAssertEqual(named.items.map(\.id), raw.items.map(\.id))
        XCTAssertEqual(named.items.map(\.value), raw.items.map(\.value))
        XCTAssertEqual(named.total, raw.total)
        XCTAssertEqual(named.items[0].name, "Short")
        XCTAssertEqual(style.displayName(id: "model:a", fallback: "Original"), "Short")
        XCTAssertEqual(style.displayName(id: "device:a", fallback: "Original"), "Desk")
        XCTAssertEqual(try JSONDecoder().decode(ChartStyle.self, from: JSONEncoder().encode(style)), style)
        var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(style)) as! [String: Any]
        legacy.removeValue(forKey: "objectNames")
        let restored = try JSONDecoder().decode(ChartStyle.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertEqual(restored.displayName(id: "model:a", fallback: "Original"), "Original")
        style.objectNames?["model:a"] = "  "
        XCTAssertEqual(style.displayName(id: "model:a", fallback: "Original"), "Original")
    }
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
        XCTAssertFalse(old.menuBarTokens); XCTAssertFalse(old.menuBarShortQuota); XCTAssertTrue(old.menuBarWeeklyQuota)
        XCTAssertEqual(old.menuBarStyle, .rings)
        let runtime = RuntimePreferences(old)
        runtime.menuBarTokens = false; runtime.menuBarShortQuota = false; runtime.menuBarWeeklyQuota = true; runtime.menuBarStyle = .rings
        let decoded = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(runtime.snapshot))
        XCTAssertFalse(decoded.menuBarTokens); XCTAssertFalse(decoded.menuBarShortQuota); XCTAssertTrue(decoded.menuBarWeeklyQuota)
        XCTAssertEqual(decoded.menuBarStyle, .rings); XCTAssertEqual(decoded.schemaVersion, 4)
        let unknown = try JSONDecoder().decode(Preferences.self, from: Data(#"{"menuBarStyle":"future"}"#.utf8))
        XCTAssertEqual(unknown.menuBarStyle, .rings)
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
    @MainActor func testAutomaticMenuSourceDoesNotMixAccountsAndExpires() throws {
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
        store.preferences.menuBarShortQuota = true
        XCTAssertEqual(store.menuQuotaMetrics.map(\.percent), [72, 48])
        store.stats = try snapshot([reports[1]])
        XCTAssertEqual(store.menuQuotaMetrics.map(\.percent), [20, 48])
        store.stats = try snapshot([reports[0]])
        XCTAssertEqual(store.menuQuotaMetrics.map(\.percent), [72, 48])
        store.now = now.addingTimeInterval(601)
        XCTAssertTrue(store.menuQuotaMetrics.allSatisfy { $0.percent == nil })
        store.preferences.menuBarTokens = false; store.preferences.menuBarShortQuota = false; store.preferences.menuBarWeeklyQuota = false
        XCTAssertTrue(store.menuQuotaMetrics.isEmpty)
    }
    @MainActor func testMenuOmitsUnreportedShortWindow() throws {
        let store = AppStore(ephemeral: true)
        store.now = now
        store.preferences.menuBarShortQuota = true
        let raw = """
        {"updatedAt":"2026-09-16T00:00:00Z","periods":{},"devices":[],"limits":{"providers":[{"provider":"codex","status":"ok","updatedAt":"2026-09-16T00:00:00Z","windows":[{"kind":"weekly","remainingPercent":48,"windowMinutes":10080}]}]}}
        """
        store.stats = try JSONDecoder().decode(Stats.self, from: Data(raw.utf8))
        XCTAssertEqual(store.menuQuotaMetrics.map(\.label), ["7d"])
        XCTAssertEqual(store.menuQuotaMetrics.map(\.percent), [48])
    }
    @MainActor func testMenuTextInkIsCenteredWithRing() throws {
        let image = MenuBarImageCache().image(tokens: nil, metrics: [.init(label: "7d", percent: 72)], suffix: "")
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(image.tiffRepresentation)))
        let scale = Double(bitmap.pixelsHigh) / image.size.height
        var occupied: [Int] = []
        for y in 0..<bitmap.pixelsHigh {
            if (Int(22 * scale)..<bitmap.pixelsWide).contains(where: { (bitmap.colorAt(x: $0, y: y)?.alphaComponent ?? 0) > 0.3 }) { occupied.append(y) }
        }
        let midpoint = Double(try XCTUnwrap(occupied.first) + XCTUnwrap(occupied.last)) / 2
        XCTAssertEqual(midpoint, Double(bitmap.pixelsHigh - 1) / 2, accuracy: scale)
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
    @MainActor func testHoverUsesOriginalShapeAndVisibleAppearanceAwareStroke() throws {
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 184, height: 184), styleMask: [.titled], backing: .buffered, defer: false)
        let view = DonutNativeView(frame: NSRect(x: 0, y: 0, width: 184, height: 184))
        window.contentView = view
        var style = ChartStyle()
        style.objectColors = ["a": .init(red: 0.4, green: 0.5, blue: 0.6)]
        view.configure(Distribution([.init(id: "a", name: "A", value: 1)]), cost: false, quota: true, style: style)
        defer { window.contentView = nil }
        func tooltipVisible() -> Bool { view.superview?.subviews.contains { $0 is ChartTooltipView } == true }
        func bitmap() throws -> NSBitmapImageRep {
            let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: bitmap)
            return bitmap
        }
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            view.appearance = NSAppearance(named: appearance)
            view.clear()
            let before = try bitmap()
            view.show(at: NSPoint(x: 172, y: 92))
            XCTAssertTrue(tooltipVisible())
            let after = try bitmap()
            let scale = CGFloat(before.pixelsWide) / view.bounds.width
            let x = Int(174 * scale), y = Int(92 * scale)
            let base = try XCTUnwrap(before.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
            let border = try XCTUnwrap(after.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
            if appearance == .aqua { XCTAssertLessThan(border.redComponent, base.redComponent) }
            else { XCTAssertGreaterThan(border.redComponent, base.redComponent) }
            // Hover cannot enlarge the drawing or hit area.
            let outside = Int(177 * scale)
            XCTAssertEqual(before.colorAt(x: outside, y: y), after.colorAt(x: outside, y: y))
            view.show(at: NSPoint(x: 175.8, y: 92))
            XCTAssertFalse(tooltipVisible())
            view.show(at: NSPoint(x: 92, y: 92))
            XCTAssertFalse(tooltipVisible())
        }
    }
}
