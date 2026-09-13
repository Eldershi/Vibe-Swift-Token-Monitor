import XCTest
import Observation
import SwiftUI
@testable import MonitorCore
@testable import TokenMonitorNative

final class TimestampCacheTests: XCTestCase {
    func testCompatibleFormatsAndNegativeCache() {
        let parser = TimestampParser(capacity: 8)
        let integral = parser.parse("2026-09-13T04:00:00Z")
        XCTAssertNotNil(integral)
        XCTAssertEqual(integral, parser.parse("2026-09-13T12:00:00+08:00"))
        XCTAssertEqual(parser.parse("2026-09-13T04:00:00.250Z")?.timeIntervalSince(integral!), 0.25)
        for _ in 0..<100 { XCTAssertNil(parser.parse("invalid")); XCTAssertEqual(parser.parse("2026-09-13T04:00:00Z"), integral) }
        XCTAssertEqual(parser.misses, 4)
    }
    func testBoundedAndConcurrent() {
        let parser = TimestampParser(capacity: 8)
        DispatchQueue.concurrentPerform(iterations: 500) { _ in
            XCTAssertNotNil(parser.parse("2026-09-13T04:00:00Z"))
            XCTAssertNil(parser.parse("invalid"))
        }
        XCTAssertEqual(parser.misses, 2)
        for i in 0..<50 { _ = parser.parse("invalid-\(i)") }
        XCTAssertLessThanOrEqual(parser.cachedCount, 8)
    }
}

@MainActor final class InteractionRegressionTests: XCTestCase {
    func testIndependentPreferenceObservations() {
        let preferences = RuntimePreferences()
        var invalidated = false
        withObservationTracking { _ = preferences.tool; _ = preferences.themeColor; _ = preferences.homeSections } onChange: { invalidated = true }
        preferences.period = .today
        XCTAssertFalse(invalidated)
        preferences.tool = "another-tool"
        XCTAssertTrue(invalidated)
    }
    func testSecondTickDoesNotInvalidateHistoryOrPresentation() throws {
        let store = AppStore(ephemeral: true)
        store.now = DateCodec.parse("2026-09-13T04:00:00Z")!
        store.stats = try Stats.decode(Data(contentsOf: Bundle.module.url(forResource: "stats", withExtension: "json", subdirectory: "Fixtures")!))
        store.online = true; store.preparePresentation()
        let count = store.presentationComputations
        var invalidated = false
        withObservationTracking { _ = store.statusClock; _ = store.historyDay; _ = store.tools } onChange: { invalidated = true }
        store.now = store.now.addingTimeInterval(1)
        store.preparePresentation()
        XCTAssertFalse(invalidated)
        XCTAssertEqual(store.presentationComputations, count)
        store.preferences.period = .allTime
        XCTAssertEqual(store.presentationComputations, count + 1, "Only model ranking depends on the selected period")
    }
    func testExpiryBoundaryInvalidatesPreparedSources() throws {
        let store = AppStore(ephemeral: true)
        let start = DateCodec.parse("2026-09-13T04:00:00Z")!
        store.now = start
        var json = try JSONSerialization.jsonObject(with: Data(contentsOf: Bundle.module.url(forResource: "stats", withExtension: "json", subdirectory: "Fixtures")!)) as! [String: Any]
        json["staleAfterMs"] = 1000
        json["devices"] = [["deviceId": "a", "receivedAt": "2026-09-13T04:00:00Z", "periods": Dictionary(uniqueKeysWithValues: Period.allCases.map { ($0.rawValue, ["totalTokens": 0, "clients": ["codex": 0]] as [String: Any]) })]]
        store.stats = try Stats.decode(JSONSerialization.data(withJSONObject: json))
        store.online = true
        XCTAssertEqual(store.tools, ["codex"])
        store.now = start.addingTimeInterval(0.999)
        XCTAssertEqual(store.tools, ["codex"])
        store.now = start.addingTimeInterval(1.002)
        XCTAssertTrue(store.tools.isEmpty)
    }
    func testLatestLayoutLateDataManualBrowsingAndReset() {
        var position = HistoryScrollPosition()
        XCTAssertEqual(position.layout(content: 0, viewport: 300), 0)
        XCTAssertEqual(position.layout(content: 1000, viewport: 300), 700)
        position.userScrolled(to: 200)
        XCTAssertEqual(position.layout(content: 1200, viewport: 300), 200)
        XCTAssertEqual(position.layout(content: 1200, viewport: 1100), 100)
        position.reset()
        XCTAssertEqual(position.layout(content: 1200, viewport: 400), 800)
    }
    func testPrependingHeatmapPreservesBrowsedDate() {
        var position = HistoryScrollPosition()
        _ = position.layout(content: 1000, viewport: 300)
        position.userScrolled(to: 200)
        XCTAssertEqual(position.layout(content: 1300, viewport: 300, prepends: true), 500)
    }
    func testHeatmapFillsWideViewWithMissingDatesAndPreservesZero() throws {
        let history = try History.decode(Data("{\"daily\":[{\"date\":\"2026-09-13\",\"tokens\":0}],\"monthly\":[]}".utf8))
        let points = history.allActivityPoints(tool: "", now: DateCodec.parse("2026-09-13T04:00:00Z")!)
        let expanded = HistoryGeometry.fillingWeeks(points, minimumWeeks: 190)
        XCTAssertEqual((expanded.count + 6) / 7, 190)
        XCTAssertEqual(expanded.last?.tokens, 0)
        XCTAssertEqual(expanded.last?.date, points.last?.date)
        XCTAssertTrue(expanded.dropLast(points.count).allSatisfy { $0.tokens == nil && $0.cost == nil })
        XCTAssertEqual(HistoryGeometry.fillingWeeks(expanded, minimumWeeks: 16), expanded)
    }
    func testResizeExpansionNeverReprojectsHistory() throws {
        let store = AppStore(ephemeral: true)
        store.now = DateCodec.parse("2026-09-13T04:00:00Z")!
        store.history = try History.decode(Data("{\"daily\":[{\"date\":\"2023-09-13\",\"tokens\":0}],\"monthly\":[]}".utf8))
        let base = store.historyPoints(activity: true)
        let count = store.historyProjectionComputations
        for weeks in 16...190 { _ = store.historyPoints(activity: true, minimumWeeks: weeks) }
        XCTAssertEqual(store.historyProjectionComputations, count)
        XCTAssertEqual(store.historyPoints(activity: true), base)
    }
    func testMonthLabelsUseBoundaries() throws {
        let history = try History.decode(Data("{\"daily\":[{\"date\":\"2026-07-10\",\"tokens\":0}],\"monthly\":[]}".utf8))
        let points = history.allPoints(monthly: false, tool: "", now: DateCodec.parse("2026-09-13T04:00:00Z")!)
        let dates = HistoryGeometry.monthIndices(points).map { DateCodec.key(points[$0].date, monthly: false) }
        XCTAssertEqual(dates, ["2026-07-10", "2026-08-01", "2026-09-01"])
    }
    func testNativeScrollOffsetSurvivesContentUpdates() {
        let view = HistoryNativeScroll(content: AnyView(Color.clear))
        view.frame = NSRect(x: 0, y: 0, width: 300, height: 160)
        view.documentSize = NSSize(width: 1000, height: 160)
        view.layout()
        XCTAssertEqual(view.contentView.bounds.minX, 700, accuracy: 1)
        view.setFrameSize(NSSize(width: 600, height: 160)); view.layout()
        XCTAssertEqual(view.contentView.bounds.minX, 400, accuracy: 1)
        view.setFrameSize(NSSize(width: 300, height: 160)); view.layout()
        XCTAssertEqual(view.contentView.bounds.minX, 700, accuracy: 1)
        view.contentView.scroll(to: NSPoint(x: 100, y: 0))
        view.documentSize.width = 1200; view.layout()
        XCTAssertEqual(view.contentView.bounds.minX, 100, accuracy: 1)
        view.position.reset(); view.layout()
        XCTAssertEqual(view.contentView.bounds.minX, 900, accuracy: 1)
    }
    func testBackgroundPersistenceLatestSnapshotRoundTrip() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("settings.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let writer = PersistenceWriter()
        var value = Preferences()
        value.period = .today
        try await writer.savePreferences(value, to: url)
        value.period = .allTime; value.tool = "codex"
        try await writer.savePreferences(value, to: url, revision: 2)
        try await writer.savePreferences(Preferences(), to: url, revision: 1)
        XCTAssertEqual(try PreferencesFile(url: url).load(), value)
    }
}

@MainActor final class NativeScrollIntegrationTests: XCTestCase {
    func testHorizontalWheelAndRelayoutPreserveManualPosition() {
        let view = HistoryNativeScroll(content: AnyView(Color.clear.frame(width: 1500, height: 160)))
        view.frame = NSRect(x: 0, y: 0, width: 320, height: 160)
        view.documentSize = NSSize(width: 1500, height: 160)
        view.layout()
        XCTAssertEqual(view.contentView.bounds.minX, 1180, accuracy: 1)
        // Deliver a real NSEvent into the shipping scroll handler, not just its policy.
        let cg = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: 0, wheel2: 120, wheel3: 0)!
        view.scrollWheel(with: NSEvent(cgEvent: cg)!)
        let browsed = view.contentView.bounds.minX
        XCTAssertLessThan(browsed, 1180)
        view.layout(); XCTAssertEqual(view.contentView.bounds.minX, browsed, accuracy: 1)
        view.documentSize.width = 1600; view.layout()
        XCTAssertEqual(view.contentView.bounds.minX, browsed, accuracy: 1)
        view.position.reset(); view.layout()
        XCTAssertEqual(view.contentView.bounds.minX, 1280, accuracy: 1)
    }
    func testActivityFillsRealNativeViewportAcrossWidthChanges() async throws {
        let store = AppStore(ephemeral: true)
        store.preferences.tool = ""
        store.now = DateCodec.parse("2026-09-13T04:00:00Z")!
        store.history = try History.decode(Data("{\"daily\":[{\"date\":\"2026-09-13\",\"tokens\":0}],\"monthly\":[]}".utf8))
        let host = NSHostingView(rootView: ActivityView(store: store))
        host.sizingOptions = []
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        defer { window.orderOut(nil) }
        func chart(_ view: NSView) -> HistoryNativeScroll? {
            if let value = view as? HistoryNativeScroll { return value }
            for child in view.subviews { if let value = chart(child) { return value } }
            return nil
        }
        for width in [320.0, 600, 1000, 1600, 600] {
            window.setContentSize(NSSize(width: width, height: 200))
            for _ in 0..<5 { host.layoutSubtreeIfNeeded(); try? await Task.sleep(for: .milliseconds(20)) }
            let view = try XCTUnwrap(chart(host))
            XCTAssertEqual(view.contentView.bounds.width, width, accuracy: 1)
            XCTAssertGreaterThanOrEqual(view.documentSize.width, width)
            XCTAssertLessThan(view.documentSize.width - width, 11)
            XCTAssertEqual(view.host.frame.width, view.documentSize.width, accuracy: 1)
            XCTAssertEqual(view.drawingKey?.size.width, view.documentSize.width)
        }
    }
    func testPageContentIsTopAlignedWhenShortAndWidthTracksViewport() async {
        let scroll = PageNativeScroll(content: AnyView(Text("short")))
        let marker = PositionMarker()
        scroll.setContent(AnyView(VStack(spacing: 0) { MarkerView(marker: marker).frame(height: 30); Text("short") }))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 900), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = scroll
        defer { window.orderOut(nil) }
        for width in [320.0, 600, 1000] {
            window.setContentSize(NSSize(width: width, height: 900))
            for _ in 0..<4 { window.contentView?.layoutSubtreeIfNeeded(); try? await Task.sleep(for: .milliseconds(20)) }
            XCTAssertEqual(scroll.host.frame.width, scroll.contentView.bounds.width, accuracy: 1)
            if let view = marker.view {
                let rect = scroll.host.convert(view.bounds, from: view)
                let top = scroll.host.isFlipped ? rect.minY : scroll.host.bounds.height - rect.maxY
                XCTAssertEqual(top, 0, accuracy: 1, "Short pages must not be centered")
            } else { XCTFail("Marker must be hosted") }
        }
    }
}
private final class PositionMarker { weak var view: NSView? }
private struct MarkerView: NSViewRepresentable {
    let marker: PositionMarker
    func makeNSView(context: Context) -> NSView { let view = NSView(); marker.view = view; return view }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
