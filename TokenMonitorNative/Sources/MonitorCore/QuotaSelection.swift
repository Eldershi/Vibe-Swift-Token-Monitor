import Foundation

/// A presentation choice identifies a quota lane, not an account or a reset cycle.
public struct QuotaChoice: Identifiable, Equatable {
    public let id: String
    public let title: String
    public let isDefault: Bool
}

public enum QuotaSelection {
    public static func choices(in providers: [QuotaProvider]) -> [QuotaChoice] {
        var seen = Set<String>()
        return providers.flatMap { provider in
            provider.windows.filter(\.hasReportedQuota).map { window in
                QuotaChoice(id: window.selectionID(provider: provider.provider),
                            title: "\(provider.provider == "codex" ? "Codex" : provider.provider) · \(window.title)",
                            isDefault: provider.provider == "codex" && !window.isAdditional)
            }
        }.filter { seen.insert($0.id).inserted }
    }

    public static func effectiveIDs(selection: Set<String>?, choices: [QuotaChoice]) -> Set<String> {
        let available = Set(choices.map(\.id))
        if let selection {
            let active = selection.intersection(available)
            if !active.isEmpty { return active }
        }
        let defaults = Set(choices.filter(\.isDefault).map(\.id))
        if !defaults.isEmpty { return defaults }
        // Custom selection must retain a visible option if its last lane disappears.
        // Automatic mode never promotes an additional model quota into the home page.
        return selection == nil ? [] : Set(choices.prefix(1).map(\.id))
    }

    public static func filtered(_ providers: [QuotaProvider], ids: Set<String>) -> [QuotaProvider] {
        providers.compactMap { provider in
            let windows = provider.windows.filter { $0.hasReportedQuota && ids.contains($0.selectionID(provider: provider.provider)) }
            guard !windows.isEmpty else { return nil }
            return QuotaProvider(provider: provider.provider, status: provider.status, updatedAt: provider.updatedAt,
                                 stale: provider.stale, windows: windows)
        }
    }
}

extension QuotaWindow {
    public var hasReportedQuota: Bool {
        validPercent != nil || remaining.map { $0.isFinite && $0 >= 0 } == true
    }
    public var isAdditional: Bool {
        if let additional { return additional }
        if let limitId, !limitId.isEmpty { return limitId != "codex" }
        // Older Hubs may omit lane metadata. Named model windows remain additional.
        guard let label, !label.isEmpty else { return false }
        return !["monthly", "weekly", "daily", "5h", "5 hours", "5 小时"].contains(label.lowercased())
    }
    public func selectionID(provider: String) -> String {
        let lane = isAdditional ? (limitId?.isEmpty == false ? limitId! : label ?? "additional") : "main"
        // Duration, values, reset time, and translated titles must not churn selections.
        let parts = [provider, lane, kind, metric ?? "", currency ?? ""]
        return parts.map { "\($0.utf8.count):\($0)" }.joined(separator: "|")
    }
}
