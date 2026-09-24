import SwiftUI
import MonitorCore

/// Keep row identity across quota/token and cycle changes so position, value and
/// bar length interpolate from the visible row instead of replacing the list.
struct QuotaSummaryRows: View {
    let distribution: Distribution
    let quota: Bool
    var hasSourceRows = true
    var tint: Color? = nil
    var toggleMetric: () -> Void = {}
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Target: Equatable {
        let distribution: Distribution
        let quota: Bool
    }
    private var action: String { L10n.text(quota ? "切换为 Token 用量" : "切换为额度百分比") }
    private var rowTransition: AnyTransition {
        guard !reduceMotion else { return .identity }
        return .asymmetric(
            insertion: .opacity.combined(with: .offset(y: 6))
                .animation(.easeOut(duration: 0.20).delay(0.16)),
            removal: .opacity.animation(.easeOut(duration: 0.12)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if distribution.items.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.text("暂无可换算的匹配数据")).font(.caption).foregroundStyle(.secondary)
                    if hasSourceRows { metricButton(fraction: 0, name: "") }
                }.transition(rowTransition)
            }
            ForEach(distribution.items) { item in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 2) {
                        Text(item.name).lineLimit(1).truncationMode(.middle)
                            .minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(quota ? item.value.formatted(.number.precision(.fractionLength(0...1))) + "%" : DisplayFormat.compact(item.value))
                            .monospacedDigit().lineLimit(1)
                            .contentTransition(.numericText(value: item.value))
                            .frame(width: 44, alignment: .trailing)
                            .clipped()
                    }.font(.caption)
                    metricButton(fraction: quota ? item.value / 100 : distribution.fraction(item), name: item.name)
                }
                .transition(rowTransition)
            }
        }
        .animation(reduceMotion ? nil : DataMotion.summaryAnimation,
                   value: Target(distribution: distribution, quota: quota))
    }

    private func metricButton(fraction: Double, name: String) -> some View {
        Button(action: toggleMetric) {
            ThinProgress(value: fraction, motion: DataMotion.summaryAnimation)
                .tint(tint)
                .frame(height: 12)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(action)
        .accessibilityLabel(name.isEmpty ? action : name + ", " + action)
    }
}
