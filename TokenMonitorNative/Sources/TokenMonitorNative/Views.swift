import SwiftUI
import Accessibility
import MonitorCore

extension AppStore {
    var connectionDisplayStatus: String {
        guard online else { return status }
        let local = Identity.isBeta && (BetaBackend.shared.localOnly || BetaBackend.shared.snapshot?.sync?.enabled != true)
        return local ? L10n.text("已连接本机") : L10n.text("已连接Hub")
    }
}
struct ConnectionFooter: View {
    var store: AppStore
    var body: some View {
        VStack(alignment: .trailing, spacing: 5) {
            Label(store.connectionDisplayStatus, systemImage: store.online ? "checkmark.circle" : "exclamationmark.circle")
                .foregroundStyle(store.online ? Color.green : Color.secondary)
            if let error = store.error { Text(error).foregroundStyle(.secondary) }
        }.font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .trailing).multilineTextAlignment(.trailing)
            .accessibilityElement(children: .combine)
    }
}
struct SummaryView: View {
    var store: AppStore
    var compact = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Codex").font(.subheadline).foregroundStyle(.secondary)
            Text(DisplayFormat.tokens(store.selectedTokens))
                .font(.system(size: compact ? 34 : 46, weight: .semibold, design: .rounded))
                .monospacedDigit().lineLimit(1).minimumScaleFactor(0.4)
                .fixedSize(horizontal: true, vertical: false)
                .contentTransition(.numericText(value: store.selectedTokens ?? 0))
                .animation(reduceMotion ? nil : DataMotion.animation, value: store.selectedTokens)
                .padding(.trailing, 6)
                .frame(maxWidth: .infinity, minHeight: compact ? 44 : 58, alignment: .leading)
                .clipped()
                .accessibilityLabel(L10n.text("总用量 %@ tokens", String(describing: DisplayFormat.tokens(store.selectedTokens))))
            Text("tokens").foregroundStyle(.secondary)
            Text(L10n.text("%@ API 等价估算", String(describing: DisplayFormat.cost(store.selectedCost)))).font(.subheadline)
                .help(L10n.text("由 Hub 提供的 API 等价费用，不代表订阅账单。"))
            if store.stats != nil && store.selectedTokens == nil {
                Text(L10n.text("Hub 尚未报告此工具的数据")).font(.caption).foregroundStyle(.secondary)
            } else if store.selectedTokens == 0 {
                Text(L10n.text("此范围已报告 0 用量")).font(.caption).foregroundStyle(.secondary)
            }
        }.textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L10n.text("%@，%@，总用量 %@ tokens，API 等价估算 %@。%@", "Codex", String(describing: store.preferences.period.title), String(describing: DisplayFormat.tokens(store.selectedTokens)), String(describing: DisplayFormat.cost(store.selectedCost)), String(describing: store.selectedTokens == nil ? L10n.text("Hub 尚未报告此工具的数据") : "")))
    }
}
struct SetupPrompt: View {
    var body: some View {
        if Identity.isBeta {
            ContentUnavailableView {
                Label(BetaBackend.shared.enabled ? L10n.text("正在准备本机数据") : L10n.text("后台已停用"), systemImage: "externaldrive")
            } description: {
                Text(BetaBackend.shared.message)
            } actions: { SettingsLink { Text(L10n.text("数据设置…")) } }
            .frame(maxWidth: .infinity)
        } else {
        ContentUnavailableView {
            Label(L10n.text("连接你的 Hub"), systemImage: "network")
        } description: {
            Text(L10n.text("填写 Hub 地址与共享密钥，即可查看已有统计。"))
        } actions: { SettingsLink { Text(L10n.text("数据设置…")) } }
            .frame(maxWidth: .infinity)
        }
    }
}
struct DeviceRow: View {
    let device: Device
    var usageFraction: Double? = nil
    var store: AppStore
    var compact = false
    private var collectionNote: String? { compact ? nil : device.collectionNote(tool: "codex") }
    private var displayedFraction: Double? { compact && !store.preferences.showHomeDeviceUsageBars ? nil : usageFraction }
    private var systemTitle: String? {
        let value = [device.osName, device.osVersion].compactMap { value in
            guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return value
        }.joined(separator: " ")
        return value.isEmpty ? nil : value
    }
    var body: some View {
        let stale = device.isStale(at: store.statusClock, threshold: store.stats?.staleAfterMs ?? 600_000)
        let expired = device.periodExpired(store.preferences.period, at: store.statusClock)
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                HStack(alignment: .center, spacing: 6) {
                    DeviceSystemIcon(osName: device.osName)
                    Text(store.preferences.chartStyle.displayName(id: "device:" + device.id, fallback: device.id)).fontWeight(.medium).lineLimit(1).truncationMode(.middle)
                }
                Spacer()
                Text(expired ? L10n.text("上一周期数据") : DisplayFormat.tokens(device.periods[store.preferences.period.rawValue]?.tokens(tool: "codex")))
                    .monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
            }
            if let fraction = displayedFraction {
                ThinProgress(value: fraction)
                    .tint(store.preferences.accentColor)
                    .accessibilityLabel(L10n.text("相对最高用量设备"))
                    .accessibilityValue(fraction.formatted(.percent.precision(.fractionLength(0))))
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let systemTitle { Text(systemTitle).lineLimit(1).truncationMode(.tail) }
                Spacer(minLength: 8)
                Label(stale ? L10n.text("上报数据已过期") : L10n.text("已同步"), systemImage: stale ? "clock.badge.exclamationmark" : "checkmark.circle")
                    .font(.caption).foregroundStyle(stale ? Color.orange : Color.green)
                    .fixedSize()
            }.font(.caption).foregroundStyle(.secondary)
            if let note = collectionNote {
                Text(note).font(.caption).foregroundStyle(.secondary)
            }
        }.textSelection(.enabled).accessibilityElement(children: .combine)

    }
}
enum InterfaceSymbols {
    // Official gear exported from SF Symbols 7.2; avoid OS-specific glyph substitution.
    static var resourceBundle: Bundle {
        if let url = Bundle.main.resourceURL?.appendingPathComponent("TokenMonitorNative_TokenMonitorNative.bundle"),
           let bundle = Bundle(url: url) { return bundle }
        return .module
    }
    static var gear: some View {
        Image("ReferenceGear", bundle: resourceBundle)
            .symbolRenderingMode(.monochrome)
            .font(.system(size: 20, weight: .bold))
    }
}
enum Page: String, CaseIterable, Identifiable {
    case overview = "总览", devices = "设备", models = "模型", quota = "额度", activity = "活动"
    static let navigationPages: [Page] = [.overview, .quota, .activity]
    static func restored(_ value: String) -> Page { ["趋势", "设备", "模型"].contains(value) ? .activity : value == "额度换算" ? .quota : (Page(rawValue: value) ?? .overview) }
    var title: String { L10n.text(rawValue) }
    var id: String { rawValue }
    var symbol: String { switch self { case .overview: "chart.bar.xaxis"; case .devices: "server.rack"; case .models: "square.stack.3d.up"; case .quota: "timer"; case .activity: "waveform.path.ecg.text.clipboard" } }
}
struct CompactView: View {
    @Bindable var store: AppStore
    @AppStorage("compactPage") private var persistedPage = Page.overview.rawValue
    @State private var activityDetail: ActivityDetail?
    @State private var quotaDetail: QuotaDetail?
    @State private var diagnosticPage = Page.overview.rawValue
    private var isPeriodDiagnostic: Bool { ProcessInfo.processInfo.arguments.contains("--verify-period-animation") || ProcessInfo.processInfo.arguments.contains("--preview-fixture") }
    private var selectedPage: String {
        get { isPeriodDiagnostic ? diagnosticPage : persistedPage }
        nonmutating set { if isPeriodDiagnostic { diagnosticPage = newValue } else { persistedPage = newValue } }
    }
    private var pageBinding: Binding<String> { Binding(get: { selectedPage }, set: { selectedPage = $0 }) }
    var body: some View {
        ZStack(alignment: .bottom) {
            GeometryReader { _ in
            PageScrollView(tint: store.preferences.accentColor) {
                VStack(alignment: .leading, spacing: 22) {
                    if store.stats == nil { SetupPrompt() }
                    else {
                        if selectedPage != Page.overview.rawValue {
                            HStack(spacing: 8) {
                                Button { if quotaDetail != nil { quotaDetail = nil } else if activityDetail != nil { activityDetail = nil } else { selectedPage = Page.overview.rawValue } } label: {
                                    Image(systemName: "chevron.left").font(.body.weight(.medium))
                                        .frame(width: 20, height: 28)
                                }.buttonStyle(.plain).help(L10n.text(quotaDetail != nil ? "返回额度" : activityDetail == nil ? "返回总览" : "返回活动")).accessibilityLabel(L10n.text(quotaDetail != nil ? "返回额度" : activityDetail == nil ? "返回总览" : "返回活动"))
                                Text(quotaDetail?.title ?? activityDetail?.title ?? Page.restored(selectedPage).title).font(.headline)
                                Spacer(minLength: 8)
                                if activityDetail == .models { ModelSortPicker(store: store) }
                            }
                        }
                        if let activityDetail {
                            ActivitySecondaryView(store: store, detail: activityDetail)
                        } else {
                            switch Page.restored(selectedPage) {
                            case .overview: OverviewView(store: store, selectedPage: pageBinding)
                            case .devices:
                                DistributionChart(distribution: store.deviceDistribution, style: store.preferences.chartStyle)
                                if store.devices.isEmpty { Text(L10n.text("尚无设备数据")).foregroundStyle(.secondary) }
                                let fractions = store.deviceUsageFractions
                                ForEach(store.devices) { DeviceRow(device: $0, usageFraction: fractions[$0.id], store: store) }
                            case .models: ModelsView(store: store)
                            case .quota: QuotaConversionView(store: store, detail: quotaDetail) { quotaDetail = $0 }
                            case .activity: CompactActivityDetailView(store: store) { activityDetail = $0 }
                            }
                        }
                    }
                    ConnectionFooter(store: store)
                }.padding(20).padding(.bottom, 64)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
                .id(selectedPage + (activityDetail?.rawValue ?? "") + (quotaDetail?.rawValue ?? ""))
                .ignoresSafeArea(.container, edges: .top)
            }
            GlassEffectContainer(spacing: 10) {
                HStack(spacing: 10) {
                    HStack(spacing: 0) {
                        FloatingMenuButton(items: Page.navigationPages.map { page in
                            FloatingMenuItem(title: page.title, symbol: page.symbol) { activityDetail = nil; quotaDetail = nil; selectedPage = page.rawValue }
                        }) {
                            Image(systemName: Page.restored(selectedPage).symbol)
                                .font(.system(size: 19, weight: .medium)).frame(width: 44, height: 44)
                        }.help(Page.restored(selectedPage).title).accessibilityLabel(L10n.text("切换页面，当前%@", String(describing: Page.restored(selectedPage).title)))
                        Divider().frame(height: 20).accessibilityHidden(true)
                        Button { store.refresh() } label: {
                            Image(systemName: "arrow.clockwise").font(.system(size: 19, weight: .medium))
                                .frame(width: 44, height: 44)
                        }.buttonStyle(.plain).background(ChartInteractionShield())
                            .help(L10n.text("刷新")).accessibilityLabel(L10n.text("刷新"))
                    }.glassEffect(.regular.interactive(), in: .capsule)
                    Spacer(minLength: 0)
                    SettingsLink { InterfaceSymbols.gear.frame(width: 44, height: 44) }
                        .buttonStyle(.plain).background(ChartInteractionShield()).glassEffect(.regular.interactive(), in: .circle)
                        .help(L10n.text("设置")).accessibilityLabel(L10n.text("设置"))
                }
            }.padding(12)
        }.background(Color(nsColor: .windowBackgroundColor))
            .tint(store.preferences.accentColor).accentColor(store.preferences.accentColor)
            .frame(width: CompactPanel.contentWidth)
            .onChange(of: selectedPage) { activityDetail = nil; quotaDetail = nil; PanelController.shared.updatePage(Page.restored(selectedPage)) }
            .task { selectedPage = Page.restored(selectedPage).rawValue; PanelController.shared.updatePage(Page.restored(selectedPage)); store.loadHistory() }
    }
}
struct OverviewView: View {
    var store: AppStore
    @Binding var selectedPage: String
    private var sections: [HomeSection] {
        store.preferences.visibleHomeSections.filter {
            switch $0 {
            case .quota: !store.homeQuotaProviders.isEmpty
            case .models: !store.modelRows.isEmpty
            case .devices: !store.devices.isEmpty
            default: true
            }
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !store.hasCodexData && store.homeQuotaProviders.isEmpty {
                ContentUnavailableView(L10n.text("暂无可用数据来源"), systemImage: "tray")
                    .frame(maxWidth: .infinity)
            } else if sections.isEmpty {
                ContentUnavailableView {
                    Label(L10n.text("首页暂无栏目"), systemImage: "rectangle.grid.1x2")
                } actions: { SettingsLink { Text(L10n.text("布局设置…")) } }
                    .frame(maxWidth: .infinity)
            } else {
                ForEach(sections, id: \.self) { section in
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            if section == .usage {
                                Text(section.title).font(.headline)
                                Spacer()
                                Image(systemName: "binoculars.fill").font(.body).foregroundStyle(.secondary).accessibilityHidden(true)
                            } else {
                                Button { selectedPage = section.page.rawValue } label: {
                                    Text(section.title).font(.headline)
                                }.buttonStyle(.plain).accessibilityLabel(L10n.text("查看%@详情", section.title))
                                Spacer()
                                Button { selectedPage = section.page.rawValue } label: {
                                    Image(systemName: section.symbol).font(.body).foregroundStyle(store.preferences.accentColor ?? Color.accentColor)
                                }.buttonStyle(.plain).accessibilityLabel(L10n.text("查看%@详情", section.title))
                            }
                        }
                        sectionBody(section)
                    }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(nsColor: .quaternaryLabelColor).opacity(0.35), in: RoundedRectangle(cornerRadius: 14))
                }
            }
        }
    }
    @ViewBuilder private func sectionBody(_ section: HomeSection) -> some View {
        switch section {
        case .usage: SummaryView(store: store, compact: true)
        case .quota: QuotaView(store: store, showHeading: false, home: true)
        case .devices:
            let fractions = store.deviceUsageFractions
            ForEach(store.devices) { DeviceRow(device: $0, usageFraction: fractions[$0.id], store: store, compact: true) }
        case .models: ForEach(store.modelRows.prefix(3)) { ModelUsageRow(row: $0, style: store.preferences.chartStyle) }
        case .activity: ActivityView(store: store, showHeading: false, showBorder: false)
        case .trends:
            HistoryNotice(store: store)
            UsageChart(points: store.trendPoints(), granularity: store.trendGranularity, tint: store.preferences.accentColor,
                              animationMemory: store.overviewTrendAnimation)
        }
    }
}
struct SectionSeparator: View {
    var body: some View { Divider().padding(.horizontal, 12).accessibilityHidden(true) }
}
struct QuotaView: View {
    var store: AppStore
    var showHeading = true
    var showBorder = true
    var home = false
    private var providers: [QuotaProvider] { home ? store.homeQuotaProviders : store.quotaProviders }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showHeading { HStack { Text(L10n.text("额度")).font(.headline); Spacer(); Text(L10n.text("当前状态")).font(.caption).foregroundStyle(.secondary) } }
            ForEach(Array(providers.enumerated()), id: \.offset) { index, provider in
                let stale = provider.isStale(now: store.statusClock, threshold: max(store.stats?.staleAfterMs ?? 600_000, (store.stats?.limits?.refreshMs ?? 300_000) * 2))
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(provider.provider == "codex" ? "Codex" : provider.provider).fontWeight(.medium)
                        if providers.filter({ $0.provider == provider.provider }).count > 1 { Text(store.reportTitle(provider, in: providers)).foregroundStyle(.secondary) }
                        Spacer()
                        if stale || provider.status != "ok" { Text(stale ? L10n.text("数据已过期") : provider.statusTitle).foregroundStyle(.secondary) }
                    }.font(.caption)
                    ForEach(Array(provider.windows.filter(\.hasReportedQuota).enumerated()), id: \.offset) { _, window in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(window.title).lineLimit(2)
                                Spacer(minLength: 8)
                                Text(window.remainingTitle).monospacedDigit().fixedSize(horizontal: false, vertical: true)
                            }.font(.subheadline)
                            if window.showMeter != false, let percent = window.validPercent {
                                ThinProgress(value: percent / 100).accessibilityLabel(L10n.text("%@，%@", window.title, window.remainingTitle))
                            }
                            if let date = DateCodec.parse(window.resetsAt) {
                                Text(date <= store.statusClock ? L10n.text("周期已结束 等待更新") : L10n.text("%@：%@", window.boundaryKind == "expiry" ? L10n.text("到期") : L10n.text("重置"), date.formatted(date: .abbreviated, time: .shortened)))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    if provider.windows.isEmpty { Text(L10n.text("没有可显示的额度窗口")).font(.caption).foregroundStyle(.secondary) }
                }
            }
        }
    }
}
struct ModelUsageRow: View {
    let row: ModelRow
    var style = ChartStyle()
    private var name: String { style.displayName(id: "model:" + row.name, fallback: row.name) }
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(name).fontWeight(.medium).lineLimit(1).help(name)
            HStack { Text("\(DisplayFormat.tokens(row.tokens)) tokens"); Spacer(); Text(DisplayFormat.cost(row.cost)) }
                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
        }.textSelection(.enabled).accessibilityElement(children: .ignore)
            .accessibilityLabel(L10n.text("%@，%@ tokens，API 等价估算 %@", name, String(describing: DisplayFormat.tokens(row.tokens)), String(describing: DisplayFormat.cost(row.cost))))
    }
}
struct ModelSortPicker: View {
    @Bindable var store: AppStore
    var body: some View {
        Picker(L10n.text("排序"), selection: $store.preferences.modelSortByCost) {
            Text(L10n.text("Token 用量")).tag(false); Text(L10n.text("估算费用")).tag(true)
        }.pickerStyle(.menu).labelsHidden().fixedSize().tint(.primary).accentColor(.primary)
            .onChange(of: store.preferences.modelSortByCost) { store.savePreferences() }
    }
}
struct ModelsView: View {
    @Bindable var store: AppStore
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            DistributionChart(distribution: store.modelDistribution, cost: store.preferences.modelSortByCost, style: store.preferences.chartStyle)
            if store.modelRows.isEmpty { Text(L10n.text("尚无模型明细")).foregroundStyle(.secondary) }
            ForEach(store.modelRows) { ModelUsageRow(row: $0, style: store.preferences.chartStyle) }
        }
    }
}
struct HistoryNotice: View {
    var store: AppStore
    var body: some View {
        if store.historyBusy { ProgressView(L10n.text("读取历史…")).controlSize(.small) }
        if let error = store.historyError {
            Text(error).font(.caption).foregroundStyle(.secondary)
            Button(L10n.text("重试历史请求")) { store.loadHistory() }
        }
    }
}
struct HistoryBorder: ViewModifier {
    var enabled = true
    func body(content: Content) -> some View {
        content.overlay(RoundedRectangle(cornerRadius: 8)
            .stroke(Color(nsColor: .separatorColor).opacity(enabled ? 0.5 : 0), lineWidth: 0.5).allowsHitTesting(false))
    }
}
struct ActivityView: View {
    var store: AppStore
    var showHeading = true
    var showBorder = true
    @State private var visibleWeeks = 16
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiate
    var body: some View {
        let points = store.historyPoints(activity: true, minimumWeeks: visibleWeeks)
        let maximum = points.compactMap(\.tokens).max() ?? 0
        let columns = (points.count + 6) / 7
        VStack(alignment: .leading, spacing: 10) {
            if showHeading { Text(L10n.text("活动")).font(.headline) }
            if points.isEmpty { Text(L10n.text("尚无活动数据")).font(.caption).foregroundStyle(.secondary) }
            else {
                HistoryScrollView(width: CGFloat(columns * 10 + 29), height: 104,
                                  resetKey: store.historyPresentationID.uuidString, prepends: true, points: points, tint: store.preferences.accentColor, heatmapHover: true, viewportChanged: { width in
                                      let weeks = max(16, Int(ceil((width - 29) / 10)))
                                      if visibleWeeks != weeks { visibleWeeks = weeks }
                                  }) {
                    Canvas { context, _ in
                        for (index, point) in points.enumerated() {
                            let rect = HeatmapHitTesting.rect(at: index)
                            context.fill(Path(roundedRect: rect, cornerRadius: 1.5), with: .color(color(point.tokens, maximum: maximum)))
                        }
                        for week in 0..<columns {
                            let date = points[week * 7].date
                            let firstLabelFits = week != 0 || columns < 4 || Calendar.current.isDate(date, equalTo: points[21].date, toGranularity: .month)
                            if firstLabelFits && (week == 0 || !Calendar.current.isDate(date, equalTo: points[(week - 1) * 7].date, toGranularity: .month)) {
                                let label = Text(date.formatted(.dateTime.month(.abbreviated))).font(.caption2).foregroundColor(.secondary)
                                context.draw(label, at: CGPoint(x: 16 + week * 10, y: 88), anchor: week == columns - 1 ? .trailing : .center)
                            }
                        }
                    }.frame(width: CGFloat(columns * 10 + 29), height: 104)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(L10n.text("活动热力图，缺失日期无数据"))
                        .accessibilityChartDescriptor(TrendAccessibility(points: points, ceiling: max(1, maximum), granularity: .day))
                }.frame(height: 104)
                    .modifier(HistoryBorder(enabled: showBorder))
            }
        }
    }
    private func color(_ value: Double?, maximum: Double) -> Color {
        guard let value, value > 0, maximum > 0 else { return Color(nsColor: .systemGray).opacity(0.18) }
        return (differentiate ? Color.primary : Color.accentColor).opacity(0.25 + 0.75 * sqrt(value / maximum))
    }

}
struct UsageChart: View {
    let points: [TrendPoint]
    let granularity: TrendGranularity
    var tint: Color? = nil
    var animationMemory = BarAnimationMemory()
    var body: some View {
        if points.contains(where: { $0.tokens != nil }) {
            FixedBarChart(points: points, granularity: granularity, tint: tint, animationMemory: animationMemory)
                .padding(10).frame(height: 180).modifier(HistoryBorder())
        } else { Text(L10n.text("此范围尚无历史数据")).font(.caption).foregroundStyle(.secondary) }
    }
}
struct BarAnimationVector: VectorArithmetic {
    var values: [Double]
    static var zero: Self { .init(values: []) }
    static func + (lhs: Self, rhs: Self) -> Self { combine(lhs, rhs, +) }
    static func - (lhs: Self, rhs: Self) -> Self { combine(lhs, rhs, -) }
    static func += (lhs: inout Self, rhs: Self) { lhs = lhs + rhs }
    static func -= (lhs: inout Self, rhs: Self) { lhs = lhs - rhs }
    mutating func scale(by rhs: Double) { values = values.map { $0 * rhs } }
    var magnitudeSquared: Double { values.reduce(0) { $0 + $1 * $1 } }
    private static func combine(_ lhs: Self, _ rhs: Self, _ operation: (Double, Double) -> Double) -> Self {
        let count = max(lhs.values.count, rhs.values.count)
        return Self(values: (0..<count).map { operation($0 < lhs.values.count ? lhs.values[$0] : 0, $0 < rhs.values.count ? rhs.values[$0] : 0) })
    }
}
struct BarAnimationTarget: Equatable {
    var vector: BarAnimationVector
    var count: Double
}
@MainActor @Observable final class BarAnimationMemory {
    var displayed: BarAnimationTarget?
}
private struct AnimatedBarCanvas: View, Animatable {
    var vector: BarAnimationVector
    var count: Double
    let tint: Color
    var animatableData: AnimatablePair<BarAnimationVector, Double> {
        get { AnimatablePair(vector, count) }
        set { vector = newValue.first; count = newValue.second }
    }
    var body: some View {
        Canvas { context, size in
            var grid = Path()
            for y in [CGFloat(0.5), size.height / 2] {
                grid.move(to: CGPoint(x: 0, y: y)); grid.addLine(to: CGPoint(x: size.width, y: y))
            }
            context.stroke(grid, with: .color(Color(nsColor: .separatorColor).opacity(0.5)), lineWidth: 0.5)
            let slots = max(1, count), slot = size.width / CGFloat(slots), width = min(5, max(2, slot * 0.66))
            for index in 0..<31 {
                let fraction = vector.values.indices.contains(index) ? max(0, min(1, vector.values[index])) : 0
                guard fraction > 0 else { continue }
                let height = CGFloat(fraction) * size.height
                let rect = CGRect(x: (CGFloat(index) + 0.5) * slot - width / 2, y: size.height - height, width: width, height: height)
                context.fill(Path(roundedRect: rect, cornerRadius: min(width, height) / 2), with: .color(tint))
            }
        }
    }
}
struct AnimatedBarPlot: View {
    let target: BarAnimationTarget
    let tint: Color
    @Bindable var memory: BarAnimationMemory
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    init(target: BarAnimationTarget, tint: Color, memory: BarAnimationMemory) {
        self.target = target
        self.tint = tint
        self.memory = memory
    }
    var body: some View {
        let displayed = memory.displayed ?? target
        AnimatedBarCanvas(vector: displayed.vector, count: displayed.count, tint: tint)
            .onAppear { transition(to: target) }
            .onChange(of: target) { _, next in transition(to: next) }
            .onChange(of: reduceMotion) { _, reduced in
                if reduced { memory.displayed = target }
            }
    }
    private func transition(to next: BarAnimationTarget) {
        guard memory.displayed != next else { return }
        guard memory.displayed != nil, !reduceMotion else { memory.displayed = next; return }
        withAnimation(DataMotion.animation) { memory.displayed = next }
    }
}
enum TrendAxisLayout {
    enum EdgeAlignment: Equatable { case leading, center, trailing }
    struct Placement: Equatable { let center: CGFloat; let alignment: EdgeAlignment }
    static func indices(points: [TrendPoint], granularity: TrendGranularity, calendar: Calendar = .current) -> [Int] {
        points.indices.filter { index in
            let components = calendar.dateComponents([.month, .day, .hour], from: points[index].date)
            switch granularity {
            case .hour: return [0, 6, 12, 18].contains(components.hour)
            case .day: return components.day == 1 || components.day == 15
            case .month: return components.month == 1
            }
        }
    }
    static func labelPlacement(index: Int, count: Int, width: CGFloat, labelWidth: CGFloat) -> Placement {
        let raw = (CGFloat(index) + 0.5) * width / CGFloat(max(1, count))
        return Placement(center: raw, alignment: .center)
    }
}
enum TrendAxisFormatting {
    static func hour(_ date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "h a"
        return formatter.string(from: date)
    }
    static func month(_ date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "MMM"
        return formatter.string(from: date)
    }
    static func year(_ date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy"
        return formatter.string(from: date)
    }
}
private struct AnimatedAxisValue: View {
    let value: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        ZStack(alignment: .leading) {
            Text(DisplayFormat.compact(value))
                .contentTransition(.numericText(value: value))
                .animation(reduceMotion ? nil : DataMotion.animation, value: value)
        }
        .frame(width: 38, height: 14, alignment: .leading)
        .clipped()
    }
}
struct FixedBarChart: View {
    let points: [TrendPoint]
    let granularity: TrendGranularity
    var tint: Color? = nil
    var animationMemory = BarAnimationMemory()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var ceiling: Double {
        let value = points.compactMap(\.tokens).max() ?? 0
        guard value > 0 else { return 1 }
        let magnitude = pow(10, floor(log10(value)))
        return ceil(value / magnitude) * magnitude
    }
    var body: some View {
        HStack(alignment: .top, spacing: 5) {
            VStack(spacing: 4) {
                GeometryReader { geometry in
                    ZStack {
                        AnimatedBarPlot(target: animationTarget, tint: tint ?? .accentColor, memory: animationMemory)
                        BarHoverOverlay(points: points, ceiling: ceiling, width: geometry.size.width, height: 136,
                                        hourly: granularity == .hour, tint: tint)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(granularity.accessibilityTitle)
                    .accessibilityChartDescriptor(TrendAccessibility(points: points, ceiling: ceiling, granularity: granularity))
                }.frame(height: 136)
                GeometryReader { geometry in
                    ZStack(alignment: .topLeading) {
                        ForEach(axisIndices, id: \.self) { index in
                            let labelWidth: CGFloat = 40
                            let placement = TrendAxisLayout.labelPlacement(index: index, count: points.count,
                                                                           width: geometry.size.width, labelWidth: labelWidth)
                            Text(axisLabel(points[index].date))
                                .font(.caption2).foregroundStyle(.secondary).lineLimit(1).fixedSize()
                                .frame(width: labelWidth, alignment: labelAlignment(placement.alignment))
                                .position(x: placement.center, y: 10)
                        }
                    }.id(granularity).transition(.opacity)
                        .animation(reduceMotion ? nil : DataMotion.animation, value: granularity)
                }.frame(height: 20)
            }.padding(.horizontal, 20)
            VStack(alignment: .leading, spacing: 0) {
                AnimatedAxisValue(value: ceiling)
                Spacer(minLength: 0)
                AnimatedAxisValue(value: ceiling / 2)
                Spacer(minLength: 0)
                Text("0").frame(width: 38, height: 14, alignment: .leading)
            }.font(.caption2).foregroundStyle(.secondary).frame(width: 38, height: 136, alignment: .leading)
                .clipped()
                .accessibilityLabel(L10n.text("纵轴，零至%@ tokens", String(describing: DisplayFormat.tokens(ceiling))))
        }
    }
    private var animationTarget: BarAnimationTarget {
        var values = Array(repeating: 0.0, count: 31)
        for (index, point) in points.prefix(31).enumerated() {
            values[index] = point.tokens.map { max(0, min(1, $0 / ceiling)) } ?? 0
        }
        return .init(vector: .init(values: values), count: Double(max(1, points.count)))
    }
    private var axisIndices: [Int] {
        TrendAxisLayout.indices(points: points, granularity: granularity)
    }
    private func axisLabel(_ date: Date) -> String {
        switch granularity {
        case .hour: return TrendAxisFormatting.hour(date)
        case .day:
            return Calendar.current.component(.day, from: date) == 1
                ? TrendAxisFormatting.month(date) : "15"
        case .month: return TrendAxisFormatting.year(date)
        }
    }
    private func labelAlignment(_ value: TrendAxisLayout.EdgeAlignment) -> Alignment {
        switch value { case .leading: .leading; case .center: .center; case .trailing: .trailing }
    }
}
struct TrendAccessibility: AXChartDescriptorRepresentable {
    let points: [TrendPoint]
    let ceiling: Double
    let granularity: TrendGranularity
    func makeChartDescriptor() -> AXChartDescriptor {
        let x = AXNumericDataAxisDescriptor(title: L10n.text("日期"), range: 0...Double(max(1, points.count - 1)), gridlinePositions: []) { value in
            let index = min(max(0, Int(value)), max(0, points.count - 1))
            guard points.indices.contains(index) else { return "" }
            return granularity == .hour ? points[index].date.formatted(date: .omitted, time: .shortened) : points[index].date.formatted(date: .abbreviated, time: .omitted)
        }
        let y = AXNumericDataAxisDescriptor(title: "Token", range: 0...ceiling, gridlinePositions: [ceiling / 2, ceiling]) {
            DisplayFormat.tokens($0)
        }
        let values = points.enumerated().compactMap { index, point -> AXDataPoint? in
            guard let tokens = point.tokens else { return nil }
            let label = granularity == .hour
                ? point.date.formatted(date: .abbreviated, time: .shortened)
                : point.date.formatted(date: .abbreviated, time: .omitted)
            return AXDataPoint(x: Double(index), y: tokens, label: label)
        }
        return AXChartDescriptor(title: granularity.accessibilityTitle, summary: L10n.text("缺失日期保留为空白，零值为已报告的零用量。"),
                                 xAxis: x, yAxis: y, series: [AXDataSeriesDescriptor(name: "Token", isContinuous: false, dataPoints: values)])
    }
    func updateChartDescriptor(_ descriptor: AXChartDescriptor) {
        let updated = makeChartDescriptor()
        descriptor.title = updated.title; descriptor.xAxis = updated.xAxis
        descriptor.yAxis = updated.yAxis; descriptor.series = updated.series
    }
}
