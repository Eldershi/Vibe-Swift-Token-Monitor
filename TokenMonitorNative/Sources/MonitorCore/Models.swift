import Foundation

public enum Period: String, CaseIterable, Codable, Sendable {
    case today, month, allTime
    public var title: String { switch self { case .today: L10n.text("今天"); case .month: L10n.text("本月"); case .allTime: L10n.text("总计") } }
}

public enum HubError: Error, LocalizedError, Equatable {
    case invalidURL, unauthorized, unsupportedStream, incompatible(String), http(Int), disconnected, invalidSecret
    public var errorDescription: String? {
        switch self {
        case .invalidURL: L10n.text("请输入有效的 HTTP 或 HTTPS Hub 地址，不含用户名、密码、查询参数或片段。")
        case .unauthorized: L10n.text("共享密钥不正确。请在“数据”设置中检查密钥。")
        case .invalidSecret: L10n.text("共享密钥不能为空，也不能包含换行。")
        case .unsupportedStream: L10n.text("Hub 暂不支持串流，改用定时刷新。")
        case .incompatible(let context): L10n.text("Hub 数据格式不兼容（%@），已保留上次有效数据。", String(describing: context))
        case .http(let code): L10n.text("Hub 返回 HTTP %@。", String(describing: code))
        case .disconnected: L10n.text("Hub 连接已断开，正在重新连接。")
        }
    }
}

public struct Usage: Codable, Sendable {
    public let totalTokens: Double
    public let costUsd: Double?
    public let cacheReadTokens: Double?
    public let cacheWriteTokens: Double?
    public let outputTokens: Double?
    public let unclassifiedTokens: Double?
    public let timedTokens: Double?
    public let timedOutputTokens: Double?
    public let timedDurationMs: Double?
    public let capabilities: [String: Bool]?
    public let clients: [String: Double]?
    public let clientCosts: [String: Double]?
    public let clientCacheReads: [String: Double]?
    public let clientOutputs: [String: Double]?
    public let models: [String: Double]?
    public let modelCosts: [String: Double]?
    public let clientModels: [String: [String: Double]]?
    public let clientModelCosts: [String: [String: Double]]?

    public func tokens(tool: String) -> Double? { tool.isEmpty ? totalTokens : clients?[tool] }
    public func cost(tool: String) -> Double? { tool.isEmpty ? costUsd : clientCosts?[tool] }
    public func cache(tool: String) -> Double? {
        guard capabilities?["tokenComponents"] != false else { return nil }
        return tool.isEmpty ? cacheReadTokens : clientCacheReads?[tool]
    }
    public func output(tool: String) -> Double? {
        guard capabilities?["tokenComponents"] != false else { return nil }
        return tool.isEmpty ? outputTokens : clientOutputs?[tool]
    }
    public func modelRows(tool: String) -> [ModelRow] {
        let tokens = tool.isEmpty ? models : clientModels?[tool]
        let costs = tool.isEmpty ? modelCosts : clientModelCosts?[tool]
        return (tokens ?? [:]).map { ModelRow(name: $0.key, tokens: $0.value, cost: costs?[$0.key]) }
    }
}

public struct ModelRow: Identifiable, Sendable {
    public var id: String { name }
    public let name: String
    public let tokens: Double
    public let cost: Double?
}

public struct Device: Codable, Identifiable, Sendable {
    public var id: String { deviceId }
    public let deviceId: String
    public let hostname: String?
    public let osName: String?
    public let osVersion: String?
    public let agentVersion: String?
    public let receivedAt: String?
    public let updatedAt: String?
    public let stale: Bool?
    public let syncUploadIntervalMs: Double?
    public let trackedClients: [String]?
    public let clientStatus: [String: String]?
    public let clientHealth: ClientHealth?
    public let periods: [String: Usage]
    public let periodWindows: PeriodWindows?
    public var limits: QuotaSummary? = nil
    public var reportDate: Date? { DateCodec.parse(receivedAt) ?? DateCodec.parse(updatedAt) }
    public func collectionNote(tool: String) -> String? {
        let names = tool.isEmpty
            ? Set(clientHealth?.clients.keys.map { $0 } ?? []).union(clientStatus?.keys.map { $0 } ?? []).sorted()
            : [tool]
        let notes = names.compactMap { name -> String? in
            let state = clientHealth?.clients[name]?.overall ?? clientStatus?[name]
            let hasUsage = periods.values.contains { ($0.clients?[name] ?? 0) > 0 }
            // An absent, never-used tool is not a fault of the device as a whole.
            if tool.isEmpty && !hasUsage && ["unavailable", "missing", "unknown"].contains(state ?? "") { return nil }
            let title = name == "codex" ? "Codex" : name == "claude" ? "Claude" : name
            switch state {
            case "unavailable", "missing": return L10n.text("%@：未找到用量日志", title)
            case "attention": return L10n.text("%@：采集需要检查，请打开该应用", title)
            case "waiting": return nil
            case "unknown": return L10n.text("%@：采集状态未知", title)
            default: return nil
            }
        }
        return notes.isEmpty ? nil : notes.joined(separator: "\n")
    }

    public func isStale(at now: Date, threshold: Double) -> Bool {
        guard let date = reportDate else { return stale ?? true }
        guard threshold > 0 else { return stale ?? false }
        let limit = max(threshold, (syncUploadIntervalMs ?? 0) * 2)
        return stale == true || now.timeIntervalSince(date) * 1000 > limit
    }
    public func hasUsableData(for tool: String, at now: Date, threshold: Double) -> Bool {
        guard !isStale(at: now, threshold: threshold) else { return false }
        let unavailable: Set<String> = ["missing", "unavailable", "offline", "disabled", "notConfigured"]
        if let state = clientHealth?.clients[tool]?.overall, unavailable.contains(state) { return false }
        if let state = clientStatus?[tool], unavailable.contains(state) { return false }
        return periods.values.contains { $0.clients?[tool] != nil }
    }
    public func periodExpired(_ period: Period, at now: Date = Date()) -> Bool {
        guard period != .allTime else { return false }
        if let end = DateCodec.parse(periodWindows?[period.rawValue]?.endsAt) { return now >= end }
        guard let date = DateCodec.parse(updatedAt) else { return false }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return !calendar.isDate(date, equalTo: now, toGranularity: period == .today ? .day : .month)
    }
}

public struct PeriodWindow: Codable, Sendable { public let key: String?; public let endsAt: String? }
public struct PeriodWindows: Codable, Sendable {
    public let today: PeriodWindow?
    public let month: PeriodWindow?
    public subscript(_ period: String) -> PeriodWindow? { period == "today" ? today : period == "month" ? month : nil }
}
public struct ClientHealth: Codable, Sendable {
    public let observedAt: String?
    public let clients: [String: Entry]
    public struct Entry: Codable, Sendable { public let overall: String }
}

public struct Stats: Codable, Sendable {
    public let limits: QuotaSummary?
    public let updatedAt: String
    public let periods: [String: Usage]
    public let devices: [Device]
    public let staleAfterMs: Double?
    public let historyRevision: String?
    public let deviceHistoryRevision: String?

    public static func decode(_ data: Data) throws -> Stats {
        do {
            let stats = try JSONDecoder().decode(Stats.self, from: data)
            guard Period.allCases.allSatisfy({ stats.periods[$0.rawValue] != nil }),
                  DateCodec.parse(stats.updatedAt) != nil,
                  stats.periods.values.allSatisfy({ $0.totalTokens.isFinite && $0.totalTokens >= 0 }),
                  Set(stats.devices.map(\.id)).count == stats.devices.count,
                  stats.devices.allSatisfy({ device in !device.id.isEmpty && Period.allCases.allSatisfy({ p in device.periods[p.rawValue] != nil }) })
            else { throw HubError.incompatible(L10n.text("缺失统计周期、时间戳或设备数据")) }
            return stats
        } catch let error as HubError { throw error }
        catch let error as DecodingError { throw HubError.incompatible(L10n.text("统计响应 ") + decodingLocation(error)) }
        catch { throw HubError.incompatible(L10n.text("统计响应")) }
    }
    public var tools: [String] {
        Array(Set(periods.values.flatMap { Array(($0.clients ?? [:]).keys) } + devices.flatMap { $0.trackedClients ?? [] })).sorted()
    }
}
private func decodingLocation(_ error: DecodingError) -> String {
    switch error {
    case .keyNotFound(let key, let context): return (context.codingPath.map(\.stringValue) + [key.stringValue]).joined(separator: ".") + L10n.text(" 缺失")
    case .typeMismatch(_, let context), .valueNotFound(_, let context), .dataCorrupted(let context): return context.codingPath.map(\.stringValue).joined(separator: ".") + L10n.text(" 类型或值不符")
    @unknown default: return L10n.text("未知字段位置")
    }
}

public struct Health: Decodable, Sendable {
    public let ok: Bool
    public let role: String?
    public let runtime: String?
    public let version: Int?
    public let hubBuild: HubBuild?
    public struct HubBuild: Decodable, Sendable {
        public let schemaVersion: Int?
        public let coreRevision: Int?
        public let coreBuildId: String?
    }
}

public struct HistoryValue: Codable, Sendable { public let tokens: Double; public let cost: Double? }
public struct HistoryRow: Codable, Sendable {
    public let date: String?
    public let month: String?
    public let tokens: Double
    public let cost: Double?
    public let perClient: [String: HistoryValue]?
}
public struct History: Codable, Sendable {
    public let daily: [HistoryRow]
    public let monthly: [HistoryRow]
    public static func decode(_ data: Data) throws -> History {
        do { return try JSONDecoder().decode(History.self, from: data) }
        catch { throw HubError.incompatible(L10n.text("历史响应")) }
    }
    public func points(monthly: Bool, tool: String, now: Date = Date(), count requestedCount: Int? = nil) -> [TrendPoint] {
        let rows = monthly ? self.monthly : self.daily
        let calendar = Calendar.current
        let count = max(1, requestedCount ?? (monthly ? 12 : 30))
        let component: Calendar.Component = monthly ? .month : .day
        let start = calendar.dateInterval(of: component, for: now)!.start
        let grouped = Dictionary(rows.map { (($0.date ?? $0.month ?? ""), $0) }, uniquingKeysWith: { _, rhs in rhs })
        let keyFormatter = DateCodec.keyFormatter(monthly: monthly)
        return (0..<count).reversed().map { offset in
            let date = calendar.date(byAdding: component, value: -offset, to: start)!
            let key = keyFormatter.string(from: date)
            let row = grouped[key]
            let tokens = tool.isEmpty ? row?.tokens : row?.perClient?[tool]?.tokens
            let cost = tool.isEmpty ? row?.cost : row?.perClient?[tool]?.cost
            return TrendPoint(date: date, tokens: tokens, cost: cost)
        }
    }
}
public struct TrendPoint: Identifiable, Equatable, Sendable {
    public var id: Date { date }
    public let date: Date
    public let tokens: Double?
    public let cost: Double?
    public init(date: Date, tokens: Double?, cost: Double?) { self.date = date; self.tokens = tokens; self.cost = cost }
}
public enum TrendGranularity: String, Equatable, Sendable {
    case hour, day, month
    public var accessibilityTitle: String {
        switch self {
        case .hour: L10n.text("每小时 Token 用量")
        case .day: L10n.text("每日 Token 用量")
        case .month: L10n.text("每月 Token 用量")
        }
    }
}
public enum DateCodec {
    public static func parse(_ value: String?) -> Date? {
        guard let value else { return nil }
        return TimestampParser.shared.parse(value)
    }
    public static func key(_ date: Date, monthly: Bool) -> String {
        keyFormatter(monthly: monthly).string(from: date)
    }
    static func keyFormatter(monthly: Bool) -> DateFormatter {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = monthly ? "yyyy-MM" : "yyyy-MM-dd"
        return formatter
    }
}
public enum DisplayFormat {
    public static func tokens(_ value: Double?) -> String {
        guard let value else { return "—" }
        return value.formatted(.number.precision(.fractionLength(0)))
    }
    public static func compact(_ value: Double?) -> String {
        guard let value else { return "—" }
        for (threshold, suffix) in [(1e12, "T"), (1e9, "B"), (1e6, "M"), (1e3, "K")] {
            if value >= threshold { return (value / threshold).formatted(.number.precision(.fractionLength(0...1))) + suffix }
        }
        return tokens(value)
    }
    public static func cost(_ value: Double?) -> String {
        guard let value else { return "—" }
        return value.formatted(.currency(code: "USD").precision(.fractionLength(2)))
    }
}
