import AppKit
import SwiftUI
import MonitorCore

struct DistributionChart: View {
    let distribution: Distribution
    var cost = false
    var quota = false
    var center: String? = nil
    var centerMetric: Double? = nil
    var centerLabel: String? = nil
    var tint: Color? = nil
    var style = ChartStyle()
    var strokeWidth: CGFloat? = nil
    var legendItems: [DistributionItem]? = nil
    var fixedLegendHeight: CGFloat? = nil
    var compactValues = false
    var cycleMotion = false
    var onRingClick: (() -> Void)? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private func value(_ amount: Double) -> String {
        quota ? amount.formatted(.number.precision(.fractionLength(0...1))) + "%" : cost ? DisplayFormat.cost(amount) : (compactValues ? DisplayFormat.compact(amount) : DisplayFormat.tokens(amount) + " tokens")
    }
    var body: some View {
        let distribution = style.named(self.distribution)
        let legend = (legendItems ?? self.distribution.items).map { item in
            DistributionItem(id: item.id, name: style.displayName(id: item.id, fallback: item.name), value: item.value)
        }
        VStack(spacing: 12) {
            ZStack {
                DonutCanvas(distribution: distribution, cost: cost, quota: quota, style: style,
                            strokeWidth: strokeWidth, duration: cycleMotion ? DataMotion.cycleDuration : DataMotion.duration,
                            onRingClick: onRingClick)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(quota ? L10n.text("额度") : cost ? L10n.text("API 等价估算") : L10n.text("Token 用量"))
                    .accessibilityChartDescriptor(DistributionAccessibility(distribution: distribution, cost: cost, quota: quota))
                VStack(spacing: 4) {
                    Text(center ?? (distribution.items.isEmpty ? "—" : value(distribution.total))).font(.headline).monospacedDigit().lineLimit(2).minimumScaleFactor(0.7)
                        .contentTransition(.numericText(value: centerMetric ?? distribution.total))
                        .animation(reduceMotion ? nil : (cycleMotion ? DataMotion.cycleAnimation : DataMotion.animation), value: centerMetric ?? distribution.total)
                        .clipped()
                    if quota || cost || centerLabel != nil {
                        let caption = centerLabel ?? (quota ? style.displayName(id: "quota:remaining", fallback: L10n.text("剩余额度")) : L10n.text("API 等价估算"))
                        ZStack {
                            Text(caption).font(.caption).foregroundStyle(.secondary)
                                .id(caption)
                                .transition(.move(edge: quota ? .top : .bottom).combined(with: .opacity))
                        }
                        .frame(height: 18)
                        .clipped()
                        .animation(reduceMotion ? nil : DataMotion.animation, value: caption)
                    }
                }.multilineTextAlignment(.center).frame(width: 108, alignment: .center).allowsHitTesting(false).accessibilityHidden(true)
            }.frame(width: 184, height: 184)
            VStack(spacing: 8) {
            if distribution.items.isEmpty { Text(L10n.text("无数据")).font(.caption).foregroundStyle(.secondary) }
            ForEach(legend) { item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Circle().fill(Color(nsColor: NSColor(style.color(id: item.id, activeIDs: distribution.items.map(\.id)))))
                        .frame(width: 7, height: 7).accessibilityHidden(true)
                    Text(item.name).lineLimit(1)
                    Spacer(minLength: 4)
                    Text(value(item.value)).monospacedDigit()
                    if !quota { Text(distribution.fraction(item).formatted(.percent.precision(.fractionLength(0...1)))).foregroundStyle(.secondary).monospacedDigit() }
                }.font(.caption).accessibilityElement(children: .combine)
            }
            }.frame(height: fixedLegendHeight, alignment: .bottom)
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
    static func paths(_ distribution: Distribution, size: NSSize, strokeWidth: CGFloat? = nil) -> [CGPath] {
        paths(distribution.items.map { distribution.fraction($0) }, size: size, strokeWidth: strokeWidth)
    }
    static func paths(_ fractions: [Double], size: NSSize, strokeWidth: CGFloat? = nil) -> [CGPath] {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let outer = min(size.width, size.height) / 2 - 9
        let inner = max(0, outer - (strokeWidth ?? outer * 0.32))
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

struct DonutCanvas: NSViewRepresentable {
    let distribution: Distribution
    let cost: Bool
    let quota: Bool
    let style: ChartStyle
    var strokeWidth: CGFloat? = nil
    var duration = DataMotion.duration
    var onRingClick: (() -> Void)? = nil
    func makeNSView(context: Context) -> DonutNativeView { DonutNativeView() }
    func updateNSView(_ view: DonutNativeView, context: Context) {
        view.configure(distribution, cost: cost, quota: quota, style: style, strokeWidth: strokeWidth, duration: duration)
        view.onRingClick = onRingClick
    }
}

final class DonutNativeView: NSView {
    private var distribution = Distribution([])
    private var renderItems: [DistributionItem] = []
    private var renderFractions: [Double] = []
    private var cost = false
    private var quota = false
    private var style = ChartStyle()
    private var strokeWidth: CGFloat?
    private var accent = NSColor.secondaryLabelColor
    private var paths: [CGPath] = []
    private var geometrySize = NSSize.zero
    private var monitor: Any?
    private var observers: [NSObjectProtocol] = []
    private var selected: Int?
    private var strokeOpacities: [String: Double] = [:]
    private var strokeAnimation: Timer?
    private var tooltip: ChartTooltipView?
    private var dataAnimation: Timer?
    var onRingClick: (() -> Void)?
    private var transitionDuration = DataMotion.duration
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
        strokeAnimation?.invalidate()
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
    }
    func configure(_ value: Distribution, cost: Bool, quota: Bool, style: ChartStyle,
                   strokeWidth: CGFloat? = nil, duration: TimeInterval = DataMotion.duration) {
        transitionDuration = duration
        guard distribution != value || self.cost != cost || self.quota != quota || self.style != style || self.strokeWidth != strokeWidth else { return }
        let dataChanged = distribution != value
        distribution = value; self.cost = cost; self.quota = quota; self.style = style; self.strokeWidth = strokeWidth
        paths = []; clear()
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
            else if event.window === self.window && event.type == .leftMouseDown {
                self.activate(at: self.convert(event.locationInWindow, from: nil))
            }
            else { self.clear() }
            return event
        }
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); clear(); needsDisplay = true }
    private func preparePaths() {
        if geometrySize != bounds.size || paths.count != renderItems.count {
            geometrySize = bounds.size; paths = DonutGeometry.paths(renderFractions, size: bounds.size, strokeWidth: strokeWidth)
        }
    }
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
                let raw = min(1, Date().timeIntervalSince(started) / self.transitionDuration)
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
    private func setSelection(_ index: Int?) {
        guard selected != index else { return }
        selected = index
        strokeAnimation?.invalidate(); strokeAnimation = nil
        let targetID = index.flatMap { renderItems.indices.contains($0) ? renderItems[$0].id : nil }
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            strokeOpacities = targetID.map { [$0: 1] } ?? [:]
            needsDisplay = true
            return
        }
        let start = strokeOpacities
        let ids = Set(start.keys).union(targetID.map { [$0] } ?? [])
        let started = Date()
        strokeAnimation = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self else { timer.invalidate(); return }
                let raw = min(1, Date().timeIntervalSince(started) / 0.18)
                let eased = DataMotion.progress(raw)
                self.strokeOpacities = Dictionary(uniqueKeysWithValues: ids.compactMap { id -> (String, Double)? in
                    let from = start[id] ?? 0
                    let to = id == targetID ? 1.0 : 0.0
                    let value = from + (to - from) * eased
                    return value > 0.001 ? (id, value) : nil
                })
                self.needsDisplay = true
                if raw == 1 {
                    timer.invalidate(); self.strokeAnimation = nil
                    self.strokeOpacities = targetID.map { [$0: 1] } ?? [:]
                }
            }
        }
    }
    func clear() { setSelection(nil); tooltip?.removeFromSuperview(); needsDisplay = true }
    func activate(at point: NSPoint) {
        guard let onRingClick, !isHiddenOrHasHiddenAncestor, bounds.contains(point),
              !ChartInteractionShield.blocks(point, from: self) else { clear(); return }
        var ancestor = superview
        while let view = ancestor {
            if view is NSClipView && !view.bounds.contains(view.convert(point, from: self)) { clear(); return }
            ancestor = view.superview
        }
        let radius = min(bounds.width, bounds.height) / 2 - 9
        guard hypot(point.x - bounds.midX, point.y - bounds.midY) <= radius else { clear(); return }
        clear()
        onRingClick()
    }
    func show(at point: NSPoint) {
        guard !isHiddenOrHasHiddenAncestor, bounds.contains(point), let window,
              dataAnimation == nil, !ChartInteractionShield.blocks(point, from: self) else { clear(); return }
        var ancestor = superview
        while let view = ancestor {
            if view is NSClipView && !view.bounds.contains(view.convert(point, from: self)) { clear(); return }
            ancestor = view.superview
        }
        preparePaths()
        guard let index = paths.firstIndex(where: { $0.contains(point) }), let container = window.contentView?.superview else { clear(); return }
        setSelection(index); needsDisplay = true
        let item = renderItems[index]
        accent = NSColor(style.color(id: item.id, activeIDs: renderItems.map(\.id)))
        let amount = quota ? item.value.formatted(.number.precision(.fractionLength(0...1))) + "%" : cost ? DisplayFormat.cost(item.value) : DisplayFormat.tokens(item.value) + " tokens"
        let tip = tooltip ?? ChartTooltipView(frame: .zero); tooltip = tip
        let size = tip.configure(value: item.name, detail: amount + (quota ? "" : " " + distribution.fraction(item).formatted(.percent.precision(.fractionLength(0...1)))), accent: .separatorColor)
        let cell = window.convertToScreen(convert(bounds, to: nil))
        let frame = HeatmapHitTesting.tooltipFrame(pointer: NSPoint(x: cell.midX, y: cell.maxY - 10), cell: cell, size: size,
                                                   bounds: window.frame.intersection(window.screen?.visibleFrame ?? window.frame))
        tip.frame = container.convert(window.convertFromScreen(frame), from: nil)
        if tip.superview !== container { container.addSubview(tip, positioned: .above, relativeTo: nil) }
    }
    override func draw(_ dirtyRect: NSRect) {
        preparePaths()
        if renderFractions.allSatisfy({ $0 <= 0 }) {
            let width = strokeWidth ?? 27
            let rect = bounds.insetBy(dx: 9 + width / 2, dy: 9 + width / 2)
            let ring = NSBezierPath(ovalIn: rect); ring.lineWidth = width
            NSColor.quaternaryLabelColor.setStroke(); ring.stroke()
        }
        for index in paths.indices {
            let shape = NSBezierPath(cgPath: paths[index])
            let fill = NSColor(style.color(id: renderItems[index].id, activeIDs: renderItems.map(\.id)))
            fill.setFill(); shape.fill()
            if let opacity = strokeOpacities[renderItems[index].id], opacity > 0 {
                NSGraphicsContext.saveGraphicsState(); shape.addClip()
                HeatmapHoverView.barStrokeColor(accent: fill, appearance: effectiveAppearance)
                    .withAlphaComponent(CGFloat(opacity)).setStroke()
                // Clip the centered stroke to the original sector: no expanded silhouette.
                shape.lineWidth = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast ? 3 : 2
                shape.stroke(); NSGraphicsContext.restoreGraphicsState()
            }
        }
    }
}

extension NSColor {
    convenience init(_ rgb: MonitorCore.RGBColor) { self.init(srgbRed: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1) }
}
