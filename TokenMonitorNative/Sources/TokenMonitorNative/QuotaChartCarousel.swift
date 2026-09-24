import SwiftUI
import MonitorCore

enum QuotaChartPage: Int, CaseIterable {
    case overview, devices, models
    func advanced(by offset: Int) -> Self {
        let count = Self.allCases.count
        return Self(rawValue: ((rawValue + offset) % count + count) % count)!
    }
    func title(tokens: Bool) -> String {
        switch self {
        case .overview: return L10n.text("额度概览")
        case .devices: return L10n.text(tokens ? "设备 Token" : "设备额度分摊")
        case .models: return L10n.text(tokens ? "模型 Token" : "模型额度分摊")
        }
    }
}

enum QuotaChartData {
    static func allocation(remaining: Double?, rows: [ConversionSnapshot.Row], kind: String = "device") -> Distribution {
        guard let remaining, remaining.isFinite, (0...100).contains(remaining),
              !rows.isEmpty, rows.allSatisfy({ $0.quota?.isFinite == true && ($0.quota ?? -1) >= 0 }) else { return Distribution([]) }
        let used = 100 - remaining
        let items = rows.compactMap { row -> DistributionItem? in
            guard let amount = row.quota, amount.isFinite, amount > 0 else { return nil }
            return .init(id: kind + ":" + row.id, name: row.id, value: amount)
        }
        let attributed = items.reduce(0) { $0 + $1.value }
        guard attributed.isFinite, attributed <= used + 0.000001 else { return Distribution([]) }
        var slices = items
        let unassigned = max(0, used - attributed)
        if unassigned > 0.000001 {
            slices.append(.init(id: "quota:used", name: L10n.text("未分摊额度"), value: unassigned))
        }
        return Distribution(slices, limit: slices.count)
    }

    static func allocationLegend(_ distribution: Distribution, kind: String = "device") -> [DistributionItem] {
        Array(distribution.items.filter { $0.id.hasPrefix(kind + ":") }.prefix(3))
            + distribution.items.filter { $0.id == "quota:used" }
    }

    static func tokens(rows: [ConversionSnapshot.Row], kind: String) -> Distribution {
        Distribution.compactActivity(rows.compactMap { row in
            guard row.tokens.isFinite, row.tokens > 0 else { return nil }
            return .init(id: kind + ":" + row.id, name: row.id, value: row.tokens)
        }, otherID: "aggregate:other:" + kind)
    }
}

struct QuotaChartCarousel: View {
    let result: ConversionSnapshot.Result
    let style: ChartStyle
    var tint: Color? = nil
    var historicalCycle = false
    var openDetail: () -> Void = {}
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var forward = true
    @State private var page = QuotaChartPage.overview
    @State private var deviceTokens = false
    @State private var modelTokens = false

    private var attributionAvailable: Bool {
        result.attributionAvailable == true && result.mode == "currentWindow"
            || result.approximation?.attributionAvailable == true
    }
    private var deviceRows: [ConversionSnapshot.Row] {
        guard attributionAvailable else { return [] }
        return result.attributionAvailable == true && result.mode == "currentWindow"
            ? result.devices : result.approximation?.devices ?? []
    }
    private var modelRows: [ConversionSnapshot.Row] {
        guard attributionAvailable else { return [] }
        return result.attributionAvailable == true && result.mode == "currentWindow"
            ? result.models : result.approximation?.models ?? []
    }
    var body: some View {
        VStack(spacing: 8) {
            HStack {
            Text(page.title(tokens: page == .devices ? deviceTokens : modelTokens)
                 + (historicalCycle && page != .overview && !(page == .devices ? deviceTokens : modelTokens) ? " ≈" : ""))
                .font(.caption).foregroundStyle(.secondary).lineLimit(1).frame(height: 18)
                .help(historicalCycle ? L10n.text("历史设备与模型按周期内完整日费用估算") : "")
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
            QuotaRingView(percent: result.range?.remaining, style: style, fixedLegendHeight: 88, cycleMotion: true)
        } else {
            let isDevice = page == .devices
            let rows = isDevice ? deviceRows : modelRows
            let kind = isDevice ? "device" : "model"
            let tokens = isDevice ? deviceTokens : modelTokens
            let distribution = tokens ? QuotaChartData.tokens(rows: rows, kind: kind)
                                      : QuotaChartData.allocation(remaining: result.range?.remaining, rows: rows, kind: kind)
            DistributionChart(distribution: distribution, quota: !tokens,
                              center: tokens ? nil : result.range?.used.map { $0.formatted(.number.precision(.fractionLength(0...1))) + "%" } ?? "—",
                              centerMetric: tokens ? nil : result.range?.used,
                              centerLabel: tokens ? L10n.text("tokens") : L10n.text("已用额度"), style: style,
                              legendItems: tokens ? nil : QuotaChartData.allocationLegend(distribution, kind: kind),
                              fixedLegendHeight: 88, compactValues: tokens, cycleMotion: true,
                              onRingClick: {
                                  withAnimation(reduceMotion ? nil : DataMotion.cycleAnimation) {
                                      if isDevice { deviceTokens.toggle() } else { modelTokens.toggle() }
                                  }
                              })
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
