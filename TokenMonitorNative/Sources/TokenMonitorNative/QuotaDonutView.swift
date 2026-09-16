import SwiftUI
import MonitorCore

struct QuotaDonutChoice: Identifiable {
    let id: String
    let title: String
    let reportID: String
    let reportTitle: String
    let window: QuotaWindow
    let percent: Double
}

extension AppStore {
    var quotaDonutChoices: [QuotaDonutChoice] {
        quotaProviders.enumerated().flatMap { index, provider in
            let identity = provider.provider + ":" + (provider.accountId ?? provider.sourceDeviceId ?? String(index))
            return provider.windows.compactMap { window -> QuotaDonutChoice? in
                guard let percent = QuotaPresentation.percent(window, provider: provider, now: statusClock, threshold: quotaThreshold) else { return nil }
                return QuotaDonutChoice(id: identity + ":" + window.selectionID(provider: provider.provider), title: window.title, reportID: identity, reportTitle: reportTitle(provider, in: quotaProviders), window: window, percent: percent)
            }
        }
    }
    func reportTitle(_ provider: QuotaProvider, in reports: [QuotaProvider]) -> String {
        if reports.filter({ $0.provider == provider.provider }).count == 1 { return provider.provider == "codex" ? "Codex" : provider.provider }
        if let device = provider.sourceDeviceId { return device }
        return L10n.text("来源 %@", String((reports.firstIndex(where: { $0.accountId == provider.accountId && $0.provider == provider.provider }) ?? 0) + 1))
    }
    func quotaReportTitle(_ index: Int) -> String {
        guard quotaReports.indices.contains(index) else { return L10n.text("无数据") }
        return reportTitle(quotaReports[index], in: quotaReports)
    }
    func selectedDonutChoice(in choices: [QuotaDonutChoice]) -> QuotaDonutChoice? {
        if let selection = detailQuotaSelection, selection.source == preferences.hubAddress,
           let choice = choices.first(where: { $0.id == selection.id }) { return choice }
        if let choice = choices.first(where: { !$0.window.isAdditional && ["session", "daily"].contains($0.window.kind) }) { return choice }
        return choices.first
    }
}

struct QuotaDonutView: View {
    @Bindable var store: AppStore
    var body: some View {
        let choices = store.quotaDonutChoices
        let selected = store.selectedDonutChoice(in: choices)
        VStack(alignment: .leading, spacing: 12) {
            if let selected {
                let reports = choices.reduce(into: [QuotaDonutChoice]()) { result, choice in if !result.contains(where: { $0.reportID == choice.reportID }) { result.append(choice) } }
                if reports.count > 1 {
                    Picker(L10n.text("额度来源"), selection: Binding(get: { selected.reportID }, set: { id in if let choice = reports.first(where: { $0.reportID == id }) { store.detailQuotaSelection = (store.preferences.hubAddress, choice.id) } })) {
                        ForEach(reports) { Text($0.reportTitle).tag($0.reportID) }
                    }.pickerStyle(.menu)
                }
                Picker(L10n.text("额度窗口"), selection: Binding(get: { selected.id }, set: { store.detailQuotaSelection = (store.preferences.hubAddress, $0) })) {
                    ForEach(choices.filter { $0.reportID == selected.reportID }) { Text($0.title).tag($0.id) }
                }.pickerStyle(.menu)
                DistributionChart(distribution: Distribution([
                    .init(id: "quota:remaining", name: L10n.text("剩余额度"), value: selected.percent),
                    .init(id: "quota:used", name: L10n.text("已用额度"), value: 100 - selected.percent)
                ]), quota: true, center: selected.percent.formatted(.number.precision(.fractionLength(0...1))) + "%", style: store.preferences.chartStyle)
            } else {
                DistributionChart(distribution: Distribution([]), quota: true, center: "—", style: store.preferences.chartStyle)
            }
        }
    }
}
