import SwiftUI
import MonitorCore

enum QuotaChartPage: Int, CaseIterable {
    case overview, allocation, tokens
    func advanced(by offset: Int) -> Self {
        let count = Self.allCases.count
        return Self(rawValue: ((rawValue + offset) % count + count) % count)!
    }
    var title: String {
        switch self {
        case .overview: return L10n.text("额度概览")
        case .allocation: return L10n.text("设备额度分摊")
        case .tokens: return L10n.text("设备 Token 总计")
        }
    }
}

enum QuotaChartData {
    static func allocation(remaining: Double?, rows: [ConversionSnapshot.Row]) -> Distribution {
        guard let remaining, remaining.isFinite, (0...100).contains(remaining) else { return Distribution([]) }
        let used = 100 - remaining
        var items = rows.compactMap { row -> DistributionItem? in
            guard let amount = row.quota, amount.isFinite, amount > 0 else { return nil }
            return .init(id: "device:" + row.id, name: row.id, value: amount)
        }
        let attributed = items.reduce(0) { $0 + $1.value }
        // Never turn inconsistent attribution into a different official remaining percentage.
        if !attributed.isFinite || attributed > used + 0.000001 { items = [] }
        let unassigned = max(0, used - items.reduce(0) { $0 + $1.value })
        if unassigned > 0.000001 {
            items.append(.init(id: "quota:used", name: L10n.text("未分摊额度"), value: unassigned))
        }
        items.append(.init(id: "quota:remaining", name: L10n.text("剩余额度"), value: remaining))
        return Distribution(items, limit: items.count)
    }

    static func allocationLegend(_ distribution: Distribution) -> [DistributionItem] {
        Array(distribution.items.filter { $0.id.hasPrefix("device:") }.prefix(3))
            + distribution.items.filter { $0.id == "quota:remaining" }
    }

    static func tokens(devices: [Device]) -> Distribution {
        Distribution.compactActivity(devices.compactMap { device in
            guard let tokens = device.periods[Period.allTime.rawValue]?.tokens(tool: "codex"),
                  tokens.isFinite, tokens > 0 else { return nil }
            return .init(id: "device:" + device.id, name: device.id, value: tokens)
        }, otherID: "aggregate:other:device")
    }

}

struct QuotaChartCarousel: View {
    let devices: [Device]
    let result: ConversionSnapshot.Result
    let style: ChartStyle
    var tint: Color? = nil
    var openDetail: () -> Void = {}
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var forward = true
    @State private var page = QuotaChartPage.overview

    private var rows: [ConversionSnapshot.Row] {
        if result.attributionAvailable == true && result.mode == "currentWindow" { return result.devices }
        return result.approximation?.attributionAvailable == true ? result.approximation?.devices ?? [] : []
    }
    var body: some View {
        VStack(spacing: 8) {
            HStack {
            Text(page.title).font(.caption).foregroundStyle(.secondary).lineLimit(1).frame(height: 18)
                .accessibilityValue("\(page.rawValue + 1) / 3")
                Spacer()
                Button(action: openDetail) { Image(systemName: "timer").foregroundStyle(tint ?? Color.accentColor) }
                    .buttonStyle(.plain).accessibilityLabel(L10n.text("查看%@详情", L10n.text("额度概览")))
            }.frame(height: 18)
            ZStack(alignment: .top) {
                chart.id(page)
                    .transition(.asymmetric(insertion: .move(edge: forward ? .trailing : .leading),
                                            removal: .move(edge: forward ? .leading : .trailing)))
            }.clipped()
        }.frame(height: 310, alignment: .top).padding(12)
            .background(Color(nsColor: .quaternaryLabelColor).opacity(0.35), in: RoundedRectangle(cornerRadius: 14))
            .overlay {
                HStack {
                    navigationButton(forward: false)
                    Spacer()
                    navigationButton(forward: true)
                }.padding(.horizontal, 12)
            }
    }
    @ViewBuilder private var chart: some View {
        if page == .overview {
            QuotaRingView(percent: result.range?.remaining, style: style, fixedLegendHeight: 88)
        } else if page == .allocation {
            let allocation = QuotaChartData.allocation(remaining: result.range?.remaining, rows: rows)
            DistributionChart(distribution: allocation,
                              quota: true, center: result.range?.remaining.map { $0.formatted(.number.precision(.fractionLength(0...1))) + "%" } ?? "—", style: style, legendItems: QuotaChartData.allocationLegend(allocation), fixedLegendHeight: 88)
        } else {
            DistributionChart(distribution: QuotaChartData.tokens(devices: devices), style: style, fixedLegendHeight: 88, compactValues: true)
        }
    }
    private func navigationButton(forward: Bool) -> some View {
        Button {
            self.forward = forward
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.28)) {
                page = page.advanced(by: forward ? 1 : -1)
            }
        } label: {
            Image(systemName: forward ? "chevron.right" : "chevron.left")
                .font(.system(size: 12, weight: .semibold)).frame(width: 10, height: 44)
        }
        .buttonStyle(.bordered).buttonBorderShape(.capsule).controlSize(.small)
        .accessibilityLabel(L10n.text(forward ? "下一张图表" : "上一张图表"))
        .help(L10n.text(forward ? "下一张图表" : "上一张图表"))
    }
}
