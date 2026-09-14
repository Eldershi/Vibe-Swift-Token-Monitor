import XCTest
@testable import MonitorCore

final class ActivityRecordsTests: XCTestCase {
    private var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(secondsFromGMT: 0)!; return c }
    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date { calendar.date(from: DateComponents(year: y, month: m, day: d))! }
    private func point(_ y: Int, _ m: Int, _ d: Int, _ value: Double?) -> TrendPoint { TrendPoint(date: date(y,m,d), tokens: value, cost: nil) }
    func testCrossYearTotalsAndMissingDays() {
        let years = ActivityRecords.years(points: [point(2023,12,30,nil),point(2023,12,31,10),point(2024,1,1,0),point(2024,1,3,5)], now: date(2024,1,3), calendar: calendar)
        XCTAssertEqual(years.map(\.total), [5,10])
        XCTAssertEqual(years[0].months[0].days.map(\.tokens), [5,nil,0])
        XCTAssertTrue(years[0].isPartial)
        XCTAssertFalse(years[1].isPartial)
        XCTAssertEqual(years[1].months[0].days.count, 1)
    }
    func testLeapDayDescendingMonthsAndEmptyInvalidValues() {
        let years = ActivityRecords.years(points: [point(2024,2,28,0),point(2024,3,1,4)], now: date(2024,3,1), calendar: calendar)
        XCTAssertEqual(years[0].months.map(\.total), [4,0])
        XCTAssertEqual(years[0].months[1].days.first?.date, date(2024,2,29))
        XCTAssertEqual(years[0].months[1].days.count, 2)
        XCTAssertTrue(ActivityRecords.years(points: [point(2024,1,1,nil), point(2024,1,2,.nan), point(2024,1,3,-1),point(2025,1,1,3)], now: date(2024,3,1), calendar: calendar).isEmpty)
    }
    func testExpansionScopeRefreshAndJanuaryIdentity() {
        let years = ActivityRecords.years(points: [point(2024,1,1,0)], now: date(2024,1,3), calendar: calendar)
        let year = ActivityExpansion.Item.year(years[0].id)
        let january = ActivityExpansion.Item.month(years[0].months[0].id)
        let a = ActivityExpansion.Scope(source: "local", tool: "codex")
        let b = ActivityExpansion.Scope(source: "local", tool: "other")
        let c = ActivityExpansion.Scope(source: "hub", tool: "codex")
        var state = ActivityExpansion()
        XCTAssertTrue(state.expanded(year, scope: a, years: years))
        XCTAssertFalse(state.expanded(january, scope: a, years: years))
        state.set(true, id: january, scope: a, years: years)
        state.set(false, id: year, scope: a, years: years)
        XCTAssertFalse(state.expanded(year, scope: a, years: years))
        XCTAssertTrue(state.expanded(january, scope: a, years: years))
        XCTAssertFalse(state.expanded(january, scope: b, years: years))
        XCTAssertTrue(state.expanded(year, scope: c, years: years))
        let refreshed = ActivityRecords.years(points: [point(2024,1,1,10)], now: date(2024,2,1), calendar: calendar)
        XCTAssertFalse(state.expanded(year, scope: a, years: refreshed))
        XCTAssertTrue(state.expanded(january, scope: a, years: refreshed))
        XCTAssertFalse(state.expanded(.month(date(2024,2,1)), scope: a, years: refreshed))
    }
    func testLatestRecordedYearDefaultAndLateArrival() {
        let scope = ActivityExpansion.Scope(source: "local", tool: "")
        var state = ActivityExpansion()
        XCTAssertFalse(state.expanded(.year(date(2025,1,1)), scope: scope, years: []))
        let years = ActivityRecords.years(points: [point(2024,12,31,1)], now: date(2025,1,3), calendar: calendar)
        state.prepare(scope: scope, years: [])
        state.prepare(scope: scope, years: years)
        XCTAssertTrue(state.expanded(.year(date(2024,1,1)), scope: scope, years: years))
        let newer = ActivityRecords.years(points: [point(2024,12,31,1), point(2025,1,3,2)], now: date(2025,1,3), calendar: calendar)
        state.prepare(scope: scope, years: newer)
        XCTAssertFalse(state.expanded(.year(date(2025,1,1)), scope: scope, years: newer))
        XCTAssertFalse(state.expanded(.year(date(2025,1,1)), scope: scope, years: years))
    }
}
