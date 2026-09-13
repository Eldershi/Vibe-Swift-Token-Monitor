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
    var page: Page {
        switch self {
        case .usage: .usage
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
struct HomeLayoutSettings: View {
    @Bindable var store: AppStore
    @State private var dragHandles = HomeDragHandles()
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
                        HomeDragHandle(section: section, handles: dragHandles, move: { destination in
                            store.preferences.moveHomeSection(section, to: destination)
                        }, finish: { store.savePreferences() }, step: { offset in
                            store.preferences.moveHomeSection(section, by: offset)
                            store.savePreferences()
                        })
                            .frame(width: 28, height: 28)
                            .help("拖动以调整\(section.title)的位置")
                            .accessibilityAction(named: "上移") { store.preferences.moveHomeSection(section, by: -1); store.savePreferences() }
                            .accessibilityAction(named: "下移") { store.preferences.moveHomeSection(section, by: 1); store.savePreferences() }
                    }
                    .contentShape(Rectangle())
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
        view.setAccessibilityLabel("调整\(section.title)顺序")
        view.setAccessibilityCustomActions([
            NSAccessibilityCustomAction(name: "上移", handler: { step(-1); return true }),
            NSAccessibilityCustomAction(name: "下移", handler: { step(1); return true })
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
struct UsageDetailView: View {
    var store: AppStore
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SummaryView(store: store, compact: true)
            SectionSeparator()
            LabeledContent("缓存读取", value: DisplayFormat.tokens(store.usage?.cache(tool: store.preferences.tool)))
            LabeledContent("输出 Token", value: DisplayFormat.tokens(store.usage?.output(tool: store.preferences.tool)))
            Text("设备分项").font(.headline)
            ForEach(store.devices) { DeviceRow(device: $0, store: store, compact: true) }
        }.textSelection(.enabled)
    }
}
struct ActivityDetailView: View {
    var store: AppStore
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ActivityView(store: store, showHeading: false)
            HistoryNotice(store: store)
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
