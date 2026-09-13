import SwiftUI
import Accessibility
import MonitorCore

struct ToolPicker: View {
    @Bindable var store: AppStore
    var body: some View {
        Picker("工具", selection: $store.preferences.tool) {
            Text("全部工具").tag("")
            ForEach(store.tools, id: \.self) { Text($0 == "codex" ? "Codex" : $0).tag($0) }
        }.onChange(of: store.preferences.tool) { store.savePreferences() }
    }
}
struct ConnectionFooter: View {
    var store: AppStore
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(store.status, systemImage: store.online ? "checkmark.circle" : "exclamationmark.circle")
                .foregroundStyle(store.online ? Color.green : Color.secondary)
            if let date = store.receivedAt {
                Text("数据截至 \(date.formatted(date: .abbreviated, time: .standard))")
            }
            if let error = store.error { Text(error).foregroundStyle(.secondary) }
        }.font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(store.status)。数据截至 \(store.receivedAt?.formatted(date: .abbreviated, time: .standard) ?? "尚无数据")。\(store.error ?? "")")
    }
}
struct SummaryView: View {
    var store: AppStore
    var compact = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(store.selectedToolTitle) · \(store.preferences.period.title)").font(.subheadline).foregroundStyle(.secondary)
            Text(DisplayFormat.tokens(store.selectedTokens))
                .font(.system(size: compact ? 34 : 46, weight: .semibold, design: .rounded))
                .monospacedDigit().lineLimit(1).minimumScaleFactor(0.4)
                .accessibilityLabel("总用量 \(DisplayFormat.tokens(store.selectedTokens)) tokens")
            Text("tokens").foregroundStyle(.secondary)
            Text("\(DisplayFormat.cost(store.selectedCost)) · API 等价估算").font(.subheadline)
                .help("由 Hub 提供的 API 等价费用，不代表订阅账单。")
            if store.stats != nil && store.selectedTokens == nil {
                Text("Hub 尚未报告此工具的数据").font(.caption).foregroundStyle(.secondary)
            } else if store.selectedTokens == 0 {
                Text("此范围已报告 0 用量").font(.caption).foregroundStyle(.secondary)
            }
        }.textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(store.selectedToolTitle)，\(store.preferences.period.title)，总用量 \(DisplayFormat.tokens(store.selectedTokens)) tokens，API 等价估算 \(DisplayFormat.cost(store.selectedCost))。\(store.selectedTokens == nil ? "Hub 尚未报告此工具的数据" : "")")
    }
}
struct SetupPrompt: View {
    var body: some View {
        ContentUnavailableView {
            Label("连接你的 Hub", systemImage: "network")
        } description: {
            Text("填写 Hub 地址与共享密钥，即可查看已有统计。")
        } actions: { SettingsLink { Text("设置连接…") } }
    }
}
struct DeviceRow: View {
    let device: Device
    var store: AppStore
    var compact = false
    var body: some View {
        let stale = device.isStale(at: store.statusClock, threshold: store.stats?.staleAfterMs ?? 600_000)
        let expired = device.periodExpired(store.preferences.period, at: store.statusClock)
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(device.id).fontWeight(.medium).lineLimit(1).truncationMode(.middle)
                Spacer()
                Text(expired ? "上一周期数据" : DisplayFormat.tokens(device.periods[store.preferences.period.rawValue]?.tokens(tool: store.preferences.tool)))
                    .monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
            }
            Label(stale ? "上报数据已过期" : "上报有效", systemImage: stale ? "clock.badge.exclamationmark" : "checkmark.circle")
                .font(.caption).foregroundStyle(stale ? Color.orange : Color.green)
            if let note = device.collectionNote(tool: store.preferences.tool) {
                Text(note).font(.caption).foregroundStyle(.secondary)
            }
            if !compact {
                Text("最后上报：\(device.reportDate?.formatted(date: .abbreviated, time: .standard) ?? "未提供")").font(.caption).foregroundStyle(.secondary)
                if let os = device.osName { Text("\(os) \(device.osVersion ?? "") · Agent \(device.agentVersion ?? "未知")").font(.caption).foregroundStyle(.secondary) }
            }
        }.textSelection(.enabled).accessibilityElement(children: .ignore)
            .accessibilityLabel("\(device.id)，\(expired ? "上一周期数据" : DisplayFormat.tokens(device.periods[store.preferences.period.rawValue]?.tokens(tool: store.preferences.tool)) + " tokens")，\(stale ? "上报数据已过期" : "上报有效")，最后上报 \(device.reportDate?.formatted(date: .abbreviated, time: .standard) ?? "未提供")。\(device.collectionNote(tool: store.preferences.tool) ?? "")")
    }
}
enum Page: String, CaseIterable, Identifiable {
    case overview = "总览", devices = "设备", models = "模型", trends = "趋势", usage = "用量", rate = "实时速率", quota = "额度", activity = "活动"
    var id: String { rawValue }
    var symbol: String { switch self { case .overview: "chart.bar.xaxis"; case .devices: "desktopcomputer"; case .models: "square.stack.3d.up"; case .trends: "chart.xyaxis.line"; case .usage: "number"; case .rate: "speedometer"; case .quota: "gauge.with.dots.needle.50percent"; case .activity: "calendar" } }
}
struct CompactView: View {
    @Bindable var store: AppStore
    @AppStorage("compactPage") private var selectedPage = Page.overview.rawValue
    var body: some View {
        ZStack(alignment: .bottom) {
            PageScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if store.stats == nil { SetupPrompt() }
                    else {
                        if selectedPage != Page.overview.rawValue {
                            Button { selectedPage = Page.overview.rawValue } label: { Label("总览", systemImage: "chevron.left") }.buttonStyle(.plain)
                        }
                        switch Page(rawValue: selectedPage) ?? .overview {
                        case .overview: OverviewView(store: store, selectedPage: $selectedPage)
                        case .devices:
                            Text("设备 · \(store.selectedToolTitle)").font(.headline)
                            if store.devices.isEmpty { Text("尚无设备数据").foregroundStyle(.secondary) }
                            ForEach(store.devices) { DeviceRow(device: $0, store: store) }
                        case .models: ModelsView(store: store)
                        case .trends: TrendsView(store: store)
                        case .usage: UsageDetailView(store: store)
                        case .rate: RateDetailView(store: store)
                        case .quota:
                            QuotaView(store: store)
                            if store.quotaProviders.isEmpty { Text("暂无可用额度数据").foregroundStyle(.secondary) }
                        case .activity: ActivityDetailView(store: store)
                        }
                    }
                    ConnectionFooter(store: store)
                    if !store.online {
                        HStack { Button("刷新") { store.refresh() }; Button("打开 Token Monitor") { Backend.open() } }
                    }
                }.padding(20).padding(.top, 52).padding(.bottom, 64)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
                .id(selectedPage)
            GlassEffectContainer(spacing: 10) {
              HStack(spacing: 10) {
                FloatingMenuButton(items: Page.allCases.map { page in
                    FloatingMenuItem(title: page.rawValue, symbol: page.symbol) { selectedPage = page.rawValue }
                }) {
                    Image(systemName: (Page(rawValue: selectedPage) ?? .overview).symbol)
                        .font(.system(size: 19, weight: .medium)).frame(width: 44, height: 44)
                }.glassEffect(.regular.interactive(), in: .circle)
                    .help(selectedPage).accessibilityLabel("切换页面，当前\(selectedPage)")
                Spacer(minLength: 0)
                FloatingMenuButton(items: [FloatingMenuItem(title: "全部工具", symbol: nil) {
                    store.preferences.tool = ""; store.savePreferences()
                }] + store.tools.map { tool in
                    FloatingMenuItem(title: tool == "codex" ? "Codex" : tool == "claude" ? "Claude" : tool, symbol: nil) {
                        store.preferences.tool = tool; store.savePreferences()
                    }
                }) {
                    Image(systemName: "brain").font(.system(size: 19, weight: .medium)).frame(width: 44, height: 44)
                }.glassEffect(.regular.interactive(), in: .circle)
                    .help(store.selectedToolTitle).accessibilityLabel("选择工具，当前\(store.selectedToolTitle)")
                SettingsLink { Image(systemName: "gearshape").font(.system(size: 20, weight: .medium)).frame(width: 44, height: 44) }
                    .buttonStyle(.plain).glassEffect(.regular.interactive(), in: .circle)
                    .help("设置").accessibilityLabel("设置")
              }
            }.padding(12)
        }.background(Color(nsColor: .windowBackgroundColor))
            .tint(store.preferences.accentColor).accentColor(store.preferences.accentColor)
            .ignoresSafeArea(.container, edges: .top)
            .frame(minWidth: 320)
            .onChange(of: store.tools) { store.reconcileToolSelection() }
            .task { store.reconcileToolSelection(); store.loadHistory() }
    }
}
struct OverviewView: View {
    var store: AppStore
    @Binding var selectedPage: String
    private var sections: [HomeSection] {
        store.preferences.visibleHomeSections.filter {
            switch $0 {
            case .quota: !store.quotaProviders.isEmpty
            case .models: !store.modelRows.isEmpty
            case .devices: !store.devices.isEmpty
            default: true
            }
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            if store.tools.isEmpty {
                ContentUnavailableView("暂无可用数据来源", systemImage: "tray")
            } else if sections.isEmpty {
                ContentUnavailableView {
                    Label("首页暂无栏目", systemImage: "rectangle.grid.1x2")
                } actions: { SettingsLink { Text("设置首页栏目…") } }
            } else {
                ForEach(Array(sections.enumerated()), id: \.element) { index, section in
                    if index > 0 { SectionSeparator() }
                    VStack(alignment: .leading, spacing: 12) {
                        Button { selectedPage = section.page.rawValue } label: {
                            HStack { Text(section.title).font(.headline); Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary) }
                                .contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityLabel("查看\(section.title)详情")
                        sectionBody(section)
                    }
                }
            }
        }
    }
    @ViewBuilder private func sectionBody(_ section: HomeSection) -> some View {
        switch section {
        case .usage: SummaryView(store: store, compact: true)
        case .rate: RateSummaryView(store: store)
        case .quota: QuotaView(store: store, showHeading: false)
        case .devices: ForEach(store.devices) { DeviceRow(device: $0, store: store, compact: true) }
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
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showHeading { HStack { Text("额度").font(.headline); Spacer(); Text("当前状态").font(.caption).foregroundStyle(.secondary) } }
            ForEach(Array(store.quotaProviders.enumerated()), id: \.offset) { index, provider in
                let stale = provider.isStale(now: store.statusClock, threshold: max(store.stats?.staleAfterMs ?? 600_000, (store.stats?.limits?.refreshMs ?? 300_000) * 2))
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(provider.provider == "codex" ? "Codex" : provider.provider).fontWeight(.medium)
                        if store.quotaProviders.filter({ $0.provider == provider.provider }).count > 1 { Text("账号 \(index + 1)").foregroundStyle(.secondary) }
                        Spacer()
                        Text(stale ? "数据已过期" : provider.statusTitle).foregroundStyle(.secondary)
                    }.font(.caption)
                    ForEach(Array(provider.windows.enumerated()), id: \.offset) { _, window in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(window.title).lineLimit(2)
                                Spacer(minLength: 8)
                                Text(window.remainingTitle).monospacedDigit().fixedSize(horizontal: false, vertical: true)
                            }.font(.subheadline)
                            if window.showMeter != false, let percent = window.validPercent {
                                ProgressView(value: percent, total: 100).accessibilityLabel("\(window.title)，\(window.remainingTitle)")
                            }
                            if let date = DateCodec.parse(window.resetsAt) {
                                Text(date <= store.statusClock ? "周期已结束 · 等待更新" : "\(window.boundaryKind == "expiry" ? "到期" : "重置")：\(date.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    if provider.windows.isEmpty { Text("没有可显示的额度窗口").font(.caption).foregroundStyle(.secondary) }
                    if let date = DateCodec.parse(provider.updatedAt) { Text("更新于 \(date.formatted(date: .omitted, time: .shortened))").font(.caption2).foregroundStyle(.secondary) }
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
            .accessibilityLabel("\(row.name)，\(DisplayFormat.tokens(row.tokens)) tokens，API 等价估算 \(DisplayFormat.cost(row.cost))")
    }
}
struct ModelsView: View {
    @Bindable var store: AppStore
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("模型 · \(store.preferences.period.title)").font(.headline)
            Picker("排序", selection: $store.preferences.modelSortByCost) { Text("Token 用量").tag(false); Text("估算费用").tag(true) }
                .onChange(of: store.preferences.modelSortByCost) { store.savePreferences() }
            if store.modelRows.isEmpty { Text("尚无模型明细").foregroundStyle(.secondary) }
            ForEach(store.modelRows) { ModelUsageRow(row: $0) }
        }
    }
}
struct HistoryNotice: View {
    var store: AppStore
    var body: some View {
        if store.historyBusy { ProgressView("读取历史…").controlSize(.small) }
        if let error = store.historyError {
            Text(error).font(.caption).foregroundStyle(.secondary)
            Button("重试历史请求") { store.loadHistory() }
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
    @State private var selected: Date?
    @State private var visibleWeeks = 16
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiate
    var body: some View {
        let points = store.historyPoints(activity: true, minimumWeeks: visibleWeeks)
        let maximum = points.compactMap(\.tokens).max() ?? 0
        let columns = (points.count + 6) / 7
        VStack(alignment: .leading, spacing: 10) {
            if showHeading || selected != nil {
                HStack {
                    if showHeading { Text("活动").font(.headline) }
                    Spacer()
                    if let point = points.first(where: { $0.date == selected }) {
                        Text(description(point)).font(.caption).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
                    }
                }
            }
            if points.isEmpty { Text("尚无活动数据").font(.caption).foregroundStyle(.secondary) }
            else {
                HistoryScrollView(width: CGFloat(columns * 10 + 29), height: 104,
                                  resetKey: store.preferences.tool + store.historyPresentationID.uuidString, prepends: true, points: points, tint: store.preferences.accentColor) {
                    Canvas { context, _ in
                        for (index, point) in points.enumerated() {
                            let rect = CGRect(x: 16 + (index / 7) * 10, y: 8 + (index % 7) * 10, width: 7, height: 7)
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
                        .contentShape(Rectangle())
                        .onContinuousHover { phase in
                            if case .active(let location) = phase {
                                let week = Int(floor((location.x - 16) / 10)), day = Int(floor((location.y - 8) / 10))
                                let index = week * 7 + day
                                if week >= 0, (0..<7).contains(day), points.indices.contains(index) { selected = points[index].date }
                            }
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("活动热力图，缺失日期无数据")
                        .accessibilityChartDescriptor(TrendAccessibility(points: points, ceiling: max(1, maximum), monthly: false))
                }.frame(height: 104)
                    .onGeometryChange(for: Int.self) { max(16, Int(ceil(($0.size.width - 29) / 10))) } action: { visibleWeeks = $0 }
                    .modifier(HistoryBorder())
            }
        }
    }
    private func color(_ value: Double?, maximum: Double) -> Color {
        guard let value, value > 0, maximum > 0 else { return Color(nsColor: .systemGray).opacity(0.18) }
        return (differentiate ? Color.primary : Color.accentColor).opacity(0.25 + 0.75 * sqrt(value / maximum))
    }
    private func description(_ point: TrendPoint) -> String {
        "\(point.date.formatted(date: .abbreviated, time: .omitted)) · \(point.tokens.map { DisplayFormat.tokens($0) + " tokens" } ?? "无数据")"
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
        } else { Text("此范围尚无历史数据").font(.caption).foregroundStyle(.secondary) }
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
            HistoryScrollView(width: CGFloat(points.count) * slot + 32, height: 160, resetKey: resetKey + (monthly ? "month" : "day"), points: points, tint: tint) {
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
                .accessibilityLabel("纵轴，零至\(DisplayFormat.tokens(ceiling)) tokens")
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
                let height = CGFloat(min(1, tokens / scale)) * size.height
                bars.addRoundedRect(in: CGRect(x: CGFloat(index) * slot + 1, y: size.height - height,
                                               width: 5, height: height),
                                    cornerSize: CGSize(width: min(2.5, height / 2), height: min(2.5, height / 2)))
            }
            context.fill(bars, with: .color(.accentColor))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(monthly ? "每月 Token 用量" : "每日 Token 用量")
        .accessibilityChartDescriptor(TrendAccessibility(points: points, ceiling: ceiling, monthly: monthly))
    }
}
struct TrendAccessibility: AXChartDescriptorRepresentable {
    let points: [TrendPoint]
    let ceiling: Double
    let monthly: Bool
    func makeChartDescriptor() -> AXChartDescriptor {
        let x = AXNumericDataAxisDescriptor(title: "日期", range: 0...Double(max(1, points.count - 1)), gridlinePositions: []) { value in
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
        return AXChartDescriptor(title: monthly ? "每月 Token 用量" : "每日 Token 用量", summary: "缺失日期保留为空白，零值为已报告的零用量。",
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
    @State private var monthly = false
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("趋势 · \(store.selectedToolTitle)").font(.headline)
            Picker("趋势范围", selection: $monthly) { Text("按日").tag(false); Text("按月").tag(true) }.pickerStyle(.segmented).labelsHidden()
            HistoryNotice(store: store)
            let points = store.historyPoints(monthly: monthly)
            UsageChart(points: points, monthly: monthly, resetKey: store.preferences.tool + store.historyPresentationID.uuidString, tint: store.preferences.accentColor)
            ForEach(points.reversed()) { point in
                HStack { Text(point.date, format: monthly ? .dateTime.year().month() : .dateTime.month().day()); Spacer(); Text(point.tokens.map { DisplayFormat.tokens($0) } ?? "无数据").monospacedDigit() }.font(.caption)
            }
        }
    }
}
