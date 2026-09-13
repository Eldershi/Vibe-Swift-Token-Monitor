import XCTest
import Accessibility
@testable import MonitorCore
@testable import TokenMonitorNative

final class TrendAccessibilityTests: XCTestCase {
    func testCanvasRetainsNativeChartDataIncludingReportedZero() {
        let date = Date(timeIntervalSince1970: 0)
        let points = [TrendPoint(date: date, tokens: nil, cost: nil),
                      TrendPoint(date: date.addingTimeInterval(86400), tokens: 0, cost: nil),
                      TrendPoint(date: date.addingTimeInterval(172800), tokens: 42, cost: nil)]
        let chart = TrendAccessibility(points: points, ceiling: 50, monthly: false).makeChartDescriptor()
        XCTAssertEqual(chart.title, "每日 Token 用量")
        XCTAssertEqual(chart.series.count, 1)
        XCTAssertEqual(chart.series[0].dataPoints.count, 2)
        XCTAssertEqual(chart.yAxis?.range, 0...50)
        XCTAssertEqual(chart.yAxis?.gridlinePositions, [25, 50])
    }
}
