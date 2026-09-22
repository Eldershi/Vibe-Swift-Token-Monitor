import SwiftUI
import MonitorCore

struct ConversionSnapshot: Decodable {
    struct Choice: Decodable, Identifiable {
        let id: String; let title: String; let kind: String?; let label: String?; let limitId: String?; let additional: Bool?; let windowMinutes: Double?; let accountId: String?; let sourceDeviceId: String?
        var group: String { accountId ?? sourceDeviceId ?? "default" }
        var displayTitle: String { QuotaNaming.window(kind: kind ?? (title.hasPrefix("7d") ? "weekly" : "session"), label: label, minutes: windowMinutes ?? (title.hasPrefix("5h") ? 300 : nil)) }
    }
    struct Row: Decodable, Identifiable { let id: String; let tokens: Double; let weight: Double; let share: Double?; let quota: Double?; let basis: String?; let sampleFrom: String?; let sampleTo: String? }
    struct Range: Decodable { let start: String?; let end: String?; let observedAt: String?; let calculationStart: String?; let remaining: Double?; let used: Double?; let cycleStatus: String?; let confirmedAt: String? }
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
    let result: Result
}

enum QuotaDetail: String {
    case overview = "额度概览", devices = "设备", models = "模型", cycle = "周期记录"
    var title: String { L10n.text(rawValue) }
    var symbol: String { switch self { case .overview: "timer"; case .devices: "server.rack"; case .models: "square.stack.3d.up"; case .cycle: "calendar" } }
}

struct QuotaConversionView: View {
    var store: AppStore
    var detail: QuotaDetail? = nil
    var openDetail: (QuotaDetail) -> Void = { _ in }
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
                let displayed = s.displayMode == "historical" ? s.lastSuccessful?.result ?? s.result : s.result
                if detail == nil {
                    QuotaChartCarousel(devices: store.devices, result: displayed, style: store.preferences.chartStyle, tint: store.preferences.accentColor) { openDetail(.overview) }
                } else if detail == .overview {
                    QuotaView(store: store)
                }
                let choice = s.choices.first { $0.id == s.choiceId } ?? s.choices.first
                let groups = s.choices.reduce(into: [ConversionSnapshot.Choice]()) { result, c in if !result.contains(where: { $0.group == c.group }) { result.append(c) } }
                if detail == nil && groups.count > 1 {
                    Picker(L10n.text("额度来源"), selection: Binding(get: { choice?.group ?? "" }, set: { group in if let c = groups.first(where: { $0.group == group }) { Task { await load(["action":"configure", "choiceId":c.id]) } } })) {
                        ForEach(groups) { c in Text(sourceTitle(c)).tag(c.group) }
                    }.pickerStyle(.menu).disabled(store.conversionBusy)
                }
                if detail == nil, let choice {
                    let windows = s.choices.filter { $0.group == choice.group }
                    if windows.count > 1 {
                        Picker(L10n.text("额度窗口"), selection: Binding(get: { choice.id }, set: { id in Task { await load(["action":"configure", "choiceId":id]) } })) {
                            ForEach(windows) { Text(windowTitle($0, among: windows)).tag($0.id) }
                        }.pickerStyle(.menu).disabled(store.conversionBusy)
                    }
                }
                if s.displayMode == "historical" { Text(L10n.text("历史结果")).font(.caption.weight(.medium)).foregroundStyle(.secondary) }
                let strict = displayed.attributionAvailable == true && displayed.mode == "currentWindow"
                let rows = strict ? displayed.devices : displayed.approximation?.devices ?? displayed.devices
                let models = strict ? displayed.models : displayed.approximation?.models ?? displayed.models
                if detail == nil || detail == .devices { summaryCard(.devices, rows: rows, kind: "device") }
                if detail == nil || detail == .models { summaryCard(.models, rows: models, kind: "model") }
                if detail == nil || detail == .cycle {
                VStack(alignment: .leading, spacing: 10) {
                cardHeading(.cycle)
                if let range = displayed.range, range.start != nil {
                    if range.cycleStatus == "pending" {
                        Text(L10n.text("周期待确认")).font(.caption).foregroundStyle(.secondary)
                    } else {
                        LabeledContent(L10n.text(range.cycleStatus == "confirmed" ? "周期开始" : "预计周期开始"), value: date(range.start))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    LabeledContent(L10n.text("下次重置"), value: date(range.end)).font(.caption).foregroundStyle(.secondary)
                    LabeledContent(L10n.text("官方已用额度"), value: range.remaining.map { (100 - $0).formatted(.number.precision(.fractionLength(0...1))) + "%" } ?? "—")
                }
                if let events = s.cycleEvents, !events.isEmpty {
                    DisclosureGroup(L10n.text("周期记录")) {
                        if s.cycleRecordsAvailable != true { Text(L10n.text("当前无法更新周期记录")).foregroundStyle(.secondary) }
                        ForEach(Array(events.suffix(20).reversed())) { event in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(L10n.text(event.kind == "initialDiscovery" ? "首次重建" : "周期变更")).fontWeight(.medium)
                                LabeledContent(L10n.text("周期开始"), value: preciseDate(event.inferredStartAt))
                                LabeledContent(L10n.text("确认时间"), value: preciseDate(event.confirmedAt))
                            }.padding(.vertical, 4)
                        }
                    }.font(.caption)
                }
                }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .quaternaryLabelColor).opacity(0.35), in: RoundedRectangle(cornerRadius: 14))
                }
                if s.error != nil { Text(L10n.text("明细同步未完成，保留本地记录")).font(.caption).foregroundStyle(.secondary) }
            } else {
                QuotaDonutView(store: store)
            }
        }.task(id: store.online) { await store.ensureConversionLoaded() }
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
    private func summaryCard(_ target: QuotaDetail, rows: [ConversionSnapshot.Row], kind: String) -> some View {
        let quota = !rows.isEmpty && rows.allSatisfy { $0.quota != nil }
        let items: [DistributionItem] = rows.map {
            .init(id: kind + ":" + $0.id, name: $0.id, value: quota ? $0.quota ?? 0 : $0.tokens)
        }
        let distribution = store.preferences.chartStyle.named(detail == nil ? Distribution.compactActivity(items, otherID: "aggregate:other:" + kind) : Distribution(items, limit: items.count))
        return VStack(alignment: .leading, spacing: 12) {
            cardHeading(target)
            VStack(alignment: .leading, spacing: 12) {
                if distribution.items.isEmpty { Text(L10n.text("暂无可换算的匹配数据")).font(.caption).foregroundStyle(.secondary) }
                ForEach(distribution.items) { item in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(item.name).lineLimit(1)
                            Spacer(minLength: 8)
                            Text(quota ? item.value.formatted(.number.precision(.fractionLength(0...1))) + "%" : DisplayFormat.compact(item.value)).monospacedDigit()
                        }.font(.callout)
                        if quota { ThinProgress(value: item.value / 100).tint(store.preferences.accentColor) }
                    }.accessibilityElement(children: .combine)
                }
            }.frame(height: detail == nil ? 152 : nil, alignment: .top)
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .quaternaryLabelColor).opacity(0.35), in: RoundedRectangle(cornerRadius: 14))
    }
    private func cardHeading(_ target: QuotaDetail) -> some View {
        HStack {
            Text(target.title).font(.headline)
            Spacer()
            if detail == nil {
                Button { openDetail(target) } label: {
                    Image(systemName: target.symbol).foregroundStyle(store.preferences.accentColor ?? Color.accentColor)
                }.buttonStyle(.plain).accessibilityLabel(L10n.text("查看%@详情", target.title))
            }
        }
    }

}
