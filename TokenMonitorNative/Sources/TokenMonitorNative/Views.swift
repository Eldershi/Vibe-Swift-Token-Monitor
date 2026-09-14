import SwiftUI
import Accessibility
import MonitorCore

struct ToolPicker: View {
    @Bindable var store: AppStore
    var body: some View {
        Picker(L10n.text("工具"), selection: $store.preferences.tool) {
            Text(L10n.text("全部工具")).tag("")
            ForEach(store.tools, id: \.self) { Text($0 == "codex" ? "Codex" : $0).tag($0) }
        }.onChange(of: store.preferences.tool) { store.savePreferences() }
    }
}
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
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(store.selectedToolTitle).font(.subheadline).foregroundStyle(.secondary)
            Text(DisplayFormat.tokens(store.selectedTokens))
                .font(.system(size: compact ? 34 : 46, weight: .semibold, design: .rounded))
                .monospacedDigit().lineLimit(1).minimumScaleFactor(0.4)
                .accessibilityLabel(L10n.text("总用量 %@ tokens", String(describing: DisplayFormat.tokens(store.selectedTokens))))
            Text("tokens").foregroundStyle(.secondary)
            Text(L10n.text("%@ · API 等价估算", String(describing: DisplayFormat.cost(store.selectedCost)))).font(.subheadline)
                .help(L10n.text("由 Hub 提供的 API 等价费用，不代表订阅账单。"))
            if store.stats != nil && store.selectedTokens == nil {
                Text(L10n.text("Hub 尚未报告此工具的数据")).font(.caption).foregroundStyle(.secondary)
            } else if store.selectedTokens == 0 {
                Text(L10n.text("此范围已报告 0 用量")).font(.caption).foregroundStyle(.secondary)
            }
        }.textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L10n.text("%@，%@，总用量 %@ tokens，API 等价估算 %@。%@", String(describing: store.selectedToolTitle), String(describing: store.preferences.period.title), String(describing: DisplayFormat.tokens(store.selectedTokens)), String(describing: DisplayFormat.cost(store.selectedCost)), String(describing: store.selectedTokens == nil ? L10n.text("Hub 尚未报告此工具的数据") : "")))
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
    private var collectionNote: String? { compact ? nil : device.collectionNote(tool: store.preferences.tool) }
    private var displayedFraction: Double? { !compact || store.preferences.showHomeDeviceUsageBars ? usageFraction : nil }
    var body: some View {
        let stale = device.isStale(at: store.statusClock, threshold: store.stats?.staleAfterMs ?? 600_000)
        let expired = device.periodExpired(store.preferences.period, at: store.statusClock)
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                HStack(alignment: .center, spacing: 6) {
                    DeviceSystemIcon(osName: device.osName)
                    Text(device.id).fontWeight(.medium).lineLimit(1).truncationMode(.middle)
                }
                Spacer()
                Text(expired ? L10n.text("上一周期数据") : DisplayFormat.tokens(device.periods[store.preferences.period.rawValue]?.tokens(tool: store.preferences.tool)))
                    .monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
            }
            if let fraction = displayedFraction {
                ProgressView(value: fraction, total: 1).progressViewStyle(.linear)
                    .tint(store.preferences.accentColor)
                    .accessibilityLabel(L10n.text("相对最高用量设备"))
                    .accessibilityValue(fraction.formatted(.percent.precision(.fractionLength(0))))
            }
            Label(stale ? L10n.text("上报数据已过期") : L10n.text("上报有效"), systemImage: stale ? "clock.badge.exclamationmark" : "checkmark.circle")
                .font(.caption).foregroundStyle(stale ? Color.orange : Color.green)
            if let note = collectionNote {
                Text(note).font(.caption).foregroundStyle(.secondary)
            }
            if !compact {
                Text(L10n.text("最后上报：%@", String(describing: device.reportDate?.formatted(date: .abbreviated, time: .standard) ?? L10n.text("未提供")))).font(.caption).foregroundStyle(.secondary)
                if let os = device.osName { Text("\(os) \(device.osVersion ?? "") · Agent \(device.agentVersion ?? L10n.text("未知"))").font(.caption).foregroundStyle(.secondary) }
            }
        }.textSelection(.enabled).accessibilityElement(children: .ignore)
            .accessibilityLabel(L10n.text("%@，%@，%@，最后上报 %@。%@", String(describing: device.id), String(describing: expired ? L10n.text("上一周期数据") : DisplayFormat.tokens(device.periods[store.preferences.period.rawValue]?.tokens(tool: store.preferences.tool)) + " tokens"), String(describing: stale ? L10n.text("上报数据已过期") : L10n.text("上报有效")), String(describing: device.reportDate?.formatted(date: .abbreviated, time: .standard) ?? L10n.text("未提供")), String(describing: collectionNote ?? "")) + (displayedFraction.map { " " + L10n.text("相对最高用量设备：%@", $0.formatted(.percent.precision(.fractionLength(0)))) } ?? ""))
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
    case overview = "总览", devices = "设备", models = "模型", trends = "趋势", quota = "额度", activity = "活动"
    var title: String { L10n.text(rawValue) }
    var id: String { rawValue }
    var symbol: String { switch self { case .overview: "chart.bar.xaxis"; case .devices: "server.rack"; case .models: "square.stack.3d.up"; case .trends: "chart.xyaxis.line"; case .quota: "timer"; case .activity: "calendar" } }
}
struct CompactView: View {
    @Bindable var store: AppStore
    @AppStorage("compactPage") private var selectedPage = Page.overview.rawValue
    var body: some View {
        ZStack(alignment: .bottom) {
            PageScrollView(tint: store.preferences.accentColor) {
                VStack(alignment: .leading, spacing: 22) {
                    if store.stats == nil { SetupPrompt() }
                    else {
                        if selectedPage != Page.overview.rawValue {
                            HStack(spacing: 8) {
                                Button { selectedPage = Page.overview.rawValue } label: {
                                    Image(systemName: "chevron.left").font(.body.weight(.medium))
                                        .frame(width: 20, height: 28)
                                }.buttonStyle(.plain).help(L10n.text("返回总览")).accessibilityLabel(L10n.text("返回总览"))
                                Text((Page(rawValue: selectedPage) ?? .overview).title).font(.headline)
                                Spacer(minLength: 8)
                                if selectedPage == Page.models.rawValue { ModelSortPicker(store: store) }
                            }
                        }
                        switch Page(rawValue: selectedPage) ?? .overview {
                        case .overview: OverviewView(store: store, selectedPage: $selectedPage)
                        case .devices:
                            if store.devices.isEmpty { Text(L10n.text("尚无设备数据")).foregroundStyle(.secondary) }
                            let fractions = store.deviceUsageFractions
                            ForEach(store.devices) { DeviceRow(device: $0, usageFraction: fractions[$0.id], store: store) }
                        case .models: ModelsView(store: store)
                        case .trends: TrendsView(store: store)
                        case .quota:
                            QuotaView(store: store, showHeading: false)
                            if store.quotaProviders.isEmpty { Text(L10n.text("暂无可用额度数据")).foregroundStyle(.secondary) }
                        case .activity: ActivityDetailView(store: store)
                        }
                    }
                    ConnectionFooter(store: store)
                }.padding(20).padding(.bottom, 64)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
                .id(selectedPage)
            GlassEffectContainer(spacing: 10) {
                HStack(spacing: 10) {
                    HStack(spacing: 0) {
                        FloatingMenuButton(items: Page.allCases.map { page in
                            FloatingMenuItem(title: page.title, symbol: page.symbol) { selectedPage = page.rawValue }
                        }) {
                            Image(systemName: (Page(rawValue: selectedPage) ?? .overview).symbol)
                                .font(.system(size: 19, weight: .medium)).frame(width: 44, height: 44)
                        }.help((Page(rawValue: selectedPage) ?? .overview).title).accessibilityLabel(L10n.text("切换页面，当前%@", String(describing: (Page(rawValue: selectedPage) ?? .overview).title)))
                        Divider().frame(height: 20).accessibilityHidden(true)
                        FloatingMenuButton(items: [FloatingMenuItem(title: L10n.text("全部工具"), symbol: nil) {
                            store.preferences.tool = ""; store.savePreferences()
                        }] + store.tools.map { tool in
                            FloatingMenuItem(title: tool == "codex" ? "Codex" : tool == "claude" ? "Claude" : tool, symbol: nil) {
                                store.preferences.tool = tool; store.savePreferences()
                            }
                        }) {
                            Image(systemName: "brain").font(.system(size: 19, weight: .medium)).frame(width: 44, height: 44)
                        }.help(store.selectedToolTitle).accessibilityLabel(L10n.text("选择工具，当前%@", String(describing: store.selectedToolTitle)))
                    }.glassEffect(.regular.interactive(), in: .capsule)
                    Spacer(minLength: 0)
                    Button { store.refresh() } label: {
                        Image(systemName: "arrow.clockwise").font(.system(size: 19, weight: .medium))
                            .frame(width: 44, height: 44)
                    }.buttonStyle(.plain).glassEffect(.regular.interactive(), in: .circle)
                        .help(L10n.text("刷新")).accessibilityLabel(L10n.text("刷新"))
                    SettingsLink { InterfaceSymbols.gear.frame(width: 44, height: 44) }
                        .buttonStyle(.plain).glassEffect(.regular.interactive(), in: .circle)
                        .help(L10n.text("设置")).accessibilityLabel(L10n.text("设置"))
                }
            }.padding(12)
        }.background(Color(nsColor: .windowBackgroundColor))
            .tint(store.preferences.accentColor).accentColor(store.preferences.accentColor)
            .frame(minWidth: 320)
            .onChange(of: store.tools) { store.reconcileToolSelection() }
            .task { if Page(rawValue: selectedPage) == nil { selectedPage = Page.overview.rawValue }; store.reconcileToolSelection(); store.loadHistory() }
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
        VStack(alignment: .leading, spacing: 24) {
            if store.tools.isEmpty && store.homeQuotaProviders.isEmpty {
                ContentUnavailableView(L10n.text("暂无可用数据来源"), systemImage: "tray")
                    .frame(maxWidth: .infinity)
            } else if sections.isEmpty {
                ContentUnavailableView {
                    Label(L10n.text("首页暂无栏目"), systemImage: "rectangle.grid.1x2")
                } actions: { SettingsLink { Text(L10n.text("布局设置…")) } }
                    .frame(maxWidth: .infinity)
            } else {
                ForEach(Array(sections.enumerated()), id: \.element) { index, section in
                    if index > 0 { SectionSeparator() }
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
                                    Image(systemName: section.page.symbol).font(.body).foregroundStyle(store.preferences.accentColor ?? Color.accentColor)
                                }.buttonStyle(.plain).accessibilityLabel(L10n.text("查看%@详情", section.title))
                            }
                        }
                        sectionBody(section)
                    }
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
        case .models: ForEach(store.modelRows.prefix(3)) { ModelUsageRow(row: $0) }
        case .activity: ActivityView(store: store, showHeading: false)
        case .trends:
            HistoryNotice(store: store)
            UsageChart(points: store.historyPoints(), monthly: false, resetKey: store.preferences.tool + store.historyPresentationID.uuidString, tint: store.preferences.accentColor)
        }
    }
}
struct SectionSeparator: View {
    var body: some View { Divider().padding(.horizontal, 12).accessibilityHidden(true) }
}
struct QuotaView: View {
    var store: AppStore
    var showHeading = true
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
                        if providers.filter({ $0.provider == provider.provider }).count > 1 { Text(L10n.text("账号 %@", String(describing: index + 1))).foregroundStyle(.secondary) }
                        Spacer()
                        Text(stale ? L10n.text("数据已过期") : provider.statusTitle).foregroundStyle(.secondary)
                    }.font(.caption)
                    ForEach(Array(provider.windows.filter(\.hasReportedQuota).enumerated()), id: \.offset) { _, window in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(window.title).lineLimit(2)
                                Spacer(minLength: 8)
                                Text(window.remainingTitle).monospacedDigit().fixedSize(horizontal: false, vertical: true)
                            }.font(.subheadline)
                            if window.showMeter != false, let percent = window.validPercent {
                                ProgressView(value: percent, total: 100).accessibilityLabel(L10n.text("%@，%@", window.title, window.remainingTitle))
                            }
                            if let date = DateCodec.parse(window.resetsAt) {
                                Text(date <= store.statusClock ? L10n.text("周期已结束 · 等待更新") : L10n.text("%@：%@", window.boundaryKind == "expiry" ? L10n.text("到期") : L10n.text("重置"), date.formatted(date: .abbreviated, time: .shortened)))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    if provider.windows.isEmpty { Text(L10n.text("没有可显示的额度窗口")).font(.caption).foregroundStyle(.secondary) }
                    if let date = DateCodec.parse(provider.updatedAt) { Text(L10n.text("更新于 %@", String(describing: date.formatted(date: .omitted, time: .shortened)))).font(.caption2).foregroundStyle(.secondary) }
                }
            }
        }
    }
}
struct ModelUsageRow: View {
    let row: ModelRow
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(row.name).fontWeight(.medium).lineLimit(2).help(row.name)
            HStack { Text("\(DisplayFormat.tokens(row.tokens)) tokens"); Spacer(); Text(DisplayFormat.cost(row.cost)) }
                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
        }.textSelection(.enabled).accessibilityElement(children: .ignore)
            .accessibilityLabel(L10n.text("%@，%@ tokens，API 等价估算 %@", String(describing: row.name), String(describing: DisplayFormat.tokens(row.tokens)), String(describing: DisplayFormat.cost(row.cost))))
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
            if store.modelRows.isEmpty { Text(L10n.text("尚无模型明细")).foregroundStyle(.secondary) }
            ForEach(store.modelRows) { ModelUsageRow(row: $0) }
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
    func body(content: Content) -> some View {
        content.overlay(RoundedRectangle(cornerRadius: 8)
            .stroke(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 0.5).allowsHitTesting(false))
    }
}
struct ActivityView: View {
    var store: AppStore
    var showHeading = true
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
                                  resetKey: store.preferences.tool + store.historyPresentationID.uuidString, prepends: true, points: points, tint: store.preferences.accentColor, heatmapHover: true, viewportChanged: { width in
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
                        .accessibilityChartDescriptor(TrendAccessibility(points: points, ceiling: max(1, maximum), monthly: false))
                }.frame(height: 104)
                    .modifier(HistoryBorder())
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
    let monthly: Bool
    var resetKey = ""
    var tint: Color? = nil
    var body: some View {
        if points.contains(where: { $0.tokens != nil }) {
            FixedBarChart(points: points, monthly: monthly, resetKey: resetKey, tint: tint).equatable().padding(10).frame(height: 180).modifier(HistoryBorder())
        } else { Text(L10n.text("此范围尚无历史数据")).font(.caption).foregroundStyle(.secondary) }
    }
}
struct FixedBarChart: View, Equatable {
    let points: [TrendPoint]
    let monthly: Bool
    var resetKey = ""
    var tint: Color? = nil
    private let slot: CGFloat = 7
    private var ceiling: Double {
        let value = points.compactMap(\.tokens).max() ?? 0
        guard value > 0 else { return 1 }
        let magnitude = pow(10, floor(log10(value)))
        return ceil(value / magnitude) * magnitude
    }
    var body: some View {
        HStack(alignment: .top, spacing: 5) {
            HistoryScrollView(width: CGFloat(points.count) * slot + 32, height: 160, resetKey: resetKey + (monthly ? "month" : "day"), points: points, tint: tint, barHover: .bars(ceiling: ceiling, slot: slot, height: 136)) {
                VStack(spacing: 4) {
                    bars.frame(height: 136)
                    ZStack(alignment: .topLeading) {
                        ForEach(monthly ? points.indices.filter { $0.isMultiple(of: 4) } : HistoryGeometry.monthIndices(points), id: \.self) { index in
                            Text(points[index].date.formatted(.dateTime.month(.abbreviated)))
                                .font(.caption2).foregroundStyle(.secondary).fixedSize()
                                .position(x: CGFloat(index) * slot + slot / 2, y: 10)
                        }
                    }.frame(height: 20)
                }.frame(width: CGFloat(points.count) * slot).padding(.horizontal, 16)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(DisplayFormat.compact(ceiling))
                Spacer(minLength: 0)
                Text(DisplayFormat.compact(ceiling / 2))
                Spacer(minLength: 0)
                Text("0")
            }.font(.caption2).foregroundStyle(.secondary).frame(width: 38, height: 136, alignment: .leading)
                .accessibilityLabel(L10n.text("纵轴，零至%@ tokens", String(describing: DisplayFormat.tokens(ceiling))))
        }
    }
    private var bars: some View {
        Canvas { context, size in
            let scale = ceiling
            var grid = Path()
            for y in [CGFloat(0.5), size.height / 2] {
                grid.move(to: CGPoint(x: 0, y: y))
                grid.addLine(to: CGPoint(x: size.width, y: y))
            }
            context.stroke(grid, with: .color(Color(nsColor: .separatorColor).opacity(0.5)), lineWidth: 0.5)
            var bars = Path()
            for (index, point) in points.enumerated() {
                guard let tokens = point.tokens, tokens > 0 else { continue }
                let geometry = ChartHoverGeometry.bars(ceiling: scale, slot: slot, height: size.height)
                let rect = geometry.rect(at: index, points: points).offsetBy(dx: -16, dy: 0)
                let radius = geometry.cornerRadius(for: rect)
                bars.addRoundedRect(in: rect, cornerSize: CGSize(width: radius, height: radius))
            }
            context.fill(bars, with: .color(.accentColor))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(monthly ? L10n.text("每月 Token 用量") : L10n.text("每日 Token 用量"))
        .accessibilityChartDescriptor(TrendAccessibility(points: points, ceiling: ceiling, monthly: monthly))
    }
}
struct TrendAccessibility: AXChartDescriptorRepresentable {
    let points: [TrendPoint]
    let ceiling: Double
    let monthly: Bool
    func makeChartDescriptor() -> AXChartDescriptor {
        let x = AXNumericDataAxisDescriptor(title: L10n.text("日期"), range: 0...Double(max(1, points.count - 1)), gridlinePositions: []) { value in
            let index = min(max(0, Int(value)), max(0, points.count - 1))
            return points.indices.contains(index) ? points[index].date.formatted(date: .abbreviated, time: .omitted) : ""
        }
        let y = AXNumericDataAxisDescriptor(title: "Token", range: 0...ceiling, gridlinePositions: [ceiling / 2, ceiling]) {
            DisplayFormat.tokens($0)
        }
        let values = points.enumerated().compactMap { index, point -> AXDataPoint? in
            guard let tokens = point.tokens else { return nil }
            return AXDataPoint(x: Double(index), y: tokens, label: point.date.formatted(date: .abbreviated, time: .omitted))
        }
        return AXChartDescriptor(title: monthly ? L10n.text("每月 Token 用量") : L10n.text("每日 Token 用量"), summary: L10n.text("缺失日期保留为空白，零值为已报告的零用量。"),
                                 xAxis: x, yAxis: y, series: [AXDataSeriesDescriptor(name: "Token", isContinuous: false, dataPoints: values)])
    }
    func updateChartDescriptor(_ descriptor: AXChartDescriptor) {
        let updated = makeChartDescriptor()
        descriptor.title = updated.title; descriptor.xAxis = updated.xAxis
        descriptor.yAxis = updated.yAxis; descriptor.series = updated.series
    }
}

struct TrendsView: View {
    var store: AppStore
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HistoryNotice(store: store)
            let points = store.historyPoints()
            UsageChart(points: points, monthly: false, resetKey: store.preferences.tool + store.historyPresentationID.uuidString, tint: store.preferences.accentColor)
            ForEach(points.reversed()) { point in
                HStack { Text(point.date, format: .dateTime.month().day()); Spacer(); Text(point.tokens.map { DisplayFormat.tokens($0) } ?? L10n.text("无数据")).monospacedDigit() }.font(.caption)
            }
        }
    }
}
