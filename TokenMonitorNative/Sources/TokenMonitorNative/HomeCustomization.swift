import SwiftUI
import MonitorCore
import AppKit

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
    var symbol: String {
        switch self {
        case .activity: "calendar"
        case .trends: "chart.xyaxis.line"
        case .devices: "server.rack"
        case .models: "square.stack.3d.up"
        default: page.symbol
        }
    }
    var page: Page {
        switch self {
        case .usage: .overview
        case .quota: .quota
        case .devices: .activity
        case .models: .activity
        case .activity: .activity
        case .trends: .activity
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
        Toggle(L10n.text("跟随系统主题色"), isOn: Binding(
            get: { store.preferences.themeColor == .system },
            set: { store.preferences.themeColor = $0 ? .system : .custom }
        ))
        ColorPicker(L10n.text("自定义主题色"), selection: Binding(
            get: { store.preferences.accentColor ?? Color.accentColor },
            set: { color in
                guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return }
                store.preferences.customThemeColor = RGBColor(red: rgb.redComponent, green: rgb.greenComponent, blue: rgb.blueComponent)
                store.preferences.themeColor = .custom
            }
        ), supportsOpacity: false)
        .help(L10n.text("打开系统颜色选择器，选择任意主题色"))
    }
}
struct HomeLayoutSettings: View {
    @Bindable var store: AppStore
    @State private var dragHandles = HomeDragHandles()
    var body: some View {
        Form {
            Section(L10n.text("首页栏目")) {
                VStack(spacing: 4) {
                    ForEach(store.preferences.homeSections.filter { $0 != .usage }) { section in
                        HStack(spacing: 12) {
                            Toggle(section.title, isOn: Binding(
                                get: { !store.preferences.hiddenHomeSections.contains(section) },
                                set: { visible in
                                    if visible { store.preferences.hiddenHomeSections.remove(section) }
                                    else { store.preferences.hiddenHomeSections.insert(section) }
                                }
                            ))
                            Spacer()
                            HomeDragHandle(section: section, handles: dragHandles, move: { destination in
                                store.preferences.moveHomeSection(section, to: destination)
                            }, finish: { store.savePreferences() }, step: { offset in
                                store.preferences.moveHomeSection(section, by: offset)
                                store.savePreferences()
                            })
                                .frame(width: 28, height: 24)
                                .help(L10n.text("拖动以调整%@的位置", String(describing: section.title)))
                                .accessibilityAction(named: L10n.text("上移")) { store.preferences.moveHomeSection(section, by: -1); store.savePreferences() }
                                .accessibilityAction(named: L10n.text("下移")) { store.preferences.moveHomeSection(section, by: 1); store.savePreferences() }
                        }
                        .frame(height: 28)
                        .contentShape(Rectangle())
                    }
                }
            }
            Section(L10n.text("额度")) {
                HomeQuotaSettings(store: store)
                    .disabled(store.preferences.hiddenHomeSections.contains(.quota))
                if store.preferences.hiddenHomeSections.contains(.quota) {
                    Text(L10n.text("请先开启首页的额度栏目")).font(.caption).foregroundStyle(.secondary)
                }
            }
            Section(L10n.text("设备")) {
                Toggle(L10n.text("首页显示设备用量条"), isOn: $store.preferences.showHomeDeviceUsageBars)
                    .disabled(store.preferences.hiddenHomeSections.contains(.devices))
                if store.preferences.hiddenHomeSections.contains(.devices) {
                    Text(L10n.text("请先开启首页的设备栏目")).font(.caption).foregroundStyle(.secondary)
                }
            }
            Section(L10n.text("图表")) { ChartStyleSettings(store: store) }
            Section(L10n.text("菜单栏")) { MenuBarSettings(store: store) }
            Section {
                Button(L10n.text("恢复默认布局")) {
                    store.preferences.homeSections = HomeSection.allCases
                    store.preferences.hiddenHomeSections = [.devices]
                    store.preferences.homeQuotaSelection = nil
                    store.preferences.showHomeDeviceUsageBars = false
                    store.preferences.menuBarTokens = false
                    store.preferences.menuBarShortQuota = false
                    store.preferences.menuBarWeeklyQuota = true
                    store.preferences.menuBarStyle = .rings
                }
            }
        }.formStyle(.grouped)
    }
}
struct HomeQuotaSettings: View {
    @Bindable var store: AppStore
    var body: some View {
        Group {
            Toggle(L10n.text("自定义首页额度"), isOn: Binding(
                get: { store.preferences.homeQuotaSelection != nil },
                set: { enabled in
                    store.preferences.homeQuotaSelection = enabled
                        ? QuotaSelection.effectiveIDs(selection: [], choices: store.quotaChoices) : nil
                    store.savePreferences()
                }
            )).disabled(store.quotaChoices.isEmpty)
            if store.quotaChoices.isEmpty {
                Text(L10n.text("暂无可用额度数据")).font(.caption).foregroundStyle(.secondary)
            } else if store.preferences.homeQuotaSelection != nil {
                let selected = store.homeQuotaIDs
                ForEach(store.quotaChoices) { choice in
                    Toggle(choice.title, isOn: Binding(
                        get: { selected.contains(choice.id) },
                        set: { enabled in
                            var next = store.homeQuotaIDs
                            if enabled { next.insert(choice.id) }
                            else if next.count > 1 { next.remove(choice.id) }
                            store.preferences.homeQuotaSelection = next
                            store.savePreferences()
                        }
                    )).disabled(selected.count == 1 && selected.contains(choice.id))
                }
            }
        }
    }
}

// Track the mouse in window coordinates: Form rows can be rebuilt while reordering.
// Keeping the native mouse session avoids losing a SwiftUI drop target in that rebuild.
@MainActor
private final class HomeDragHandles {
    private struct Entry { weak var view: HomeDragHandleView? }
    private var entries: [HomeSection: Entry] = [:]
    func register(_ view: HomeDragHandleView, section: HomeSection) {
        entries[section] = Entry(view: view)
    }
    func destination(at point: NSPoint, in window: NSWindow) -> HomeSection? {
        entries.compactMap { section, entry -> (HomeSection, CGFloat)? in
            guard let view = entry.view, view.window === window else { return nil }
            let center = view.convert(NSPoint(x: view.bounds.midX, y: view.bounds.midY), to: nil)
            return (section, abs(center.y - point.y))
        }.min { $0.1 < $1.1 }?.0
    }
}
private struct HomeDragHandle: NSViewRepresentable {
    let section: HomeSection
    let handles: HomeDragHandles
    let move: (HomeSection) -> Void
    let finish: () -> Void
    let step: (Int) -> Void
    func makeNSView(context: Context) -> HomeDragHandleView { HomeDragHandleView() }
    func updateNSView(_ view: HomeDragHandleView, context: Context) {
        handles.register(view, section: section)
        view.move = { point, window in
            if let destination = handles.destination(at: point, in: window) { move(destination) }
        }
        view.finish = finish
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.button)
        view.setAccessibilityLabel(L10n.text("调整%@顺序", String(describing: section.title)))
        view.setAccessibilityCustomActions([
            NSAccessibilityCustomAction(name: L10n.text("上移"), handler: { step(-1); return true }),
            NSAccessibilityCustomAction(name: L10n.text("下移"), handler: { step(1); return true })
        ])
    }
}
private final class HomeDragHandleView: NSView {
    var move: ((NSPoint, NSWindow) -> Void)?
    var finish: (() -> Void)?
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
    override func draw(_ dirtyRect: NSRect) {
        let symbol = NSImage(systemSymbolName: "line.3.horizontal", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 12, weight: .regular))?
            .withSymbolConfiguration(.init(paletteColors: [.secondaryLabelColor]))
        symbol?.draw(in: NSRect(x: (bounds.width - 14) / 2, y: (bounds.height - 12) / 2, width: 14, height: 12))
    }
    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        let move = move, finish = finish
        let start = event.locationInWindow
        var moved = false
        NSCursor.closedHand.push()
        defer { NSCursor.pop(); if moved { finish?() } }
        while let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            if next.type == .leftMouseUp { break }
            if !moved && hypot(next.locationInWindow.x - start.x, next.locationInWindow.y - start.y) < 3 { continue }
            moved = true
            move?(next.locationInWindow, window)
            // Make row positions current before processing another drag event.
            window.contentView?.layoutSubtreeIfNeeded()
        }
    }
}
struct ActivityDetailView: View {
    var store: AppStore
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(L10n.text("热力图")).font(.subheadline.weight(.semibold))
            ActivityView(store: store, showHeading: false)
            Text(L10n.text("趋势")).font(.subheadline.weight(.semibold))
            UsageChart(points: store.trendPoints(), granularity: store.trendGranularity, tint: store.preferences.accentColor,
                       animationMemory: store.detailTrendAnimation)
                .id("activity-detail-trend-chart")
            HistoryNotice(store: store)
            ActivityRecordsView(store: store)
        }
    }
}
