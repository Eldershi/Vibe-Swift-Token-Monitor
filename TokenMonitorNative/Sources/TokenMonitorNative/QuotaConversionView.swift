import SwiftUI
import MonitorCore

struct ConversionSnapshot: Decodable {
    struct Choice: Decodable, Identifiable {
        let id: String; let title: String; let kind: String?; let label: String?; let limitId: String?; let additional: Bool?; let windowMinutes: Double?; let accountId: String?; let sourceDeviceId: String?
        var group: String { accountId ?? sourceDeviceId ?? "default" }
        var displayTitle: String { QuotaNaming.window(kind: kind ?? (title.hasPrefix("7d") ? "weekly" : "session"), label: label, minutes: windowMinutes ?? (title.hasPrefix("5h") ? 300 : nil)) }
    }
    struct Row: Decodable, Identifiable { let id: String; let tokens: Double; let weight: Double; let share: Double?; let quota: Double?; let basis: String?; let sampleFrom: String?; let sampleTo: String? }
    struct Range: Decodable { let start: String?; let end: String?; let observedAt: String?; let calculationStart: String?; let remaining: Double?; let used: Double? }
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
    let result: Result
}

struct QuotaConversionView: View {
    var store: AppStore
    private func date(_ raw: String?) -> String { DateCodec.parse(raw)?.formatted(date: .abbreviated, time: .shortened) ?? "—" }
    private func load(_ body: [String: Any]? = nil) async {
        await store.updateConversion(body)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if store.conversionBusy && store.conversionSnapshot == nil { ProgressView().controlSize(.small) }
            if let error = store.conversionError { Text(error).font(.caption).foregroundStyle(.secondary) }
            if let s = store.conversionSnapshot {
                let displayed = s.displayMode == "historical" ? s.lastSuccessful?.result ?? s.result : s.result
                let choice = s.choices.first { $0.id == s.choiceId } ?? s.choices.first
                let groups = s.choices.reduce(into: [ConversionSnapshot.Choice]()) { result, c in if !result.contains(where: { $0.group == c.group }) { result.append(c) } }
                if groups.count > 1 {
                    Picker(L10n.text("额度来源"), selection: Binding(get: { choice?.group ?? "" }, set: { group in if let c = groups.first(where: { $0.group == group }) { Task { await load(["action":"configure", "choiceId":c.id]) } } })) {
                        ForEach(groups) { c in Text(sourceTitle(c)).tag(c.group) }
                    }.pickerStyle(.menu).disabled(store.conversionBusy)
                }
                if let choice {
                    let windows = s.choices.filter { $0.group == choice.group }
                    Picker(L10n.text("额度窗口"), selection: Binding(get: { choice.id }, set: { id in Task { await load(["action":"configure", "choiceId":id]) } })) {
                        ForEach(windows) { Text(windowTitle($0, among: windows)).tag($0.id) }
                    }.pickerStyle(.menu).disabled(store.conversionBusy)
                }
                if s.displayMode == "historical" { Text(L10n.text("历史结果")).font(.caption.weight(.medium)).foregroundStyle(.secondary) }
                if let range = displayed.range, range.start != nil {
                    Text(date(range.start) + " – " + date(range.end)).font(.caption).foregroundStyle(.secondary)
                    LabeledContent(L10n.text("官方已用额度"), value: range.remaining.map { (100 - $0).formatted(.number.precision(.fractionLength(0...1))) + "%" } ?? "—")
                }
                let strict = displayed.attributionAvailable == true && displayed.mode == "currentWindow"
                let rows = strict ? displayed.devices : displayed.approximation?.devices ?? displayed.devices
                let models = strict ? displayed.models : displayed.approximation?.models ?? displayed.models
                Text(L10n.text("设备")).font(.headline)
                ForEach(rows) { usageRow($0) }
                Text(L10n.text("模型")).font(.headline)
                ForEach(models) { usageRow($0) }
                if rows.isEmpty { Text(L10n.text("暂无可换算的匹配数据")).font(.caption).foregroundStyle(.secondary) }
                DisclosureGroup(L10n.text("估算依据")) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(L10n.text("默认包含全部设备，未知档位按普通模式。事件明细优先，旧设备按近期完整日组合外推。"))
                        Text(L10n.text("根据下次重置时间和窗口时长推算"))
                        LabeledContent(L10n.text("官方读数时间"), value: date(displayed.range?.observedAt))
                        ForEach(rows) { row in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(row.id).fontWeight(.medium)
                                Text(row.basis == "dailyRateProjection" ? L10n.text("按近期完整日用量外推") : L10n.text("按事件明细计算"))
                                if let from = row.sampleFrom, let to = row.sampleTo { Text(from + " – " + to) }
                                LabeledContent("Token", value: DisplayFormat.tokens(row.tokens))
                                LabeledContent("credits", value: row.weight.formatted(.number.precision(.fractionLength(0...3))))
                            }
                        }
                        if let prices = s.prices, let url = URL(string: prices.sourceUrl) { Link(L10n.text("官方价格来源"), destination: url) }
                        LabeledContent(L10n.text("未纳入价格换算的 Token"), value: DisplayFormat.tokens(displayed.approximation?.excludedTokens ?? displayed.unknownTokens))
                        if s.pricing?.error != nil { Text(L10n.text("价格更新失败，保留上一有效版本")) }
                        Toggle(L10n.text("每六小时检查价格"), isOn: Binding(get: { s.config?.automaticPrices ?? true }, set: { value in Task { await load(["action":"configure", "automaticPrices":value]) } })).disabled(store.conversionBusy)
                        Button(L10n.text("刷新价格")) { Task { await load(["action":"refreshPrices"]) } }.disabled(store.conversionBusy)
                    }.font(.caption).foregroundStyle(.secondary)
                }
                if s.error != nil { Text(L10n.text("明细同步未完成，保留本地记录")).font(.caption).foregroundStyle(.secondary) }
            }
        }.task(id: store.online) { await store.ensureConversionLoaded() }
    }
    private func sourceTitle(_ choice: ConversionSnapshot.Choice) -> String {
        if let device = choice.sourceDeviceId, !device.isEmpty { return device }
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
    private func usageRow(_ row: ConversionSnapshot.Row) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(row.id).lineLimit(2)
                Spacer(minLength: 8)
                Text(row.quota.map { $0.formatted(.number.precision(.fractionLength(0...1))) + "%" } ?? DisplayFormat.tokens(row.tokens) + " tokens").monospacedDigit()
            }
            if let quota = row.quota { ThinProgress(value: quota / 100).tint(store.preferences.accentColor) }
        }.accessibilityElement(children: .combine).padding(.vertical, 3)
    }
}
