import AppKit
import SwiftUI
import MonitorCore

/// Shares the Canvas geometry without adding a view or tracking area for every day.
enum HeatmapHitTesting {
    static func rect(at index: Int) -> NSRect {
        NSRect(x: 16 + (index / 7) * 10, y: 8 + (index % 7) * 10, width: 7, height: 7)
    }
    static func index(at point: NSPoint, count: Int) -> Int? {
        guard point.x.isFinite, point.y.isFinite, point.x >= 16, point.y >= 8, point.y < 75 else { return nil }
        let column = Int((point.x - 16) / 10), row = Int((point.y - 8) / 10)
        let index = column * 7 + row
        guard index < count, rect(at: index).contains(point) else { return nil }
        return index
    }
    static func tooltipFrame(pointer: NSPoint, cell: NSRect, size: NSSize, bounds: NSRect) -> NSRect {
        let safe = bounds.insetBy(dx: 8, dy: 8)
        let width = min(size.width, safe.width), height = min(size.height, safe.height)
        let x = min(max(pointer.x - width / 2, safe.minX), safe.maxX - width)
        let above = max(pointer.y + 18, cell.maxY + 8)
        let y = above + height <= safe.maxY ? above : cell.minY - height - 12
        return NSRect(x: x, y: max(safe.minY, min(y, safe.maxY - height)), width: width, height: height)
    }
}

/// Hit testing shares the exact rendered capsule; absent bars remain AX-only.
enum ChartHoverGeometry: Equatable {
    case heatmap
    case bars(ceiling: Double, slot: CGFloat, height: CGFloat)
    case fittedBars(ceiling: Double, width: CGFloat, height: CGFloat, hourly: Bool)
    func cornerRadius(for rect: NSRect) -> CGFloat {
        switch self {
        case .heatmap: return 1.5
        case .bars, .fittedBars: return min(rect.width, rect.height) / 2
        }
    }
    func index(at point: NSPoint, points: [TrendPoint]) -> Int? {
        switch self {
        case .heatmap: return HeatmapHitTesting.index(at: point, count: points.count)
        case let .bars(_, slot, height):
            guard point.x.isFinite, point.y.isFinite, slot > 0, point.x >= 17, point.y >= 0, point.y < height else { return nil }
            let index = Int((point.x - 16) / slot)
            guard points.indices.contains(index), point.x >= 17 + CGFloat(index) * slot,
                  point.x < 22 + CGFloat(index) * slot else { return nil }
            guard let value = points[index].tokens, value.isFinite, value > 0 else { return nil }
            let bar = rect(at: index, points: points)
            let radius = cornerRadius(for: bar)
            return NSBezierPath(roundedRect: bar, xRadius: radius, yRadius: radius).contains(point) ? index : nil
        case let .fittedBars(_, width, height, _):
            guard point.x.isFinite, point.y.isFinite, width > 0, height > 0, !points.isEmpty,
                  point.x >= 0, point.x < width, point.y >= 0, point.y < height else { return nil }
            let slot = width / CGFloat(points.count), index = min(points.count - 1, Int(point.x / slot))
            guard let value = points[index].tokens, value.isFinite, value > 0 else { return nil }
            let bar = rect(at: index, points: points), radius = cornerRadius(for: bar)
            return NSBezierPath(roundedRect: bar, xRadius: radius, yRadius: radius).contains(point) ? index : nil
        }
    }
    func rect(at index: Int, points: [TrendPoint]) -> NSRect {
        switch self {
        case .heatmap: return HeatmapHitTesting.rect(at: index)
        case let .bars(ceiling, slot, height):
            let value = points[index].tokens ?? 0
            let barHeight = value.isFinite && value > 0 && ceiling > 0 ? CGFloat(min(1, value / ceiling)) * height : 0
            return NSRect(x: 17 + CGFloat(index) * slot, y: height - barHeight, width: 5, height: barHeight)
        case let .fittedBars(ceiling, width, height, _):
            let value = points[index].tokens ?? 0, slot = width / CGFloat(max(1, points.count))
            let barWidth = min(5, max(2, slot * 0.66))
            let barHeight = value.isFinite && value > 0 && ceiling > 0 ? CGFloat(min(1, value / ceiling)) * height : 0
            return NSRect(x: (CGFloat(index) + 0.5) * slot - barWidth / 2, y: height - barHeight, width: barWidth, height: barHeight)
        }
    }
    var isHourly: Bool { if case let .fittedBars(_, _, _, hourly) = self { return hourly }; return false }
}

/// A native, mouse-transparent view above the window content, outside both scroll clips.
/// No child window, SwiftUI intrinsic-size negotiation, or popup animation is involved.
@MainActor final class ChartTooltipView: NSView {
    private let valueLabel = NSTextField(labelWithString: "")
    private let dateLabel = NSTextField(labelWithString: "")
    var accent: NSColor = .controlAccentColor
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override init(frame: NSRect) {
        super.init(frame: frame)
        valueLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        dateLabel.font = .systemFont(ofSize: 11)
        valueLabel.textColor = .labelColor; dateLabel.textColor = .secondaryLabelColor
        for label in [valueLabel, dateLabel] {
            label.alignment = .center; label.lineBreakMode = .byTruncatingTail
            label.setAccessibilityElement(false); addSubview(label)
        }
        setAccessibilityElement(false)
    }
    required init?(coder: NSCoder) { fatalError() }
    func configure(point: TrendPoint, accent: NSColor) -> NSSize {
        configure(value: point.tokens.map { DisplayFormat.tokens($0) + " tokens" } ?? L10n.text("无数据"),
                  detail: point.date.formatted(date: .abbreviated, time: .omitted), accent: accent)
    }
    func configure(value: String, detail: String, accent: NSColor) -> NSSize {
        valueLabel.stringValue = value
        dateLabel.stringValue = detail
        self.accent = accent
        let valueSize = valueLabel.intrinsicContentSize, dateSize = dateLabel.intrinsicContentSize
        let size = NSSize(width: min(280, ceil(max(valueSize.width, dateSize.width)) + 38), height: valueSize.height + dateSize.height + 27)
        valueLabel.frame = NSRect(x: 15, y: 12, width: size.width - 30, height: valueSize.height)
        dateLabel.frame = NSRect(x: 15, y: 15 + valueSize.height, width: size.width - 30, height: dateSize.height)
        needsDisplay = true
        return size
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
    override func draw(_ dirtyRect: NSRect) {
        let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 4, dy: 4), xRadius: 8, yRadius: 8)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.18)
        shadow.shadowBlurRadius = 3; shadow.shadowOffset = NSSize(width: 0, height: -1); shadow.set()
        NSColor.windowBackgroundColor.setFill(); shape.fill()
        NSGraphicsContext.restoreGraphicsState()
        accent.withAlphaComponent(0.55).setStroke(); shape.lineWidth = 1; shape.stroke()
    }
}

/// A mouse-transparent overlay draws only the selected cell, above the cached Canvas.
@MainActor final class HeatmapHoverView: NSView {
    var geometry: ChartHoverGeometry = .heatmap { didSet { if geometry != oldValue { clear() } } }
    var points: [TrendPoint] = [] { didSet { if points != oldValue { clear() } } }
    var accent: NSColor? { didSet { if accent != oldValue { clear(); needsDisplay = true } } }
    var emphasisColor: NSColor { accent ?? .controlAccentColor }
    private(set) var selectedIndex: Int?
    private var tracking: NSTrackingArea?
    private var mouseMonitor: Any?
    private(set) var tooltip: ChartTooltipView?
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        setAccessibilityElement(false)
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(scrollChanged(_:)), name: NSView.boundsDidChangeNotification, object: nil)
        for name in [NSWindow.didResignKeyNotification, NSWindow.willCloseNotification, NSWindow.didMoveNotification, NSWindow.didResizeNotification, NSApplication.didResignActiveNotification] {
            center.addObserver(self, selector: #selector(windowChanged(_:)), name: name, object: nil)
        }
    }
    required init?(coder: NSCoder) { fatalError() }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.acceptsMouseMovedEvents = true
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor); self.mouseMonitor = nil }
        if window != nil {
            // Hosting views may own mouse dispatch; observe without consuming events.
            mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown, .rightMouseDown, .scrollWheel, .leftMouseDragged]) { [weak self] event in
                guard let self else { return event }
                if event.window === self.window, [.mouseMoved, .leftMouseDown, .rightMouseDown].contains(event.type) {
                    self.show(at: self.convert(event.locationInWindow, from: nil))
                } else { self.clear() }
                return event
            }
        }
    }
    override func viewWillMove(toWindow newWindow: NSWindow?) { clear(); super.viewWillMove(toWindow: newWindow) }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); clear(); needsDisplay = true }
    override func updateTrackingAreas() {
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self)
        addTrackingArea(area); tracking = area
        super.updateTrackingAreas()
    }
    override func mouseEntered(with event: NSEvent) { mouseMoved(with: event) }
    override func mouseMoved(with event: NSEvent) { show(at: convert(event.locationInWindow, from: nil)) }
    override func mouseExited(with event: NSEvent) { clear() }
    private func isVisiblePoint(_ point: NSPoint) -> Bool {
        guard !isHiddenOrHasHiddenAncestor, bounds.contains(point) else { return false }
        var ancestor = superview
        while let view = ancestor {
            if view is NSClipView, !view.bounds.contains(view.convert(point, from: self)) { return false }
            ancestor = view.superview
        }
        return true
    }
    func show(at location: NSPoint) {
        guard isVisiblePoint(location), let window,
              !ChartInteractionShield.blocks(location, from: self),
              let index = geometry.index(at: location, points: points) else { clear(); return }
        let changed = selectedIndex != index
        selectedIndex = index
        if changed { needsDisplay = true }
        guard let container = window.contentView?.superview else { clear(); return }
        let tip = tooltip ?? ChartTooltipView(frame: .zero)
        tooltip = tip
        let point = points[index]
        let size = geometry.isHourly
            ? tip.configure(value: point.tokens.map { DisplayFormat.tokens($0) + " tokens" } ?? L10n.text("无数据"), detail: point.date.formatted(date: .omitted, time: .shortened), accent: emphasisColor)
            : tip.configure(point: point, accent: emphasisColor)
        let anchor = geometry.rect(at: index, points: points)
        let cell = window.convertToScreen(convert(anchor, to: nil))
        // Stable within one cell/bar, including near the above/below boundary.
        let pointer = NSPoint(x: cell.midX, y: cell.maxY - 10)
        let bounds = window.frame.intersection(window.screen?.visibleFrame ?? window.frame)
        let screenFrame = HeatmapHitTesting.tooltipFrame(pointer: pointer, cell: cell, size: size, bounds: bounds)
        // Convert to the common window overlay after all scrolling offsets are resolved.
        tip.frame = container.convert(window.convertFromScreen(screenFrame), from: nil)
        if tip.superview !== container { container.addSubview(tip, positioned: .above, relativeTo: nil) }
    }

    @objc private func scrollChanged(_ note: Notification) {
        guard let clip = note.object as? NSClipView, isDescendant(of: clip) else { return }
        clear()
    }
    @objc private func windowChanged(_ note: Notification) {
        if note.name == NSApplication.didResignActiveNotification || (note.object as? NSWindow) === window { clear() }
    }
    @objc func clear() {
        if selectedIndex != nil { selectedIndex = nil; needsDisplay = true }
        tooltip?.removeFromSuperview()
    }
    static func barStrokeColor(accent: NSColor, appearance: NSAppearance) -> NSColor {
        var result = accent
        appearance.performAsCurrentDrawingAppearance {
            let dark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            if let rgb = accent.usingColorSpace(.sRGB) {
                let amount = dark ? 0.45 : 0.30
                let target = dark ? 1.0 : 0.0
                result = NSColor(srgbRed: rgb.redComponent * (1 - amount) + target * amount,
                                 green: rgb.greenComponent * (1 - amount) + target * amount,
                                 blue: rgb.blueComponent * (1 - amount) + target * amount, alpha: 1)
            }
        }
        return result
    }
    override func draw(_ dirtyRect: NSRect) {
        guard let selectedIndex else { return }
        let rect = geometry.rect(at: selectedIndex, points: points)
        let contrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        let lineWidth = min(contrast ? 1.5 : 1, rect.height)
        let radius = geometry.cornerRadius(for: rect)
        let insetRadius = max(0, radius - lineWidth / 2)
        let path = NSBezierPath(roundedRect: rect.insetBy(dx: lineWidth / 2, dy: lineWidth / 2), xRadius: insetRadius, yRadius: insetRadius)
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        let outline = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        if case .heatmap = geometry {
            let shadow = NSShadow()
            shadow.shadowColor = emphasisColor.withAlphaComponent(contrast ? 0.28 : 0.16)
            shadow.shadowBlurRadius = 2; shadow.shadowOffset = .zero; shadow.set()
            emphasisColor.withAlphaComponent(contrast ? 1 : 0.8).setStroke()
            path.lineWidth = lineWidth; path.stroke()
            shadow.shadowColor = .clear; shadow.set()
            emphasisColor.withAlphaComponent(0.1).setFill(); outline.fill()
        } else {
            // Keep every highlight pixel inside the same capsule as the Canvas.
            outline.addClip()
            emphasisColor.withAlphaComponent(0.1).setFill(); outline.fill()
            let stroke = Self.barStrokeColor(accent: emphasisColor, appearance: effectiveAppearance)
            if rect.height <= lineWidth {
                // The inner stroke covers the whole sub-point capsule; avoid a zero-height path.
                stroke.setFill(); outline.fill()
            } else {
                stroke.setStroke(); path.lineWidth = lineWidth; path.stroke()
            }
        }
    }
}

struct BarHoverOverlay: NSViewRepresentable {
    let points: [TrendPoint]
    let ceiling: Double
    let width: CGFloat
    let height: CGFloat
    let hourly: Bool
    let tint: Color?
    func makeNSView(context: Context) -> HeatmapHoverView { HeatmapHoverView(frame: .zero) }
    func updateNSView(_ view: HeatmapHoverView, context: Context) {
        view.points = points
        view.accent = tint.map(NSColor.init)
        view.geometry = .fittedBars(ceiling: ceiling, width: width, height: height, hourly: hourly)
    }
}
