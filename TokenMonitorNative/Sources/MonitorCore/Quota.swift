import Foundation

/// Only display data; account keys, names, emails and credentials are not retained.
public struct QuotaSummary: Codable, Sendable {
    public let updatedAt: String?
    public let refreshMs: Double?
    public let providers: [QuotaProvider]
}
public struct QuotaProvider: Codable, Sendable {
    public let provider: String
    public let status: String
    public let updatedAt: String?
    public let stale: Bool?
    public let windows: [QuotaWindow]
    public func isStale(now: Date, threshold: Double) -> Bool {
        stale == true || DateCodec.parse(updatedAt).map { now.timeIntervalSince($0) * 1000 > threshold } ?? false
    }
    public var statusTitle: String {
        switch status {
        case "ok": return "已更新"
        case "rateLimited": return "额度受限"
        case "unauthorized": return "需要重新登录原应用"
        case "notConfigured": return "尚未配置"
        case "disabled": return "未启用额度查询"
        case "sourceRateLimited": return "查询暂时受限"
        case "unavailable", "error": return "暂时无法查询"
        default: return "状态未知"
        }
    }
}
public struct QuotaWindow: Codable, Sendable {
    public let kind: String
    public let label: String?
    public let metric: String?
    public let remaining: Double?
    public let remainingPercent: Double?
    public let resetsAt: String?
    public let boundaryKind: String?
    public let currency: String?
    public let showMeter: Bool?
    public var validPercent: Double? {
        guard let p = remainingPercent, p.isFinite, (0...100).contains(p) else { return nil }
        return p
    }
    public var title: String {
        let period: String
        switch kind { case "session": period = "当前时段"; case "daily": period = "每日"; case "weekly": period = "每周"; case "billing": period = "账期"; default: period = kind }
        if let label, !label.isEmpty, label != period { return "\(label) · \(period)" }
        return period
    }
    public var remainingTitle: String {
        if let p = validPercent { return "剩余 " + p.formatted(.number.precision(.fractionLength(0...1))) + "%" }
        guard let remaining else { return "剩余额度未知" }
        if let currency, !currency.isEmpty { return "剩余 " + remaining.formatted(.currency(code: currency)) }
        let unit: String
        switch metric { case "tokens": unit = " tokens"; case "requests": unit = " 次请求"; case "credits": unit = " credits"; default: unit = "" }
        return "剩余 " + DisplayFormat.tokens(remaining) + unit
    }
}
extension History {
    /// Calendar-aligned weeks ending today; future cells are excluded.
    public func activityPoints(tool: String, now: Date = Date(), calendar: Calendar = .current, weeks: Int = 16) -> [TrendPoint] {
        let today = calendar.startOfDay(for: now)
        let week = calendar.dateInterval(of: .weekOfYear, for: today)!.start
        let start = calendar.date(byAdding: .weekOfYear, value: -(max(1, weeks) - 1), to: week)!
        let rows = Dictionary(daily.compactMap { row -> (String, HistoryRow)? in guard let date = row.date else { return nil }; return (date, row) }, uniquingKeysWith: { _, rhs in rhs })
        let days = calendar.dateComponents([.day], from: start, to: today).day! + 1
        let keyFormatter = DateCodec.keyFormatter(monthly: false)
        return (0..<days).map { index in
            let date = calendar.date(byAdding: .day, value: index, to: start)!
            let row = rows[keyFormatter.string(from: date)]
            return TrendPoint(date: date, tokens: tool.isEmpty ? row?.tokens : row?.perClient?[tool]?.tokens, cost: tool.isEmpty ? row?.cost : row?.perClient?[tool]?.cost)
        }
    }
}

extension History {
    public func allPoints(monthly: Bool, tool: String, now: Date = Date()) -> [TrendPoint] {
        let calendar = Calendar.current
        let component: Calendar.Component = monthly ? .month : .day
        let anchor = calendar.dateInterval(of: component, for: now)!.start
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar; formatter.timeZone = calendar.timeZone
        formatter.dateFormat = monthly ? "yyyy-MM" : "yyyy-MM-dd"
        let rows = monthly ? self.monthly : daily
        let first = rows.compactMap { formatter.date(from: monthly ? ($0.month ?? "") : ($0.date ?? "")) }.filter { $0 <= anchor }.min() ?? anchor
        let count = max(monthly ? 12 : 30, (calendar.dateComponents([component], from: first, to: anchor).value(for: component) ?? 0) + 1)
        return points(monthly: monthly, tool: tool, now: now, count: count)
    }
    public func allActivityPoints(tool: String, now: Date = Date()) -> [TrendPoint] {
        let calendar = Calendar.current
        let first = allPoints(monthly: false, tool: tool, now: now).first!.date
        let firstWeek = calendar.dateInterval(of: .weekOfYear, for: first)!.start
        let thisWeek = calendar.dateInterval(of: .weekOfYear, for: now)!.start
        let weeks = max(16, (calendar.dateComponents([.weekOfYear], from: firstWeek, to: thisWeek).weekOfYear ?? 0) + 1)
        return activityPoints(tool: tool, now: now, weeks: weeks)
    }
}
