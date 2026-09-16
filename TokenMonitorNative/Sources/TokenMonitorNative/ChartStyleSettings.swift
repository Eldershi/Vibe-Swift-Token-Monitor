import SwiftUI
import AppKit
import MonitorCore

struct ChartStyleSettings: View {
    @Bindable var store: AppStore
    private func color(_ item: DistributionItem, ids: [String]) -> Binding<Color> {
        Binding(get: { Color(nsColor: NSColor(store.preferences.chartStyle.color(id: item.id, activeIDs: ids))) }, set: { value in
            guard let rgb = NSColor(value).usingColorSpace(.sRGB) else { return }
            var style = store.preferences.chartStyle
            if style.preset != "custom" { style.customColors = style.colors; style.preset = "custom" }
            var overrides = style.objectColors ?? [:]
            overrides[item.id] = RGBColor(red: rgb.redComponent, green: rgb.greenComponent, blue: rgb.blueComponent)
            style.objectColors = overrides; store.preferences.chartStyle = style
        })
    }
    @ViewBuilder private func group(_ title: String, items: [DistributionItem]) -> some View {
        let active = items.filter { $0.value > 0 }
        if !active.isEmpty {
            VStack(alignment: .leading, spacing: 9) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                ForEach(active) { item in
                    HStack(spacing: 8) {
                        ColorPicker(item.name, selection: color(item, ids: active.map(\.id)), supportsOpacity: false).labelsHidden().fixedSize()
                        Text(item.name).lineLimit(2)
                        Spacer(minLength: 0)
                    }
                }
            }
            .listRowSeparator(.hidden)
        }
    }
    var body: some View {
        Picker(L10n.text("饼图配色"), selection: Binding(get: { store.preferences.chartStyle.preset }, set: { preset in
            store.preferences.chartStyle.preset = preset
            if preset != "custom" { store.preferences.chartStyle.objectColors = nil }
        })) {
            Text(L10n.text("鲜明")).tag("vivid")
            Text(L10n.text("柔和")).tag("soft")
            Text(L10n.text("高区分度")).tag("contrast")
            Text(L10n.text("自定义")).tag("custom")
        }
        group(L10n.text("模型"), items: store.modelDistribution.items)
        group(L10n.text("设备"), items: store.deviceDistribution.items)
        if let selected = store.selectedDonutChoice(in: store.quotaDonutChoices) {
            group(L10n.text("额度"), items: [
                .init(id: "quota:used", name: L10n.text("已用额度"), value: 100 - selected.percent),
                .init(id: "quota:remaining", name: L10n.text("剩余额度"), value: selected.percent)
            ])
        }
        Button(L10n.text("恢复图表默认配色")) {
            let slots = store.preferences.chartStyle.slots
            store.preferences.chartStyle = ChartStyle(); store.preferences.chartStyle.slots = slots
        }
    }
}
