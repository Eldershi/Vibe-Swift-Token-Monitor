import XCTest
@testable import MonitorCore

final class QuotaTests: XCTestCase {
    func testScrollableHistoryIncludesEarlierDatesAndMissingDays() throws {
        let history = try History.decode(Data(#"{"daily":[{"date":"2026-01-01","tokens":12},{"date":"2026-09-13","tokens":0}],"monthly":[{"month":"2025-01","tokens":12}]}"#.utf8))
        let now = DateCodec.parse("2026-09-13T04:00:00Z")!
        let points = history.allPoints(monthly: false, tool: "", now: now)
        XCTAssertEqual(DateCodec.key(points.first!.date, monthly: false), "2026-01-01")
        XCTAssertEqual(points.first?.tokens, 12)
        XCTAssertEqual(points.last?.tokens, 0)
        XCTAssertNil(points[1].tokens)
        XCTAssertGreaterThan(points.count, 30)
        XCTAssertGreaterThan(history.allActivityPoints(tool: "", now: now).count, 112)
        XCTAssertEqual(history.allPoints(monthly: true, tool: "", now: now).count, 21)
    }
    func summary() throws -> QuotaSummary {
        try JSONDecoder().decode(QuotaSummary.self, from: Data(#"{"providers":[{"provider":"codex","status":"ok","updatedAt":"2026-09-13T04:00:00Z","accountKey":"do-not-cache","accountEmail":"private@example.invalid","windows":[{"kind":"session","label":"5 小时","remainingPercent":0,"resetsAt":"2026-09-13T07:00:00Z"},{"kind":"weekly","remainingPercent":null},{"kind":"billing","metric":"credits","currency":"USD","remaining":12.5,"showMeter":false}]}]}"#.utf8))
    }
    func testZeroQuotaIsNotMissingAndCurrencyIsNotPercent() throws {
        let windows = try summary().providers[0].windows
        XCTAssertEqual(windows[0].validPercent, 0)
        XCTAssertEqual(windows[0].remainingTitle, L10n.text("剩余 %@", "0%"))
        XCTAssertNil(windows[1].validPercent)
        XCTAssertEqual(windows[1].remainingTitle, L10n.text("剩余额度未知"))
        XCTAssertFalse(windows[2].remainingTitle.contains("%"))
        XCTAssertEqual(windows[2].showMeter, false)
    }
    func testQuotaCacheDropsAccountIdentity() throws {
        let text = String(decoding: try JSONEncoder().encode(summary()), as: UTF8.self)
        XCTAssertFalse(text.contains("do-not-cache")); XCTAssertFalse(text.contains("private@example"))
        XCTAssertFalse(text.contains("accountKey")); XCTAssertTrue(text.contains("remainingPercent"))
    }
    func testQuotaStalenessAndUnknownStatus() throws {
        let provider = try summary().providers[0]
        XCTAssertFalse(provider.isStale(now: DateCodec.parse("2026-09-13T04:05:00Z")!, threshold: 600000))
        XCTAssertTrue(provider.isStale(now: DateCodec.parse("2026-09-13T04:11:00Z")!, threshold: 600000))
        let unknown = try JSONDecoder().decode(QuotaProvider.self, from: Data(#"{"provider":"future","status":"new-status","windows":[]}"#.utf8))
        XCTAssertEqual(unknown.statusTitle, L10n.text("状态未知"))
    }
    func testHeatmapCalendarAlignmentMissingZeroAndFuture() throws {
        let now = DateCodec.parse("2026-09-13T04:00:00Z")!
        let data = Data(#"{"daily":[{"date":"2026-09-13","tokens":0,"perClient":{"codex":{"tokens":0}}},{"date":"2026-09-12","tokens":100,"perClient":{"codex":{"tokens":100}}}],"monthly":[]}"#.utf8)
        let history = try History.decode(data)
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let points = history.activityPoints(tool: "codex", now: now, calendar: calendar)
        XCTAssertLessThanOrEqual(points.count,112); XCTAssertGreaterThanOrEqual(points.count,106)
        XCTAssertEqual(calendar.component(.weekday, from: points.first!.date), calendar.firstWeekday)
        XCTAssertEqual(points.last?.tokens,0)
        XCTAssertEqual(points.filter { $0.tokens != nil }.count,2)
        XCTAssertTrue(points.allSatisfy { $0.date <= now })
        XCTAssertTrue(history.activityPoints(tool: "missing",now: now).allSatisfy { $0.tokens == nil })
    }
}
