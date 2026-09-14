import Foundation

public struct ActivityMonth: Identifiable, Equatable {
    public let id: Date
    public let days: [TrendPoint]
    public var total: Double { days.compactMap(\.tokens).reduce(0, +) }
    public var isPartial: Bool { days.contains { $0.tokens == nil } }
}
public struct ActivityYear: Identifiable, Equatable {
    public let id: Date
    public let months: [ActivityMonth]
    public var total: Double { months.reduce(0) { $0 + $1.total } }
    public var isPartial: Bool { months.contains( where: \.isPartial) }
    public var hasRecords: Bool { months.contains { $0.days.contains { $0.tokens != nil } } }
}
public enum ActivityRecords {
    public static func years(points: [TrendPoint], now: Date, calendar: Calendar = .current) -> [ActivityYear] {
        let today = calendar.startOfDay(for: now)
        let valid = points.filter { $0.date <= today && ($0.tokens.map { $0.isFinite && $0 >= 0 } ?? false) }
        guard let first = valid.map(\.date).min() else { return [] }
        let rows = Dictionary(points.map { (calendar.startOfDay(for: $0.date), $0) }, uniquingKeysWith: { _, last in last })
        var days: [TrendPoint] = []
        var date = calendar.startOfDay(for: first)
        while date <= today {
            let value = rows[date]?.tokens.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
            days.append(TrendPoint(date: date, tokens: value, cost: nil))
            guard let next = calendar.date(byAdding: .day, value: 1, to: date), next > date else { break }
            date = next
        }
        let years = Dictionary(grouping: days) { calendar.dateInterval(of: .year, for: $0.date)!.start }
        return years.keys.sorted(by: >).map { year in
            let months = Dictionary(grouping: years[year]!) { calendar.dateInterval(of: .month, for: $0.date)!.start }
            return ActivityYear(id: year, months: months.keys.sorted(by: >).map {
                ActivityMonth(id: $0, days: months[$0]!.sorted { $0.date > $1.date })
            })
        }
    }
}

/// Session-only disclosure choices. Empty data must not consume the initial default.
public struct ActivityExpansion {
    public struct Scope: Hashable {
        public let source: String
        public let tool: String
        public init(source: String, tool: String) { self.source = source; self.tool = tool }
    }
    public enum Item: Hashable { case year(Date), month(Date) }
    private var choices: [Scope: Set<Item>] = [:]
    public init() {}
    public mutating func prepare(scope: Scope, years: [ActivityYear]) {
        guard choices[scope] == nil, let year = years.first(where: \.hasRecords) else { return }
        choices[scope] = [.year(year.id)]
    }
    public func expanded(_ id: Item, scope: Scope, years: [ActivityYear]) -> Bool {
        if let saved = choices[scope] { return saved.contains(id) }
        return years.first(where: \.hasRecords).map { Item.year($0.id) } == id
    }
    public mutating func set(_ expanded: Bool, id: Item, scope: Scope, years: [ActivityYear]) {
        var saved = choices[scope] ?? Set(years.first(where: \.hasRecords).map { [Item.year($0.id)] } ?? [])
        if expanded { saved.insert(id) } else { saved.remove(id) }
        choices[scope] = saved
    }
}
