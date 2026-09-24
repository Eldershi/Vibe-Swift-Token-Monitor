import SwiftUI
import MonitorCore

struct ConversionSnapshot: Decodable {
    struct Choice: Decodable, Identifiable {
        let id: String; let title: String; let kind: String?; let label: String?; let limitId: String?; let additional: Bool?; let windowMinutes: Double?; let accountId: String?; let sourceDeviceId: String?
        var group: String { accountId ?? sourceDeviceId ?? "default" }
        var displayTitle: String { QuotaNaming.window(kind: kind ?? (title.hasPrefix("7d") ? "weekly" : "session"), label: label, minutes: windowMinutes ?? (title.hasPrefix("5h") ? 300 : nil)) }
    }
    struct Row: Decodable, Identifiable { let id: String; let tokens: Double; let weight: Double; let share: Double?; let quota: Double?; let basis: String?; let sampleFrom: String?; let sampleTo: String? }
    struct Range: Decodable { let start: String?; let end: String?; let observedAt: String?; let calculationStart: String?; let remaining: Double?; let used: Double?; let cycleStatus: String?; let confirmedAt: String?; let cycleEventId: String? }
    struct Approximation: Decodable { let attributionAvailable: Bool?; let remainingTokens: Double?; let tokens: Double; let totalWeight: Double; let excludedTokens: Double; let assumedTierTokens: Double; let assumedAccountTokens: Double; let devices: [Row]; let models: [Row]; let missingDevices: [String]; let reasons: [String] }
    struct Result: Decodable { let attributionAvailable: Bool?; let approximation: Approximation?; let range: Range?; let mode: String?; let reasons: [String]; let devices: [Row]; let models: [Row]; let totalWeight: Double; let simulationWeight: Double; let unknownTokens: Double; let remainingTokens: Double? }
    struct Pricing: Decodable { let successAt: String?; let checkedAt: String?; let error: String? }
    struct Prices: Decodable {
        struct Rate: Decodable, Identifiable { let model: String; let tier: String; let input: Double?; let cached: Double?; let output: Double?; var id: String { model + ":" + tier } }
        let id: String; let sourceUrl: String; let rates: [Rate]
    }
    struct Config: Decodable { let automaticPrices: Bool?; let approximateEstimates: Bool? }
    struct Historical: Decodable { let capturedAt: String?; let choiceId: String; let result: Result }
    struct HourlyPoint: Decodable { let hour: Int; let start: String; let tokens: Double? }
    struct HourlyTrend: Decodable {
        let version: Int?; let mode: String?; let date: String; let timeZone: String?
        let rangeStart: String?; let rangeEnd: String?; let points: [HourlyPoint]
        var isRolling24: Bool { version == 2 && mode == "rolling24" && points.count == 24 }
    }
    struct Trend: Decodable { let hourly: HourlyTrend? }
    let deviceIds: [String]?
    let config: Config?
    struct Coverage: Decodable, Identifiable { let deviceId: String; let from: String; let to: String; let complete: Bool; var id: String { deviceId } }
    let coverage: [Coverage]?
    let schemaVersion: Int
    let deviceId: String
    let error: String?
    let choices: [Choice]
    let choiceId: String
    let accountId: String?
    let displayMode: String?
    let lastSuccessful: Historical?
    let trend: Trend?
    let pricing: Pricing?
    let prices: Prices?
    struct CycleEvent: Decodable, Identifiable {
        let id: String; let kind: String; let inferredStartAt: String; let resetsAt: String
        let confirmedAt: String; let derivation: String
    }
    let cycleRecordsAvailable: Bool?
    let cycleEvents: [CycleEvent]?
    struct Cycle: Decodable, Identifiable {
        let id: String; let kind: String; let start: String; let end: String
        let observedAt: String?; let usedPercent: Double?; let result: Result
    }
    let cycleTimeline: [Cycle]?
    let result: Result
}

enum QuotaDetail: String {
    case overview = "额度概览", devices = "设备", models = "模型"
    var title: String { L10n.text(rawValue) }
    var symbol: String { switch self { case .overview: "timer"; case .devices: "server.rack"; case .models: "square.stack.3d.up" } }
}

struct EqualHeightCards: Layout {
    let spacing: CGFloat
    private func width(_ proposal: ProposedViewSize, subviews: Subviews) -> CGFloat {
        proposal.width ?? subviews.reduce(CGFloat(0)) { $0 + $1.sizeThatFits(.unspecified).width }
            + spacing * CGFloat(max(0, subviews.count - 1))
    }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let totalWidth = width(proposal, subviews: subviews)
        let cardWidth = max(0, (totalWidth - spacing * CGFloat(max(0, subviews.count - 1))) / CGFloat(max(1, subviews.count)))
        let height = subviews.map { $0.sizeThatFits(.init(width: cardWidth, height: nil)).height }.max() ?? 0
        return CGSize(width: totalWidth, height: height)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let cardWidth = max(0, (bounds.width - spacing * CGFloat(max(0, subviews.count - 1))) / CGFloat(max(1, subviews.count)))
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + CGFloat(index) * (cardWidth + spacing), y: bounds.minY),
                          proposal: .init(width: cardWidth, height: bounds.height))
        }
    }
}

struct QuotaConversionView: View {
    var store: AppStore
    var detail: QuotaDetail? = nil
    @Binding var selectedCycleID: String?
    var openDetail: (QuotaDetail) -> Void = { _ in }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var deviceSummaryTokens = false
    @State private var modelSummaryTokens = false
    private func date(_ raw: String?) -> String { DateCodec.parse(raw)?.formatted(date: .abbreviated, time: .shortened) ?? "—" }
    private func preciseDate(_ raw: String) -> String {
        guard let value = DateCodec.parse(raw) else { return "—" }
        return value.formatted(date: .abbreviated, time: .standard)
    }
    private func load(_ body: [String: Any]? = nil) async {
        await store.updateConversion(body)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if store.conversionBusy && store.conversionSnapshot == nil { ProgressView().controlSize(.small) }
            if let error = store.conversionError { Text(error).font(.caption).foregroundStyle(.secondary) }
            if let s = store.conversionSnapshot {
                let selectedCycle = s.cycleTimeline?.first { $0.id == selectedCycleID }
                let displayed = selectedCycle?.result ?? (s.displayMode == "historical" ? s.lastSuccessful?.result ?? s.result : s.result)
                let choice = s.choices.first { $0.id == s.choiceId } ?? s.choices.first
                let groups = s.choices.reduce(into: [ConversionSnapshot.Choice]()) { result, c in if !result.contains(where: { $0.group == c.group }) { result.append(c) } }
                if detail == nil && groups.count > 1 {
                    Picker(L10n.text("额度来源"), selection: Binding(get: { choice?.group ?? "" }, set: { group in if let c = groups.first(where: { $0.group == group }) { selectedCycleID = nil; Task { await load(["action":"configure", "choiceId":c.id]) } } })) {
                        ForEach(groups) { c in Text(sourceTitle(c)).tag(c.group) }
                    }.pickerStyle(.menu).disabled(store.conversionBusy)
                }
                if detail == nil, let choice {
                    let windows = s.choices.filter { $0.group == choice.group }
                    if windows.count > 1 {
                        Picker(L10n.text("额度窗口"), selection: Binding(get: { choice.id }, set: { id in selectedCycleID = nil; Task { await load(["action":"configure", "choiceId":id]) } })) {
                            ForEach(windows) { Text(windowTitle($0, among: windows)).tag($0.id) }
                        }.pickerStyle(.menu).disabled(store.conversionBusy)
                    }
                }
                if detail == nil {
                    QuotaCycleHeatmap(store: store, cycles: s.cycleTimeline ?? [],
                                      currentID: s.result.range?.cycleEventId, selectedID: $selectedCycleID)
                    QuotaChartCarousel(result: displayed, style: store.preferences.chartStyle,
                                       tint: store.preferences.accentColor,
                                       historicalCycle: selectedCycle != nil && selectedCycle?.id != s.result.range?.cycleEventId) { openDetail(.overview) }
                } else if detail == .overview {
                    if selectedCycle != nil && selectedCycle?.id != s.result.range?.cycleEventId {
                        QuotaRingView(percent: displayed.range?.remaining, style: store.preferences.chartStyle, cycleMotion: true)
                        Text(L10n.text("最后观测的官方额度，历史分摊为近似估算"))
                            .font(.caption).foregroundStyle(.secondary)
                    } else { QuotaView(store: store) }
                }
                if s.displayMode == "historical" { Text(L10n.text("历史结果")).font(.caption.weight(.medium)).foregroundStyle(.secondary) }
                let strict = displayed.attributionAvailable == true && displayed.mode == "currentWindow"
                let rows = strict ? displayed.devices : displayed.approximation?.devices ?? displayed.devices
                let models = strict ? displayed.models : displayed.approximation?.models ?? displayed.models
                if detail == nil {
                    let summaryRevision = "\(selectedCycleID ?? "current"):\(deviceSummaryTokens):\(modelSummaryTokens):"
                        + rows.map(\.id).joined(separator: "|") + ":" + models.map(\.id).joined(separator: "|")
                    EqualHeightCards(spacing: 8) {
                        summaryCard(.devices, rows: rows, kind: "device", compact: true,
                                    historical: selectedCycle != nil && selectedCycle?.id != s.result.range?.cycleEventId)
                        summaryCard(.models, rows: models, kind: "model", compact: true,
                                    historical: selectedCycle != nil && selectedCycle?.id != s.result.range?.cycleEventId)
                    }
                    .animation(reduceMotion ? nil : DataMotion.summaryAnimation, value: summaryRevision)
                } else if detail == .devices { summaryCard(.devices, rows: rows, kind: "device", historical: selectedCycle != nil && selectedCycle?.id != s.result.range?.cycleEventId) }
                else if detail == .models { summaryCard(.models, rows: models, kind: "model", historical: selectedCycle != nil && selectedCycle?.id != s.result.range?.cycleEventId) }
                if s.error != nil { Text(L10n.text("明细同步未完成，保留本地记录")).font(.caption).foregroundStyle(.secondary) }
            } else {
                QuotaDonutView(store: store)
            }
        }.task(id: store.online) { await store.ensureConversionLoaded() }
            .onChange(of: store.conversionSnapshot?.choiceId) { selectedCycleID = nil }
    }
    private func sourceTitle(_ choice: ConversionSnapshot.Choice) -> String {
        if let device = choice.sourceDeviceId, !device.isEmpty { return store.preferences.chartStyle.displayName(id: "device:" + device, fallback: device) }
        guard let account = choice.accountId, !account.isEmpty else { return "Codex" }
        return L10n.text("Codex 来源 %@", String(account.suffix(6)))
    }
    private func windowTitle(_ choice: ConversionSnapshot.Choice, among choices: [ConversionSnapshot.Choice]) -> String {
        let semantic = QuotaNaming.window(kind: choice.kind ?? (choice.title.hasPrefix("7d") ? "weekly" : "session"),
                                          label: choice.label ?? choice.limitId,
                                          minutes: choice.windowMinutes ?? (choice.title.hasPrefix("5h") ? 300 : nil))
        let duplicates = choices.filter { $0.displayTitle == choice.displayTitle }
        guard duplicates.count > 1, semantic == choice.displayTitle,
              let index = duplicates.firstIndex(where: { $0.id == choice.id }), index > 0 else { return semantic }
        return L10n.text("专项 %@", semantic)
    }
    private func summaryCard(_ target: QuotaDetail, rows: [ConversionSnapshot.Row], kind: String,
                             compact: Bool = false, historical: Bool = false) -> some View {
        let hasQuota = !rows.isEmpty && rows.allSatisfy { $0.quota?.isFinite == true && ($0.quota ?? -1) >= 0 }
        let tokensSelected = compact && (kind == "device" ? deviceSummaryTokens : modelSummaryTokens)
        let quota = hasQuota && !tokensSelected
        let items: [DistributionItem] = (compact && !hasQuota && !tokensSelected ? [] : rows).map {
            .init(id: kind + ":" + $0.id, name: $0.id, value: quota ? $0.quota ?? 0 : $0.tokens)
        }
        let distribution = store.preferences.chartStyle.named(detail == nil ? Distribution.compactActivity(items, otherID: "aggregate:other:" + kind) : Distribution(items, limit: items.count))
        return VStack(alignment: .leading, spacing: compact ? 8 : 12) {
            cardHeading(target, approximate: historical && quota && !compact)
            if compact {
                QuotaSummaryRows(distribution: distribution, quota: !tokensSelected,
                                 hasSourceRows: !rows.isEmpty, tint: store.preferences.accentColor) {
                    if kind == "device" { deviceSummaryTokens.toggle() } else { modelSummaryTokens.toggle() }
                }
            } else {
            VStack(alignment: .leading, spacing: 12) {
                if distribution.items.isEmpty {
                    Text(L10n.text("暂无可换算的匹配数据")).font(.caption).foregroundStyle(.secondary)
                }
                ForEach(distribution.items) { item in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 8) {
                            Text(item.name).lineLimit(1).truncationMode(.middle)
                            Spacer(minLength: 8)
                            Text(quota ? item.value.formatted(.number.precision(.fractionLength(0...1))) + "%" : DisplayFormat.compact(item.value))
                                .monospacedDigit().lineLimit(1)
                                .contentTransition(.numericText(value: item.value))
                                .animation(reduceMotion ? nil : DataMotion.animation, value: item.value)
                        }.font(.callout)
                        if quota {
                            ThinProgress(value: item.value / 100, cycleMotion: true).tint(store.preferences.accentColor)
                        }
                    }
                }
            }
            }
        }.padding(compact ? 10 : 12)
            .frame(maxWidth: .infinity, maxHeight: compact ? .infinity : nil, alignment: .topLeading)
            .background(Color(nsColor: .quaternaryLabelColor).opacity(0.35), in: RoundedRectangle(cornerRadius: 14))
    }
    private func cardHeading(_ target: QuotaDetail, approximate: Bool = false) -> some View {
        HStack {
            Text(target.title).font(.headline)
            if approximate {
                Text("≈").font(.caption).foregroundStyle(.secondary)
                    .help(L10n.text("历史设备与模型按周期内完整日费用估算"))
                    .accessibilityLabel(L10n.text("历史设备与模型按周期内完整日费用估算"))
            }
            Spacer()
            if detail == nil {
                Button { openDetail(target) } label: {
                    Image(systemName: target.symbol).foregroundStyle(store.preferences.accentColor ?? Color.accentColor)
                }.buttonStyle(.plain).accessibilityLabel(L10n.text("查看%@详情", target.title))
            }
        }
    }

}
