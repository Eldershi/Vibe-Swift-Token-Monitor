import XCTest
import Accessibility
@testable import MonitorCore
@testable import TokenMonitorNative

final class TrendAccessibilityTests: XCTestCase {
    private var calendar: Calendar { var value = Calendar(identifier: .gregorian); value.timeZone = TimeZone(secondsFromGMT: 0)!; return value }
    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }
    private func sequence(start: Date, count: Int, component: Calendar.Component) -> [TrendPoint] {
        (0..<count).map { TrendPoint(date: calendar.date(byAdding: component, value: $0, to: start)!, tokens: Double($0), cost: nil) }
    }
    func testAxisUsesCalendarBoundariesAndKeepsLabelsContained() {
        let hours = sequence(start: date(2026, 9, 15, 18), count: 24, component: .hour)
        let days = sequence(start: date(2026, 8, 18), count: 30, component: .day)
        let months = sequence(start: date(2024, 10, 1), count: 24, component: .month)
        XCTAssertEqual(TrendAxisLayout.indices(points: hours, granularity: .hour, calendar: calendar), [0, 6, 12, 18])
        XCTAssertEqual(TrendAxisLayout.indices(points: days, granularity: .day, calendar: calendar), [14, 28])
        XCTAssertEqual(TrendAxisLayout.indices(points: months, granularity: .month, calendar: calendar), [3, 15])
        for points in [hours, days, months] {
            for index in points.indices {
                let placement = TrendAxisLayout.labelPlacement(index: index, count: points.count, width: 240, labelWidth: 54)
                XCTAssertGreaterThanOrEqual(placement.center, 27)
                XCTAssertLessThanOrEqual(placement.center, 213)
            }
        }
        XCTAssertEqual(TrendAxisLayout.labelPlacement(index: 0, count: 24, width: 240, labelWidth: 54).alignment, .leading)
        XCTAssertEqual(TrendAxisLayout.labelPlacement(index: 23, count: 24, width: 240, labelWidth: 54).alignment, .trailing)
        XCTAssertEqual(TrendAxisFormatting.hour(date(2026, 9, 16, 0), timeZone: calendar.timeZone), "12 AM")
        XCTAssertEqual(TrendAxisFormatting.hour(date(2026, 9, 16, 6), timeZone: calendar.timeZone), "6 AM")
        XCTAssertEqual(TrendAxisFormatting.hour(date(2026, 9, 16, 12), timeZone: calendar.timeZone), "12 PM")
        XCTAssertEqual(TrendAxisFormatting.month(date(2026, 9, 1), timeZone: calendar.timeZone), "Sep")
        XCTAssertEqual(TrendAxisFormatting.year(date(2026, 1, 1), timeZone: calendar.timeZone), "2026")
    }
    func testCanvasRetainsNativeChartDataIncludingReportedZero() {
        let date = Date(timeIntervalSince1970: 0)
        let points = [TrendPoint(date: date, tokens: nil, cost: nil),
                      TrendPoint(date: date.addingTimeInterval(86400), tokens: 0, cost: nil),
                      TrendPoint(date: date.addingTimeInterval(172800), tokens: 42, cost: nil)]
        let chart = TrendAccessibility(points: points, ceiling: 50, granularity: .day).makeChartDescriptor()
        XCTAssertEqual(chart.title, L10n.text("每日 Token 用量"))
        XCTAssertEqual(chart.series.count, 1)
        XCTAssertEqual(chart.series[0].dataPoints.count, 2)
        XCTAssertEqual(chart.yAxis?.range, 0...50)
        XCTAssertEqual(chart.yAxis?.gridlinePositions, [25, 50])
    }
}
