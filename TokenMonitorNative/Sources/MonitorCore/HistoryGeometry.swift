import Foundation

public enum HistoryGeometry {
    public static func fillingWeeks(_ points: [TrendPoint], minimumWeeks: Int, calendar: Calendar = .current) -> [TrendPoint] {
        guard let first = points.first else { return points }
        let extra = max(0, minimumWeeks - (points.count + 6) / 7) * 7
        guard extra > 0 else { return points }
        return (1...extra).reversed().compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: first.date).map { TrendPoint(date: $0, tokens: nil, cost: nil) }
        } + points
    }
    public static func monthIndices(_ points: [TrendPoint], calendar: Calendar = .current) -> [Int] {
        points.indices.filter { $0 == 0 || !calendar.isDate(points[$0 - 1].date, equalTo: points[$0].date, toGranularity: .month) }
    }
}
