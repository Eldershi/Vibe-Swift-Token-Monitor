import Foundation

public struct DistributionItem: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let value: Double
    public init(id: String, name: String, value: Double) { self.id = id; self.name = name; self.value = value }
}

public struct Distribution: Equatable, Sendable {
    public let items: [DistributionItem]
    public let total: Double
    public init(_ input: [DistributionItem], limit: Int = 5, otherID: String = "aggregate:other") {
        let valid = input.filter { $0.value.isFinite && $0.value >= 0 }.sorted {
            $0.value == $1.value ? $0.id < $1.id : $0.value > $1.value
        }
        let sum = valid.reduce(0) { $0 + $1.value }
        guard sum.isFinite else { items = []; total = 0; return }
        total = sum
        let count = max(1, limit)
        if valid.count > count {
            items = Array(valid.prefix(count)) + [DistributionItem(id: otherID, name: L10n.text("其他"), value: valid.dropFirst(count).reduce(0) { $0 + $1.value })]
        } else { items = valid }
    }
    private init(items: [DistributionItem], total: Double) { self.items = items; self.total = total }
    public func mapNames(_ name: (DistributionItem) -> String) -> Distribution {
        Distribution(items: items.map { .init(id: $0.id, name: name($0), value: $0.value) }, total: total)
    }
    public static func compactActivity(_ input: [DistributionItem], otherID: String) -> Distribution {
        let valid = input.filter { $0.value.isFinite && $0.value > 0 }
        return Distribution(valid, limit: valid.count <= 4 ? 4 : 3, otherID: otherID)
    }
    public func fraction(_ item: DistributionItem) -> Double { total > 0 ? item.value / total : 0 }
}

public enum MenuBarStyle: String, Codable, CaseIterable, Sendable { case text, rings }

/// Anonymous positions only: never infer or persist an account identity.
public enum QuotaPresentation {
    public static func topology(_ providers: [QuotaProvider]) -> String {
        let parts = providers.map { provider in
            [provider.provider] + provider.windows.map { $0.selectionID(provider: provider.provider) }
        }
        return String(decoding: (try? JSONEncoder().encode(parts)) ?? Data(), as: UTF8.self)
    }
    public static func isCurrent(_ provider: QuotaProvider, now: Date, threshold: Double) -> Bool {
        ["ok", "rateLimited"].contains(provider.status) && !provider.isStale(now: now, threshold: threshold)
    }
    public static func percent(_ window: QuotaWindow, provider: QuotaProvider, now: Date, threshold: Double) -> Double? {
        guard isCurrent(provider, now: now, threshold: threshold), window.showMeter != false,
              DateCodec.parse(window.resetsAt).map({ $0 > now }) ?? true else { return nil }
        return window.validPercent
    }
    public static func regularWindow(_ provider: QuotaProvider, weekly: Bool) -> QuotaWindow? {
        provider.windows.first { !$0.isAdditional && (weekly ? $0.kind == "weekly" : ["session", "daily"].contains($0.kind)) }
    }
    public static func defaultReport(_ providers: [QuotaProvider], now: Date, threshold: Double) -> Int? {
        let current = providers.indices.filter { index in
            isCurrent(providers[index], now: now, threshold: threshold) && providers[index].windows.contains { $0.hasReportedQuota }
        }
        return current.first { providers[$0].provider == "codex" && providers[$0].windows.contains { !$0.isAdditional } } ?? current.first
    }
    public static func shortLabel(_ window: QuotaWindow?, weekly: Bool) -> String {
        guard let window else { return weekly ? L10n.text("每周") : L10n.text("短周期") }
        if let minutes = window.windowMinutes, minutes.isFinite, minutes > 0 {
            if minutes.truncatingRemainder(dividingBy: 1440) == 0 { return "\(Int(min(minutes / 1440, 9999)))d" }
            if minutes.truncatingRemainder(dividingBy: 60) == 0 { return "\(Int(min(minutes / 60, 9999)))h" }
            return "\(Int(min(minutes, 9999)))m"
        }
        switch window.kind { case "weekly": return "7d"; case "daily": return "1d"; default: return L10n.text("短周期") }
    }
}
