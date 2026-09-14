import SwiftUI
import MonitorCore

struct ActivityRecordsView: View {
    @Bindable var store: AppStore
    var body: some View {
        let years = ActivityRecords.years(points: store.historyPoints(), now: store.historyDay)
        let scope = ActivityExpansion.Scope(source: store.preferences.hubAddress, tool: store.preferences.tool)
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.text("用量明细")).font(.subheadline.weight(.semibold))
            if years.isEmpty {
                Text(L10n.text("此范围尚无历史数据")).font(.caption).foregroundStyle(.secondary)
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
                                    .contentShape(Rectangle()).onTapGesture { let binding = expansion(.month(month.id), scope: scope, years: years); binding.wrappedValue.toggle() }
                            }.padding(.leading, 12)
                        }
                    }
                } label: {
                    summary(year.id.formatted(.dateTime.year()), total: year.total, partial: year.isPartial)
                        .contentShape(Rectangle()).onTapGesture { let binding = expansion(.year(year.id), scope: scope, years: years); binding.wrappedValue.toggle() }
                }
            }
        }
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
    private func summary(_ title: String, total: Double, partial: Bool) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 1) {
                Text(value(total)).monospacedDigit()
                if partial { Text(L10n.text("已记录")).font(.caption2).foregroundStyle(.secondary) }
            }
        }.font(.caption).foregroundStyle(.primary)
    }
}
