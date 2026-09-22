import SwiftUI
import AppKit
import MonitorCore

enum ActivityDetail: String, CaseIterable {
    case models = "模型", devices = "设备", heatmap = "热力图", trends = "趋势", history = "活动"
    var destination: ActivityDetail { self == .heatmap || self == .trends ? .history : self }
    var title: String { L10n.text(rawValue) }
    var symbol: String {
        switch self {
        case .models: "square.stack.3d.up"
        case .devices: "server.rack"
        case .heatmap: "calendar"
        case .trends: "chart.xyaxis.line"
        case .history: "waveform.path.ecg.text.clipboard"
        }
    }
}

struct CompactActivityDetailView: View {
    var store: AppStore
    var openDetail: (ActivityDetail) -> Void
    private var models: Distribution {
        Distribution.compactActivity(store.modelRows.map { row in
            DistributionItem(id: "model:" + row.name, name: row.name, value: row.tokens)
        }, otherID: "aggregate:other:model")
    }
    private var devices: Distribution {
        Distribution.compactActivity(store.devices.compactMap { device in
            guard !device.periodExpired(store.preferences.period, at: store.statusClock),
                  let amount = device.periods[store.preferences.period.rawValue]?.tokens(tool: "codex") else { return nil }
            return DistributionItem(id: "device:" + device.id, name: device.id, value: amount)
        }, otherID: "aggregate:other:device")
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            module(.models, height: 124) {
                CompactDistributionChart(distribution: models, style: store.preferences.chartStyle)
            }
            module(.devices, height: 124) {
                CompactDistributionChart(distribution: devices, style: store.preferences.chartStyle)
            }
            module(.heatmap, height: 104) { ActivityView(store: store, showHeading: false, showBorder: false) }
            module(.trends, height: 180) {
                UsageChart(points: store.trendPoints(), granularity: store.trendGranularity,
                           tint: store.preferences.accentColor, animationMemory: store.detailTrendAnimation)
                    .id("activity-detail-trend-chart")
            }
            HistoryNotice(store: store).frame(height: 24, alignment: .topLeading)
        }
    }
    private func module<Content: View>(_ detail: ActivityDetail, height: CGFloat, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button { openDetail(detail.destination) } label: { Text(detail.title).font(.subheadline.weight(.semibold)) }
                    .buttonStyle(.plain).accessibilityLabel(L10n.text("查看%@详情", detail.title))
                Spacer()
                Button { openDetail(detail.destination) } label: {
                    Image(systemName: detail.symbol).font(.body)
                        .foregroundStyle(store.preferences.accentColor ?? Color.accentColor)
                }.buttonStyle(.plain).accessibilityLabel(L10n.text("查看%@详情", detail.title))
            }.frame(height: 22)
            content().frame(height: height)
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .quaternaryLabelColor).opacity(0.35), in: RoundedRectangle(cornerRadius: 14))
    }
}

struct ActivitySecondaryView: View {
    var store: AppStore
    let detail: ActivityDetail
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            switch detail {
            case .models: ModelsView(store: store)
            case .devices:
                DistributionChart(distribution: store.deviceDistribution, style: store.preferences.chartStyle)
                if store.devices.isEmpty { Text(L10n.text("尚无设备数据")).foregroundStyle(.secondary) }
                let fractions = store.deviceUsageFractions
                ForEach(store.devices) { DeviceRow(device: $0, usageFraction: fractions[$0.id], store: store) }
            case .heatmap, .trends, .history:
                ActivityDetailView(store: store)
            }
        }
    }
}

struct CompactDistributionChart: View {
    let distribution: Distribution
    let style: ChartStyle
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        let distribution = style.named(self.distribution)
        HStack(alignment: .center, spacing: 10) {
            ZStack {
                DonutCanvas(distribution: distribution, cost: false, quota: false, style: style, strokeWidth: 6)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(L10n.text("Token 用量"))
                    .accessibilityChartDescriptor(DistributionAccessibility(distribution: distribution, cost: false, quota: false))
                Text(distribution.items.isEmpty ? "—" : DisplayFormat.compact(distribution.total))
                    .font(.system(size: 13, weight: .semibold)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.75).frame(width: 62)
                    .contentTransition(.numericText(value: distribution.total))
                    .animation(reduceMotion ? nil : DataMotion.animation, value: distribution.total)
                    .allowsHitTesting(false).accessibilityHidden(true)
            }.frame(width: 110, height: 110)
            VStack(alignment: .leading, spacing: 7) {
                if distribution.items.isEmpty {
                    Text(L10n.text("无数据")).foregroundStyle(.secondary)
                }
                ForEach(distribution.items) { item in
                    legendRow(item)
                }
            }.font(.system(size: 11))
                .frame(maxWidth: .infinity, minHeight: 124, maxHeight: 124, alignment: .bottomLeading)

        }
    }
    private func legendRow(_ item: DistributionItem) -> some View {
        let color = Color(nsColor: NSColor(style.color(id: item.id, activeIDs: distribution.items.map(\.id))))
        let percent = distribution.fraction(item).formatted(.percent.precision(.fractionLength(0...1)))
        let detail = DisplayFormat.tokens(item.value) + "  " + percent
        return HStack(alignment: .firstTextBaseline, spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6).accessibilityHidden(true)
            Text(item.name).lineLimit(1)
            Spacer(minLength: 2)
            Text(DisplayFormat.compact(item.value)).monospacedDigit().fixedSize()
        }.accessibilityElement(children: .ignore)
            .accessibilityLabel(item.name + ", " + detail)
            .help(item.name + "\n" + detail)
    }

}
