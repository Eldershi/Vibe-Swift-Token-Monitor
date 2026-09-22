import SwiftUI
import MonitorCore

struct QuotaCalculationSettings: View {
    var store: AppStore
    private func date(_ raw: String?) -> String { DateCodec.parse(raw)?.formatted(date: .abbreviated, time: .shortened) ?? "—" }
    private func load(_ body: [String: Any]) async { await store.updateConversion(body) }
    var body: some View {
        Section {
            DisclosureGroup(L10n.text("图表统计口径")) {
                Text(L10n.text("额度概览采用官方读数；设备额度分摊按近期完整日费用估算。设备 Token 总计采用各设备已同步的 Codex 累计日志统计，不按额度换算，也不限定当前重置周期。"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let s = store.conversionSnapshot {
                let displayed = s.displayMode == "historical" ? s.lastSuccessful?.result ?? s.result : s.result
                let rows = displayed.attributionAvailable == true && displayed.mode == "currentWindow" ? displayed.devices : displayed.approximation?.devices ?? displayed.devices
                DisclosureGroup(L10n.text("估算依据")) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(Identity.isNativeBeta2
                             ? L10n.text("按同账号设备近期完整日的已记录模型费用，分摊官方已用额度；并非实际额度消耗明细。")
                             : L10n.text("默认包含全部设备，未知档位按普通模式。事件明细优先，旧设备按近期完整日组合外推。"))
                        Text(L10n.text("根据下次重置时间和窗口时长推算"))
                        LabeledContent(L10n.text("官方读数时间"), value: date(displayed.range?.observedAt))
                        ForEach(rows) { row in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(store.preferences.chartStyle.displayName(id: "device:" + row.id, fallback: row.id)).fontWeight(.medium)
                                Text(row.basis == "dailyRateProjection" ? L10n.text("按近期完整日用量外推") : L10n.text("按事件明细计算"))
                                if let from = row.sampleFrom, let to = row.sampleTo { Text(from + " – " + to) }
                                LabeledContent("Token", value: DisplayFormat.tokens(row.tokens))
                                LabeledContent(Identity.isNativeBeta2 ? L10n.text("估算费用权重") : "credits", value: row.weight.formatted(.number.precision(.fractionLength(0...3))))
                            }
                        }
                        if let prices = s.prices, let url = URL(string: prices.sourceUrl) { Link(L10n.text("官方价格来源"), destination: url) }
                        if !Identity.isNativeBeta2 {
                            LabeledContent(L10n.text("未纳入价格换算的 Token"), value: DisplayFormat.tokens(displayed.approximation?.excludedTokens ?? displayed.unknownTokens))
                        }
                        if !Identity.isNativeBeta2 {
                            if s.pricing?.error != nil { Text(L10n.text("价格更新失败，保留上一有效版本")) }
                            Toggle(L10n.text("每六小时检查价格"), isOn: Binding(get: { s.config?.automaticPrices ?? true }, set: { value in Task { await load(["action":"configure", "automaticPrices":value]) } })).disabled(store.conversionBusy)
                            Button(L10n.text("刷新价格")) { Task { await load(["action":"refreshPrices"]) } }.disabled(store.conversionBusy)
                        }
                    }.font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}
