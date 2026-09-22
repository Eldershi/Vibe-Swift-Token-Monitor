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
    private func name(_ item: DistributionItem) -> Binding<String> {
        Binding(get: { store.preferences.chartStyle.objectNames?[item.id] ?? "" }, set: { value in
            var names = store.preferences.chartStyle.objectNames ?? [:]
            if value.isEmpty { names.removeValue(forKey: item.id) } else { names[item.id] = String(value.prefix(80)) }
            store.preferences.chartStyle.objectNames = names.isEmpty ? nil : names
        })
    }
    private var models: [DistributionItem] {
        let rows = store.modelRows.map { DistributionItem(id: "model:" + $0.name, name: $0.name, value: $0.tokens) }
        return rows + (rows.count > 4 ? [.init(id: "aggregate:other:model", name: L10n.text("其他"), value: 1)] : [])
    }
    private var devices: [DistributionItem] {
        let rows = store.devices.compactMap { device -> DistributionItem? in
            guard let value = device.periods["allTime"]?.tokens(tool: "codex") else { return nil }
            return .init(id: "device:" + device.id, name: device.id, value: value)
        }
        return rows + (rows.count > 3 ? [.init(id: "aggregate:other:device", name: L10n.text("其他"), value: 1)] : [])
    }
    @ViewBuilder private func group(_ title: String, items: [DistributionItem]) -> some View {
        let active = items.filter { $0.value > 0 }
        if !active.isEmpty {
            VStack(alignment: .leading, spacing: 9) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                ForEach(active) { item in
                    HStack(spacing: 8) {
                        ColorPicker(store.preferences.chartStyle.displayName(id: item.id, fallback: item.name), selection: color(item, ids: active.map(\.id)), supportsOpacity: false).labelsHidden().fixedSize()
                        TextField(item.name, text: name(item), prompt: Text(item.name))
                            .labelsHidden().textFieldStyle(.roundedBorder)
                            .accessibilityLabel(L10n.text("自定义%@名称", item.name)).help(item.name)
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
        group(L10n.text("模型"), items: models)
        group(L10n.text("设备"), items: devices)
        if let selected = store.selectedDonutChoice(in: store.quotaDonutChoices) {
            group(L10n.text("额度"), items: [
                .init(id: "quota:used", name: L10n.text("已用额度"), value: 100 - selected.percent),
                .init(id: "quota:remaining", name: L10n.text("剩余额度"), value: selected.percent)
            ])
        }
        Button(L10n.text("恢复图表默认配色")) {
            let slots = store.preferences.chartStyle.slots
            let names = store.preferences.chartStyle.objectNames
            store.preferences.chartStyle = ChartStyle(); store.preferences.chartStyle.slots = slots
            store.preferences.chartStyle.objectNames = names
        }
    }
}
