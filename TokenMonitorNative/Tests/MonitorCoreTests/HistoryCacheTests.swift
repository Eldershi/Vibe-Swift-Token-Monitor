import XCTest
@testable import MonitorCore
@testable import TokenMonitorNative

@MainActor final class HistoryCacheTests: XCTestCase {
    func testHistoryCacheTracksSnapshotToolAndCalendarDay() throws {
        let store = AppStore(ephemeral: true)
        let date = DateCodec.parse("2026-09-13T12:00:00Z")!
        store.now = date
        store.preferences.tool = "codex"
        let key = DateCodec.key(date, monthly: false)
        func history(_ tokens: Int) throws -> History {
            try History.decode(Data("{\"daily\":[{\"date\":\"\(key)\",\"tokens\":\(tokens),\"perClient\":{\"codex\":{\"tokens\":3}}}],\"monthly\":[]}".utf8))
        }
        store.history = try history(10)
        let initial = store.historyPoints()
        XCTAssertEqual(initial.last?.tokens, 3)
        store.now = date.addingTimeInterval(1)
        XCTAssertEqual(store.historyPoints(), initial)
        store.preferences.tool = ""
        XCTAssertEqual(store.historyPoints().last?.tokens, 10)
        store.history = try history(20)
        XCTAssertEqual(store.historyPoints().last?.tokens, 20)
        XCTAssertEqual(store.historyPoints(activity: true).last?.tokens, 20)
        XCTAssertEqual(store.historyPoints(monthly: true).count, 12)
        store.now = Calendar.current.date(byAdding: .day, value: 1, to: date)!
        XCTAssertNil(store.historyPoints().last?.tokens)
        XCTAssertEqual(store.historyPoints().dropLast().last?.tokens, 20)
        store.history = nil
        XCTAssertTrue(store.historyPoints().isEmpty)
    }
    func testTrendBucketsFollowTodayThirtyDayAndTwentyFourMonthRules() throws {
        let store = AppStore(ephemeral: true)
        store.now = DateCodec.parse("2028-02-15T12:00:00+08:00")!
        store.preferences.tool = "codex"
        store.history = try History.decode(Data(#"{"daily":[{"date":"2028-02-01","tokens":8,"perClient":{"codex":{"tokens":3}}}],"monthly":[{"month":"2028-02","tokens":80,"perClient":{"codex":{"tokens":30}}}]}"#.utf8))
        store.preferences.period = .month
        let days = store.trendPoints()
        XCTAssertEqual(days.count, 30)
        XCTAssertEqual(days.first?.date, Calendar.current.date(byAdding: .day, value: -29, to: Calendar.current.startOfDay(for: store.now)))
        XCTAssertTrue(days.contains { DateCodec.key($0.date, monthly: false) == "2028-02-01" && $0.tokens == 3 })
        XCTAssertNil(days.last?.tokens)
        store.preferences.period = .allTime
        XCTAssertEqual(store.trendPoints().count, 24)
        XCTAssertEqual(store.trendPoints().last?.tokens, 30)
        store.preferences.period = .today
        let hourStart = Calendar.current.dateInterval(of: .hour, for: store.now)!.start
        let hourly = (0..<24).map { index in
            ConversionSnapshot.HourlyPoint(hour: Calendar.current.component(.hour, from: hourStart.addingTimeInterval(Double(index - 23) * 3600)),
                                           start: hourStart.addingTimeInterval(Double(index - 23) * 3600).ISO8601Format(), tokens: Double(index))
        }
        store.rollingHourlyTrend = ConversionSnapshot.HourlyTrend(version: 2, mode: "rolling24", date: DateCodec.key(store.now, monthly: false), timeZone: TimeZone.current.identifier,
                                                                   rangeStart: hourly.first?.start, rangeEnd: hourStart.addingTimeInterval(3600).ISO8601Format(), points: hourly)
        XCTAssertEqual(store.trendPoints().count, 24)
        XCTAssertEqual(store.trendPoints().last?.tokens, 23)
        store.preferences.tool = "claude"
        XCTAssertTrue(store.trendUnsupported)
        XCTAssertTrue(store.trendPoints().isEmpty)
    }
}
