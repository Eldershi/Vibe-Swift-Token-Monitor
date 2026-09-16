import AppKit
import SwiftUI
import MonitorCore

struct MenuQuotaMetric: Equatable {
    let label: String
    let percent: Double?
    var text: String { label + " " + (percent.map { $0.formatted(.number.precision(.fractionLength(0))) + "%" } ?? "—") }
}
extension AppStore {
    var menuQuotaMetrics: [MenuQuotaMetric] {
        let provider = menuQuotaReportIndex.map { quotaReports[$0] }
        return [false, true].compactMap { weekly in
            guard weekly ? preferences.menuBarWeeklyQuota : preferences.menuBarShortQuota else { return nil }
            let window = provider.flatMap { QuotaPresentation.regularWindow($0, weekly: weekly) }
            let percent = window.flatMap { window in provider.flatMap { QuotaPresentation.percent(window, provider: $0, now: statusClock, threshold: quotaThreshold) } }
            return MenuQuotaMetric(label: QuotaPresentation.shortLabel(window, weekly: weekly), percent: percent)
        }
    }
}

struct MenuBarMetricsLabel: View {
    var store: AppStore
    @State private var images = MenuBarImageCache()
    var body: some View {
        let metrics = store.menuQuotaMetrics
        let tokens = store.preferences.menuBarTokens ? DisplayFormat.compact(store.todayTokens) : nil
        let beta = ""
        let description = ([tokens.map { L10n.text("Token Monitor，今日 %@ tokens", $0) }].compactMap { $0 }
            + metrics.map { L10n.text("%@，剩余额度", $0.text) }).joined(separator: "，")
        if store.preferences.menuBarStyle == .rings && !metrics.isEmpty {
            Image(nsImage: images.image(tokens: tokens, metrics: metrics, suffix: beta))
                .accessibilityLabel(description)
        } else {
            let text = ([tokens].compactMap { $0 } + metrics.map(\.text)).joined(separator: " ")
            Label(text.isEmpty ? "" : text + beta, systemImage: "chart.bar.xaxis")
                .accessibilityLabel(description.isEmpty ? "Token Monitor" : description)
        }
    }
}

@MainActor final class MenuBarImageCache {
    private var lastKey = ""
    private var lastImage: NSImage?
    func image(tokens: String?, metrics: [MenuQuotaMetric], suffix: String) -> NSImage {
        let key = ([tokens ?? "", suffix] + metrics.map { $0.text + String(describing: $0.percent) }).joined(separator: "|")
        if key == lastKey, let lastImage { return lastImage }
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular), .foregroundColor: NSColor.black]
        func width(_ text: String) -> CGFloat { ceil((text as NSString).size(withAttributes: attributes).width) }
        let totalWidth = (tokens.map { width($0) + 9 } ?? 0) + metrics.reduce(CGFloat(0)) { $0 + 21 + width($1.text) + 9 } - (metrics.isEmpty ? 0 : 9) + width(suffix)
        let image = NSImage(size: NSSize(width: max(1, totalWidth), height: 18), flipped: false) { rect in
            var x: CGFloat = 0
            func drawText(_ text: String) {
                (text as NSString).draw(at: NSPoint(x: x, y: 1), withAttributes: attributes); x += ceil((text as NSString).size(withAttributes: attributes).width)
            }
            if let tokens { drawText(tokens); x += 9 }
            for metric in metrics {
                let center = NSPoint(x: x + 8, y: rect.midY)
                let base = NSBezierPath(ovalIn: NSRect(x: x + 1, y: center.y - 7, width: 14, height: 14))
                NSColor.black.withAlphaComponent(0.25).setStroke(); base.lineWidth = 2; base.stroke()
                if let percent = metric.percent, percent > 0 {
                    let arc = NSBezierPath()
                    arc.appendArc(withCenter: center, radius: 7, startAngle: 90, endAngle: 90 - 360 * percent / 100, clockwise: true)
                    NSColor.black.setStroke(); arc.lineWidth = 2; arc.stroke()
                }
                x += 21; drawText(metric.text); x += 9
            }
            drawText(suffix)
            return true
        }
        image.isTemplate = true
        lastKey = key; lastImage = image; return image
    }
}

struct MenuBarSettings: View {
    @Bindable var store: AppStore
    var body: some View {
        Toggle(L10n.text("显示今日 Token"), isOn: $store.preferences.menuBarTokens)
        Toggle(L10n.text("显示短周期剩余额度"), isOn: $store.preferences.menuBarShortQuota)
        Toggle(L10n.text("显示每周剩余额度"), isOn: $store.preferences.menuBarWeeklyQuota)
        Picker(L10n.text("菜单栏样式"), selection: $store.preferences.menuBarStyle) {
            Text(L10n.text("紧凑文字")).tag(MenuBarStyle.text)
            Text(L10n.text("小圆环与百分比")).tag(MenuBarStyle.rings)
        }
        if !store.quotaReports.isEmpty {
            Picker(L10n.text("菜单栏额度来源"), selection: Binding(get: { store.menuQuotaSelection?.source == store.preferences.hubAddress ? store.menuQuotaSelection?.index ?? -1 : -1 }, set: { store.selectMenuQuotaReport($0) })) {
                Text(L10n.text("自动选择")).tag(-1)
                ForEach(Array(store.quotaReports.indices), id: \.self) { index in Text(store.quotaReportTitle(index)).tag(index) }
            }
        }
    }
}
