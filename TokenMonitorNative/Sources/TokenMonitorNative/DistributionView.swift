import AppKit
import SwiftUI
import MonitorCore

struct DistributionChart: View {
    let distribution: Distribution
    var cost = false
    var quota = false
    var center: String? = nil
    var tint: Color? = nil
    var style = ChartStyle()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private func value(_ amount: Double) -> String {
        quota ? amount.formatted(.number.precision(.fractionLength(0...1))) + "%" : cost ? DisplayFormat.cost(amount) : DisplayFormat.tokens(amount) + " tokens"
    }
    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                DonutCanvas(distribution: distribution, cost: cost, quota: quota, style: style)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(quota ? L10n.text("额度") : cost ? L10n.text("API 等价估算") : L10n.text("Token 用量"))
                    .accessibilityChartDescriptor(DistributionAccessibility(distribution: distribution, cost: cost, quota: quota))
                VStack(spacing: 4) {
                    Text(center ?? (distribution.items.isEmpty ? "—" : value(distribution.total))).font(.headline).monospacedDigit().lineLimit(2).minimumScaleFactor(0.7)
                        .contentTransition(.numericText(value: distribution.total))
                        .animation(reduceMotion ? nil : DataMotion.animation, value: distribution.total)
                        .clipped()
                    if quota || cost { Text(quota ? L10n.text("剩余额度") : L10n.text("API 等价估算")).font(.caption).foregroundStyle(.secondary) }
                }.multilineTextAlignment(.center).frame(width: 108, alignment: .center).allowsHitTesting(false).accessibilityHidden(true)
            }.frame(width: 184, height: 184)
            if distribution.items.isEmpty { Text(L10n.text("无数据")).font(.caption).foregroundStyle(.secondary) }
            ForEach(distribution.items) { item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Circle().fill(Color(nsColor: NSColor(style.color(id: item.id, activeIDs: distribution.items.map(\.id)))))
                        .frame(width: 7, height: 7).accessibilityHidden(true)
                    Text(item.name).lineLimit(2)
                    Spacer(minLength: 4)
                    Text(value(item.value)).monospacedDigit()
                    if !quota { Text(distribution.fraction(item).formatted(.percent.precision(.fractionLength(0...1)))).foregroundStyle(.secondary).monospacedDigit() }
                }.font(.caption).accessibilityElement(children: .combine)
            }
        }.frame(maxWidth: .infinity)
    }
}

struct DistributionAccessibility: AXChartDescriptorRepresentable {
    let distribution: Distribution
    let cost: Bool
    let quota: Bool
    func makeChartDescriptor() -> AXChartDescriptor {
        let items = distribution.items
        let x = AXNumericDataAxisDescriptor(title: L10n.text("分项"), range: 0...Double(max(1, items.count - 1)), gridlinePositions: []) { n in
            let index = Int(n); return items.indices.contains(index) ? items[index].name : ""
        }
        let title = quota ? L10n.text("额度") : cost ? L10n.text("API 等价估算") : L10n.text("Token 用量")
        let y = AXNumericDataAxisDescriptor(title: title, range: 0...max(1, distribution.total), gridlinePositions: []) { n in
            quota ? n.formatted() + "%" : cost ? DisplayFormat.cost(n) : DisplayFormat.tokens(n)
        }
        return AXChartDescriptor(title: title, summary: nil, xAxis: x, yAxis: y,
            series: [AXDataSeriesDescriptor(name: title, isContinuous: false, dataPoints: items.enumerated().map {
                AXDataPoint(x: Double($0.offset), y: $0.element.value, label: $0.element.name)
            })])
    }
    func updateChartDescriptor(_ descriptor: AXChartDescriptor) {
        let next = makeChartDescriptor(); descriptor.title = next.title
        descriptor.xAxis = next.xAxis; descriptor.yAxis = next.yAxis; descriptor.series = next.series
    }
}

enum DonutGeometry {
    static func paths(_ distribution: Distribution, size: NSSize) -> [CGPath] {
        paths(distribution.items.map { distribution.fraction($0) }, size: size)
    }
    static func paths(_ fractions: [Double], size: NSSize) -> [CGPath] {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let outer = min(size.width, size.height) / 2 - 9, inner = outer * 0.68
        var angle = -Double.pi / 2
        let positive = fractions.filter { $0 > 0 }.count
        let total = fractions.reduce(0, +)
        return fractions.map { value in
            let sweep = (total > 0 ? value / total : 0) * 2 * Double.pi
            defer { angle += sweep }
            let path = CGMutablePath()
            guard sweep > 0, outer > 0 else { return path }
            let multiple = positive > 1
            let gap = multiple ? min(3 / outer, sweep / 5) : 0
            let start = angle + gap / 2, end = angle + sweep - gap / 2
            // Small rounded corners and a narrow gap follow Apple's Swift Charts style.
            // The exact same path is used to fill, outline and hit-test each sector.
            let radius = multiple ? min(4, (outer - inner) / 2, inner * sin(min(.pi / 2, (end - start) / 2)) * 0.4) : 0
            if radius > 0.000001 {
                let outerOffset = asin(radius / (outer - radius))
                let innerOffset = asin(radius / (inner + radius))
                func polar(_ distance: Double, _ angle: Double) -> CGPoint {
                    CGPoint(x: center.x + distance * cos(angle), y: center.y + distance * sin(angle))
                }
                path.addArc(center: center, radius: outer, startAngle: start + outerOffset, endAngle: end - outerOffset, clockwise: false)
                path.addArc(center: polar(outer - radius, end - outerOffset), radius: radius,
                            startAngle: end - outerOffset, endAngle: end + .pi / 2, clockwise: false)
                path.addLine(to: polar(sqrt(pow(inner + radius, 2) - radius * radius), end))
                path.addArc(center: polar(inner + radius, end - innerOffset), radius: radius,
                            startAngle: end + .pi / 2, endAngle: end - innerOffset + .pi, clockwise: false)
                path.addArc(center: center, radius: inner, startAngle: end - innerOffset, endAngle: start + innerOffset, clockwise: true)
                path.addArc(center: polar(inner + radius, start + innerOffset), radius: radius,
                            startAngle: start + innerOffset + .pi, endAngle: start + 1.5 * .pi, clockwise: false)
                path.addLine(to: polar(sqrt(pow(outer - radius, 2) - radius * radius), start))
                path.addArc(center: polar(outer - radius, start + outerOffset), radius: radius,
                            startAngle: start - .pi / 2, endAngle: start + outerOffset, clockwise: false)
            } else {
                path.addArc(center: center, radius: outer, startAngle: start, endAngle: end, clockwise: false)
                path.addArc(center: center, radius: inner, startAngle: end, endAngle: start, clockwise: true)
            }
            path.closeSubpath(); return path
        }
    }
    @MainActor private static var paletteAssignments: [String: Int] = [:]
    @MainActor static func color(_ id: String, quota: Bool, accent: NSColor) -> NSColor {
        if id == "aggregate:other" || id == "quota:used" { return .tertiaryLabelColor }
        if quota { return accent }
        let palette: [NSColor] = [.systemBlue, .systemOrange, .systemPurple, .systemTeal, .systemPink, .systemGreen, .systemIndigo, .systemBrown]
        let hash = id.utf8.reduce(UInt64(5381)) { ($0 &* 33) &+ UInt64($1) }
        if let assigned = paletteAssignments[id] { return palette[assigned] }
        if paletteAssignments.count >= 512 { paletteAssignments.removeAll(keepingCapacity: true) }
        let scope = id.split(separator: ":").first.map(String.init) ?? ""
        let used = Set(paletteAssignments.filter { $0.key.hasPrefix(scope + ":") }.values)
        let start = Int(hash % UInt64(palette.count))
        let chosen = (0..<palette.count).map { (start + $0) % palette.count }.first { !used.contains($0) } ?? start
        paletteAssignments[id] = chosen
        return palette[chosen]
    }
}

struct DonutTransitionState {
    let items: [DistributionItem]
    let start: [Double]
    let end: [Double]
}
enum DonutTransition {
    static func state(currentItems: [DistributionItem], currentFractions: [Double], target: Distribution) -> DonutTransitionState {
        let current = Dictionary(uniqueKeysWithValues: zip(currentItems.map(\.id), currentFractions))
        let targetFractions = Dictionary(uniqueKeysWithValues: target.items.map { ($0.id, target.fraction($0)) })
        let currentIDs = Set(currentItems.map(\.id))
        let targetItems = Dictionary(uniqueKeysWithValues: target.items.map { ($0.id, $0) })
        let items = currentItems.map { targetItems[$0.id] ?? $0 } + target.items.filter { !currentIDs.contains($0.id) }
        return DonutTransitionState(items: items,
                                    start: items.map { current[$0.id] ?? 0 },
                                    end: items.map { targetFractions[$0.id] ?? 0 })
    }
    static func interpolate(_ state: DonutTransitionState, progress: Double) -> [Double] {
        let t = min(1, max(0, progress))
        return zip(state.start, state.end).map { pair in pair.0 + (pair.1 - pair.0) * t }
    }
}

private struct DonutCanvas: NSViewRepresentable {
    let distribution: Distribution
    let cost: Bool
    let quota: Bool
    let style: ChartStyle
    func makeNSView(context: Context) -> DonutNativeView { DonutNativeView() }
    func updateNSView(_ view: DonutNativeView, context: Context) {
        view.configure(distribution, cost: cost, quota: quota, style: style)
    }
}

final class DonutNativeView: NSView {
    private var distribution = Distribution([])
    private var renderItems: [DistributionItem] = []
    private var renderFractions: [Double] = []
    private var cost = false
    private var quota = false
    private var style = ChartStyle()
    private var accent = NSColor.secondaryLabelColor
    private var paths: [CGPath] = []
    private var geometrySize = NSSize.zero
    private var monitor: Any?
    private var observers: [NSObjectProtocol] = []
    private var selected: Int?
    private var tooltip: ChartTooltipView?
    private var dataAnimation: Timer?
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override init(frame: NSRect) {
        super.init(frame: frame); wantsLayer = true
        for name in [NSView.boundsDidChangeNotification, NSWindow.didResignKeyNotification, NSWindow.willCloseNotification, NSWindow.didMoveNotification, NSWindow.didResizeNotification, NSApplication.didResignActiveNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.clear() }
            })
        }
    }
    required init?(coder: NSCoder) { fatalError() }
    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
        dataAnimation?.invalidate()
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
    }
    func configure(_ value: Distribution, cost: Bool, quota: Bool, style: ChartStyle) {
        guard distribution != value || self.cost != cost || self.quota != quota || self.style != style else { return }
        let dataChanged = distribution != value
        distribution = value; self.cost = cost; self.quota = quota; self.style = style
        paths = []; clear(); hoverAnimation?.invalidate(); hoverAnimation = nil; scales = [:]
        if dataChanged { transition(to: value) }
        else { needsDisplay = true }
    }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        clear()
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
        super.viewWillMove(toWindow: newWindow)
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }; window.acceptsMouseMovedEvents = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown, .rightMouseDown, .scrollWheel, .leftMouseDragged, .mouseExited]) { [weak self] event in
            guard let self else { return event }
            if event.window === self.window && event.type == .mouseMoved { self.show(at: self.convert(event.locationInWindow, from: nil)) }
            else { self.clear() }
            return event
        }
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); clear(); needsDisplay = true }
    private func preparePaths() {
        if geometrySize != bounds.size || paths.count != renderItems.count {
            geometrySize = bounds.size; paths = DonutGeometry.paths(renderFractions, size: bounds.size)
        }
    }
    private var hoverAnimation: Timer?
    private var scales: [Int: CGFloat] = [:]
    private func setRender(_ value: Distribution) {
        renderItems = value.items; renderFractions = value.items.map { value.fraction($0) }
        paths = []; needsDisplay = true
    }
    private func transition(to value: Distribution) {
        dataAnimation?.invalidate(); dataAnimation = nil
        guard !renderItems.isEmpty, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { setRender(value); return }
        let state = DonutTransition.state(currentItems: renderItems, currentFractions: renderFractions, target: value)
        renderItems = state.items; renderFractions = state.start; paths = []
        let started = Date()
        dataAnimation = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self else { timer.invalidate(); return }
                let raw = min(1, Date().timeIntervalSince(started) / DataMotion.duration)
                let eased = DataMotion.progress(raw)
                self.renderFractions = DonutTransition.interpolate(state, progress: eased)
                self.paths = []; self.needsDisplay = true
                if raw == 1 {
                    timer.invalidate(); self.dataAnimation = nil
                    let target = Dictionary(uniqueKeysWithValues: value.items.map { ($0.id, $0) })
                    self.renderItems = state.items.compactMap { target[$0.id] }
                    self.renderFractions = self.renderItems.map { value.fraction($0) }
                    self.paths = []; self.needsDisplay = true
                }
            }
        }
    }
    private func enlargedPath(_ index: Int) -> CGPath {
        guard paths.indices.contains(index) else { return CGMutablePath() }
        let scale = scales[index] ?? (selected == index ? 1.06 : 1)
        var transform = CGAffineTransform(translationX: bounds.midX, y: bounds.midY)
            .scaledBy(x: scale, y: scale).translatedBy(x: -bounds.midX, y: -bounds.midY)
        return paths[index].copy(using: &transform) ?? paths[index]
    }
    private func setSelection(_ index: Int?) {
        guard selected != index else { return }
        selected = index; hoverAnimation?.invalidate()
        let starting = scales, start = Date()
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            scales = index.map { [$0: 1.06] } ?? [:]; needsDisplay = true; return
        }
        hoverAnimation = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self else { timer.invalidate(); return }
                let t = min(1, Date().timeIntervalSince(start) / 0.12)
                let eased = t * t * (3 - 2 * t)
                for i in self.paths.indices {
                    let from = starting[i] ?? 1, to = self.selected == i ? 1.06 : 1
                    self.scales[i] = from + (to - from) * eased
                }
                self.needsDisplay = true
                if t == 1 { timer.invalidate(); self.hoverAnimation = nil }
            }
        }
    }
    func clear() { setSelection(nil); tooltip?.removeFromSuperview(); needsDisplay = true }
    func show(at point: NSPoint) {
        guard !isHiddenOrHasHiddenAncestor, bounds.contains(point), let window,
              dataAnimation == nil, !ChartInteractionShield.blocks(point, from: self) else { clear(); return }
        var ancestor = superview
        while let view = ancestor {
            if view is NSClipView && !view.bounds.contains(view.convert(point, from: self)) { clear(); return }
            ancestor = view.superview
        }
        preparePaths()
        guard let index = selected.flatMap({ i in enlargedPath(i).contains(point) ? i : nil }) ?? paths.firstIndex(where: { $0.contains(point) }), let container = window.contentView?.superview else { clear(); return }
        setSelection(index); needsDisplay = true
        let item = renderItems[index]
        accent = NSColor(style.color(id: item.id, activeIDs: renderItems.map(\.id)))
        let amount = quota ? item.value.formatted(.number.precision(.fractionLength(0...1))) + "%" : cost ? DisplayFormat.cost(item.value) : DisplayFormat.tokens(item.value) + " tokens"
        let tip = tooltip ?? ChartTooltipView(frame: .zero); tooltip = tip
        let size = tip.configure(value: item.name, detail: amount + (quota ? "" : " " + distribution.fraction(item).formatted(.percent.precision(.fractionLength(0...1)))), accent: accent)
        let cell = window.convertToScreen(convert(bounds, to: nil))
        let frame = HeatmapHitTesting.tooltipFrame(pointer: NSPoint(x: cell.midX, y: cell.maxY - 10), cell: cell, size: size,
                                                   bounds: window.frame.intersection(window.screen?.visibleFrame ?? window.frame))
        tip.frame = container.convert(window.convertFromScreen(frame), from: nil)
        if tip.superview !== container { container.addSubview(tip, positioned: .above, relativeTo: nil) }
    }
    override func draw(_ dirtyRect: NSRect) {
        preparePaths()
        if renderFractions.allSatisfy({ $0 <= 0 }) {
            let rect = bounds.insetBy(dx: 22.5, dy: 22.5)
            let ring = NSBezierPath(ovalIn: rect); ring.lineWidth = 27
            NSColor.quaternaryLabelColor.setStroke(); ring.stroke()
        }
        for index in paths.indices.sorted(by: { ($0 == selected ? 1 : 0) < ($1 == selected ? 1 : 0) }) {
            let shape = NSBezierPath(cgPath: enlargedPath(index))
            NSColor(style.color(id: renderItems[index].id, activeIDs: renderItems.map(\.id))).setFill(); shape.fill()
            if NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast {
                NSGraphicsContext.saveGraphicsState(); shape.addClip()
                NSColor.labelColor.setStroke()
                shape.lineWidth = 2; shape.stroke(); NSGraphicsContext.restoreGraphicsState()
            }
        }
    }
}

extension NSColor {
    convenience init(_ rgb: MonitorCore.RGBColor) { self.init(srgbRed: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1) }
}
