import SwiftUI
import MonitorCore
import AppKit
import UniformTypeIdentifiers

extension ThemeColor {
    var color: Color? {
        switch self {
        case .system, .custom: nil
        case .blue: .blue
        case .purple: .purple
        case .pink: .pink
        case .red: .red
        case .orange: .orange
        case .green: .green
        case .teal: .teal
        }
    }
}
extension HomeSection {
    var page: Page {
        switch self {
        case .usage: .usage
        case .rate: .rate
        case .quota: .quota
        case .devices: .devices
        case .models: .models
        case .activity: .activity
        case .trends: .trends
        }
    }
}
extension RuntimePreferences {
    var accentColor: Color? {
        themeColor == .custom
            ? Color(.sRGB, red: customThemeColor.red, green: customThemeColor.green, blue: customThemeColor.blue)
            : themeColor.color
    }
}
struct ThemeColorSettings: View {
    @Bindable var store: AppStore
    var body: some View {
        Toggle("跟随系统主题色", isOn: Binding(
            get: { store.preferences.themeColor == .system },
            set: { store.preferences.themeColor = $0 ? .system : .custom }
        ))
        ColorPicker("自定义主题色", selection: Binding(
            get: { store.preferences.accentColor ?? Color.accentColor },
            set: { color in
                guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return }
                store.preferences.customThemeColor = RGBColor(red: rgb.redComponent, green: rgb.greenComponent, blue: rgb.blueComponent)
                store.preferences.themeColor = .custom
            }
        ), supportsOpacity: false)
        .help("打开系统颜色选择器，选择任意主题色")
    }
}
private let homeSectionDragType = UTType(exportedAs: "local.tokenmonitor.native.home-section")
struct HomeLayoutSettings: View {
    @Bindable var store: AppStore
    @State private var dragging: HomeSection?
    var body: some View {
        Form {
            Section("首页栏目") {
                ForEach(store.preferences.homeSections) { section in
                    HStack(spacing: 12) {
                        Toggle(section.title, isOn: Binding(
                            get: { !store.preferences.hiddenHomeSections.contains(section) },
                            set: { visible in
                                if visible { store.preferences.hiddenHomeSections.remove(section) }
                                else { store.preferences.hiddenHomeSections.insert(section) }
                            }
                        ))
                        Spacer()
                        Image(systemName: "line.3.horizontal")
                            .foregroundStyle(.secondary)
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                            .onDrag {
                                dragging = section
                                let provider = NSItemProvider()
                                provider.registerDataRepresentation(forTypeIdentifier: homeSectionDragType.identifier, visibility: .ownProcess) { completion in
                                    completion(Data(section.rawValue.utf8), nil)
                                    return nil
                                }
                                return provider
                            } preview: {
                                Label(section.title, systemImage: "line.3.horizontal").padding(8)
                            }
                            .help("拖动以调整\(section.title)的位置")
                            .accessibilityLabel("调整\(section.title)顺序")
                            .accessibilityAddTraits(.isButton)
                            .accessibilityAction(named: "上移") { store.preferences.moveHomeSection(section, by: -1) }
                            .accessibilityAction(named: "下移") { store.preferences.moveHomeSection(section, by: 1) }
                    }
                    .controlSize(.regular)
                    .contentShape(Rectangle())
                    .onDrop(of: [homeSectionDragType], delegate: HomeSectionDropDelegate(
                        section: section, store: store, dragging: $dragging
                    ))
                }
            }
            Section {
                Button("恢复默认布局") {
                    store.preferences.homeSections = HomeSection.allCases
                    store.preferences.hiddenHomeSections = [.devices]
                }
                Text("用开关控制可见性，按住右侧手柄上下拖动排序。隐藏首页栏目不会删除统计数据，仍可通过页面菜单查看详情。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
    }
}
private struct HomeSectionDropDelegate: DropDelegate {
    let section: HomeSection
    let store: AppStore
    @Binding var dragging: HomeSection?
    func validateDrop(info: DropInfo) -> Bool {
        dragging != nil && info.hasItemsConforming(to: [homeSectionDragType])
    }
    func dropEntered(info: DropInfo) {
        guard validateDrop(info: info), let dragging, dragging != section else { return }
        store.preferences.moveHomeSection(dragging, to: section)
    }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
    func performDrop(info: DropInfo) -> Bool {
        guard validateDrop(info: info) else { return false }
        dragging = nil
        store.savePreferences()
        return true
    }
}
struct RateSummaryView: View {
    var store: AppStore
    var body: some View {
        HStack {
            Text("所有工具")
            Spacer()
            Text(store.rate.map { "≈ \(DisplayFormat.compact($0.burn)) tok/min\($0.idle ? " · 暂闲" : "")" } ?? "—")
        }.font(.caption).foregroundStyle(.secondary)
    }
}
struct UsageDetailView: View {
    var store: AppStore
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("用量详情").font(.headline)
            SummaryView(store: store, compact: true)
            SectionSeparator()
            LabeledContent("缓存读取", value: DisplayFormat.tokens(store.usage?.cache(tool: store.preferences.tool)))
            LabeledContent("输出 Token", value: DisplayFormat.tokens(store.usage?.output(tool: store.preferences.tool)))
            Text("设备分项").font(.headline)
            ForEach(store.devices) { DeviceRow(device: $0, store: store, compact: true) }
        }.textSelection(.enabled)
    }
}
struct RateDetailView: View {
    var store: AppStore
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("实时速率 · 所有工具").font(.headline)
            LabeledContent("Token 消耗速率", value: store.rate.map { "≈ \(DisplayFormat.compact($0.burn)) tok/min" } ?? "—")
            LabeledContent("输出速度", value: store.rate.map { "≈ \(DisplayFormat.compact($0.speed)) tok/s" } ?? "—")
            if let sample = store.rate {
                LabeledContent("状态", value: sample.idle ? "暂闲" : "活跃")
                LabeledContent("最近样本", value: sample.at.formatted(date: .omitted, time: .standard))
            } else { Text("等待足够的有效计时样本").foregroundStyle(.secondary) }
            Text("速率依据设备上报的计时增量计算。Hub 尚未按工具拆分计时，因此此处始终显示所有工具。").font(.caption).foregroundStyle(.secondary)
        }.textSelection(.enabled)
    }
}
struct ActivityDetailView: View {
    var store: AppStore
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ActivityView(store: store)
            HistoryNotice(store: store)
            Text("每日活动 · \(store.selectedToolTitle)").font(.headline)
            ForEach((store.historyPoints()).reversed()) { point in
                HStack {
                    Text(point.date, format: .dateTime.year().month().day())
                    Spacer()
                    Text(point.tokens.map { DisplayFormat.tokens($0) + " tokens" } ?? "无数据").monospacedDigit()
                }.font(.caption).textSelection(.enabled)
            }
        }
    }
}
