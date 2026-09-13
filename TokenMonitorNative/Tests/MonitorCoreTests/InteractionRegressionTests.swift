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
