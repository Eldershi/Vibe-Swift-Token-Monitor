import SwiftUI
import MonitorCore

struct ActivityRecordsView: View {
    @Bindable var store: AppStore
    @ViewBuilder private var rangedRows: some View {
        let points = store.trendPoints().reversed()
        ForEach(Array(points)) { point in
            HStack(alignment: .firstTextBaseline) {
                Text(rowTitle(point.date))
                Spacer(minLength: 8)
                Text(value(point.tokens)).monospacedDigit()
            }
            .font(.caption).padding(.vertical, 3).textSelection(.enabled)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityTitle(point.date) + ", " + value(point.tokens))
        }
    }
    var body: some View {
        let years = ActivityRecords.years(points: store.historyPoints(), now: store.historyDay)
        let scope = ActivityExpansion.Scope(source: store.preferences.hubAddress, tool: "codex")
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.text("用量明细")).font(.subheadline.weight(.semibold))
            if store.preferences.period == .allTime {
                if years.isEmpty {
                    Text(store.trendEmptyMessage).font(.caption).foregroundStyle(.secondary)
                }
                ForEach(years) { year in
                    DisclosureGroup(isExpanded: expansion(.year(year.id), scope: scope, years: years)) {
                        if store.activityExpansion.expanded(.year(year.id), scope: scope, years: years) {
                            ForEach(year.months) { month in
                                DisclosureGroup(isExpanded: expansion(.month(month.id), scope: scope, years: years)) {
                                    if store.activityExpansion.expanded(.month(month.id), scope: scope, years: years) {
                                        ForEach(month.days) { day in
                                            HStack {
                                                Text(day.date, format: .dateTime.day())
                                                Spacer(minLength: 8)
                                                Text(value(day.tokens)).monospacedDigit()
                                            }
                                            .font(.caption).padding(.vertical, 3).padding(.leading, 24).textSelection(.enabled)
                                            .accessibilityElement(children: .ignore)
                                            .accessibilityLabel(day.date.formatted(date: .complete, time: .omitted) + ", " + value(day.tokens))
                                        }
                                    }
                                } label: {
                                    summary(month.id.formatted(.dateTime.month(.wide)), total: month.total, partial: month.isPartial)

                                }.disclosureGroupStyle(AlignedActivityDisclosureStyle()).padding(.leading, 12)
                            }
                        }
                    } label: {
                        summary(year.id.formatted(.dateTime.year()), total: year.total, partial: year.isPartial)

                    }
                }
            } else if store.trendPoints().isEmpty {
                Text(store.trendEmptyMessage).font(.caption).foregroundStyle(.secondary)
            } else {
                rangedRows
            }
        }
        .disclosureGroupStyle(AlignedActivityDisclosureStyle())
        .onChange(of: years, initial: true) { store.activityExpansion.prepare(scope: scope, years: years) }
        .onChange(of: scope) { store.activityExpansion.prepare(scope: scope, years: years) }
    }
    private func expansion(_ id: ActivityExpansion.Item, scope: ActivityExpansion.Scope, years: [ActivityYear]) -> Binding<Bool> {
        Binding(get: { store.activityExpansion.expanded(id, scope: scope, years: years) },
                set: { store.activityExpansion.set($0, id: id, scope: scope, years: years) })
    }
    private func value(_ tokens: Double?) -> String {
        tokens.map { DisplayFormat.tokens($0) + " tokens" } ?? L10n.text("无数据")
    }
    private func rowTitle(_ date: Date) -> String {
        guard store.preferences.period == .today else { return date.formatted(.dateTime.month(.abbreviated).day()) }
        let day = date.formatted(date: .numeric, time: .omitted)
        return day + " " + TrendAxisFormatting.hour(date)
    }
    private func accessibilityTitle(_ date: Date) -> String {
        store.preferences.period == .today
            ? date.formatted(date: .complete, time: .shortened)
            : date.formatted(date: .complete, time: .omitted)
    }
    private func summary(_ title: String, total: Double, partial: Bool) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                Spacer(minLength: 8)
                Text(value(total)).monospacedDigit()
            }
        }.font(.caption).foregroundStyle(.primary)
    }
}

private struct AlignedActivityDisclosureStyle: DisclosureGroupStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { configuration.isExpanded.toggle() } label: {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: configuration.isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        .frame(width: 12)
                    configuration.label
                }.contentShape(Rectangle())
            }.buttonStyle(.plain)
            .accessibilityValue(configuration.isExpanded ? L10n.text("已展开") : L10n.text("已折叠"))
            if configuration.isExpanded { configuration.content.padding(.leading, 6) }
        }
    }
}
