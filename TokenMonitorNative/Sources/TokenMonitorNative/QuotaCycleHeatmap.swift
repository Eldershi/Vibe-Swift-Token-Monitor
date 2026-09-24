import AppKit
import SwiftUI
import MonitorCore

struct QuotaCycleSegment: Equatable {
    let cycleID: String
    let rect: NSRect
}

enum QuotaCycleGeometry {
    static let minimumHeight: CGFloat = 3
    static func dayRect(at index: Int) -> NSRect {
        NSRect(x: 16 + (index / 7) * 10, y: 8 + (index % 7) * 10, width: 7, height: 7)
    }
    static func dayIndex(at point: NSPoint, count: Int) -> Int? {
        guard point.x.isFinite, point.y.isFinite, point.x >= 16, point.y >= 8, point.y < 75 else { return nil }
        let index = Int((point.x - 16) / 10) * 7 + Int((point.y - 8) / 10)
        guard index < count, dayRect(at: index).contains(point) else { return nil }
        return index
    }
    static func hitRect(for segment: QuotaCycleSegment) -> NSRect {
        guard segment.rect.height < 7 else { return segment.rect }
        let center = segment.rect.midY
        let y = min(max(center - 3.5, 8), 68)
        return NSRect(x: segment.rect.minX, y: y, width: 7, height: 7)
    }
    private struct Candidate {
        let cycleID: String
        let start: CGFloat
        let length: CGFloat
    }
    static func drawsActivity(on day: Date, now: Date, cycles: [ConversionSnapshot.Cycle],
                              calendar: Calendar) -> Bool {
        guard day <= calendar.startOfDay(for: now),
              let dayEnd = calendar.date(byAdding: .day, value: 1, to: day) else { return false }
        let firstStart = cycles.compactMap { DateCodec.parse($0.start) }.min()
        return !cycles.contains { cycle in
            guard let start = DateCodec.parse(cycle.start),
                  let end = DateCodec.parse(cycle.end) else { return false }
            let visibleStart = start == firstStart ? calendar.startOfDay(for: start) : start
            return max(visibleStart, day) < min(end, dayEnd)
        }
    }
    static func segments(days: [Date], cycles: [ConversionSnapshot.Cycle], now: Date,
                         calendar: Calendar) -> [QuotaCycleSegment] {
        guard !days.isEmpty else { return [] }
        let firstStart = cycles.compactMap { DateCodec.parse($0.start) }.min()
        let weekCount = (days.count + 6) / 7
        var weeks = Array(repeating: [Candidate](), count: weekCount)
        for cycle in cycles {
            guard let actualStart = DateCodec.parse(cycle.start),
                  let actualEnd = DateCodec.parse(cycle.end), actualStart <= now else { continue }
            let start = actualStart == firstStart ? calendar.startOfDay(for: actualStart) : actualStart
            let end = min(actualEnd, max(now, actualStart.addingTimeInterval(0.001)))
            guard start < end else { continue }
            for week in stride(from: 0, to: days.count, by: 7) {
                var firstY: CGFloat?, lastY: CGFloat?
                for offset in 0..<min(7, days.count - week) {
                    let day = days[week + offset]
                    guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: day),
                          max(start, day) < min(end, dayEnd) else { continue }
                    let duration = dayEnd.timeIntervalSince(day)
                    let from = max(0, min(1, start.timeIntervalSince(day) / duration))
                    let to = max(0, min(1, end.timeIntervalSince(day) / duration))
                    let y0 = CGFloat(offset) * 10 + CGFloat(from) * 10
                    let y1 = CGFloat(offset) * 10 + CGFloat(to) * 10
                    firstY = firstY ?? y0; lastY = y1
                }
                if let firstY, let lastY {
                    weeks[week / 7].append(Candidate(cycleID: cycle.id, start: firstY,
                                                     length: max(minimumHeight, lastY - firstY - 3)))
                }
            }
        }
        return weeks.enumerated().flatMap { week, candidates in
            let ordered = candidates.sorted { $0.start == $1.start ? $0.cycleID < $1.cycleID : $0.start < $1.start }
            guard !ordered.isEmpty else { return [QuotaCycleSegment]() }
            let gap: CGFloat = 3
            let capacity = CGFloat(67) - gap * CGFloat(ordered.count - 1)
            let extra = ordered.map { max(0, $0.length - minimumHeight) }
            let extraTotal = extra.reduce(0, +)
            let extraBudget = max(0, capacity - CGFloat(ordered.count) * minimumHeight)
            let scale = extraTotal > extraBudget && extraTotal > 0 ? extraBudget / extraTotal : 1
            let lengths = extra.map { minimumHeight + $0 * scale }
            var starts = [CGFloat]()
            for index in ordered.indices {
                let earliest = index == 0 ? CGFloat(0) : starts[index - 1] + lengths[index - 1] + gap
                starts.append(max(ordered[index].start, earliest))
            }
            if let last = ordered.indices.last, starts[last] + lengths[last] > 67 {
                starts[last] = 67 - lengths[last]
                if last > 0 {
                    for index in stride(from: last - 1, through: 0, by: -1) {
                        starts[index] = min(starts[index], starts[index + 1] - gap - lengths[index])
                    }
                }
            }
            return ordered.indices.map { index in
                QuotaCycleSegment(cycleID: ordered[index].cycleID,
                    rect: NSRect(x: CGFloat(16 + week * 10), y: 8 + starts[index],
                                 width: 7, height: lengths[index]))
            }
        }
    }
}

struct QuotaCycleHeatmap: View {
    var store: AppStore
    let cycles: [ConversionSnapshot.Cycle]
    let currentID: String?
    @Binding var selectedID: String?
    @State private var visibleWeeks = 16
    @Environment(\.calendar) private var calendar
    @Environment(\.colorScheme) private var colorScheme

    private var days: [TrendPoint] {
        let activity = store.historyPoints(activity: true)
        let now = store.now
        let earliest = ([calendar.date(byAdding: .day, value: -(visibleWeeks - 1) * 7, to: now)]
                        + (activity.first.map { [$0.date] } ?? [])
                        + cycles.compactMap { DateCodec.parse($0.start) }).compactMap { $0 }.min() ?? now
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: earliest)?.start ?? calendar.startOfDay(for: earliest)
        let lastWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 7, to: lastWeek) ?? now
        let lookup = Dictionary(activity.map { (calendar.startOfDay(for: $0.date), $0) }, uniquingKeysWith: { _, last in last })
        var result: [TrendPoint] = []
        var cursor = weekStart
        while cursor < end && result.count < 400 * 7 {
            result.append(lookup[cursor] ?? TrendPoint(date: cursor, tokens: nil, cost: nil))
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor), next > cursor else { break }
            cursor = next
        }
        return result
    }
    var body: some View {
        let points = days
        let segments = QuotaCycleGeometry.segments(days: points.map(\.date), cycles: cycles, now: store.now, calendar: calendar)
        let activityDays = points.map { QuotaCycleGeometry.drawsActivity(on: $0.date, now: store.now,
                                                                          cycles: cycles, calendar: calendar) }
        let columns = (points.count + 6) / 7
        let maximum = points.compactMap(\.tokens).max() ?? 0
        let activeID = selectedID ?? currentID ?? cycles.last?.id
        let selected = cycles.first { $0.id == activeID }
        let revision = cycles.map { $0.id + String($0.usedPercent ?? -1) }.joined() + (activeID ?? "")
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L10n.text("额度周期")).font(.headline)
                Spacer()
                Menu {
                    Button(L10n.text("当前周期")) { selectedID = nil }
                    ForEach(cycles.reversed()) { cycle in
                        Button(label(cycle)) { selectedID = cycle.id }
                    }
                } label: {
                    Image(systemName: "calendar").foregroundStyle(store.preferences.accentColor ?? .accentColor)
                }.menuStyle(.borderlessButton).fixedSize()
                    .accessibilityLabel(L10n.text("选择额度周期"))
            }
            HistoryScrollView(width: CGFloat(columns * 10 + 29), height: 104,
                              resetKey: store.historyPresentationID.uuidString,
                              prepends: true, points: points, drawingRevision: revision,
                              tint: store.preferences.accentColor,
                              viewportChanged: { width in
                                  visibleWeeks = max(16, Int(ceil((width - 29) / 10)))
                              }) {
                Canvas { context, _ in
                    for (index, point) in points.enumerated() {
                        guard activityDays[index] else { continue }
                        let rect = QuotaCycleGeometry.dayRect(at: index)
                        let value = point.tokens ?? 0
                        let intensity = maximum > 0 && value > 0 ? sqrt(value / maximum) : 0
                        context.fill(Path(roundedRect: rect, cornerRadius: 1.5),
                                     with: .color(gray(intensity: intensity, unknown: point.tokens == nil)))
                    }
                    for week in 0..<columns {
                        let date = points[week * 7].date
                        if week == 0 || !calendar.isDate(date, equalTo: points[(week - 1) * 7].date, toGranularity: .month) {
                            let label = Text(date.formatted(.dateTime.month(.abbreviated))).font(.caption2).foregroundColor(.secondary)
                            context.draw(label, at: CGPoint(x: 16 + week * 10, y: 88), anchor: week == columns - 1 ? .trailing : .center)
                        }
                    }
                }
                .overlay {
                    QuotaCycleInteraction(segments: segments, cycles: cycles, points: points,
                                          activityDays: activityDays,
                                          highlightedID: activeID, accent: store.preferences.accentColor,
                                          select: { selectedID = $0 == currentID ? nil : $0 })
                }
                .frame(width: CGFloat(columns * 10 + 29), height: 104)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(L10n.text("额度周期热力图"))
                .accessibilityValue(selected.map(label) ?? L10n.text("当前周期"))
            }.frame(height: 104)
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .quaternaryLabelColor).opacity(0.35), in: RoundedRectangle(cornerRadius: 14))
    }
    private func label(_ cycle: ConversionSnapshot.Cycle) -> String {
        let start = DateCodec.parse(cycle.start)?.formatted(date: .abbreviated, time: .shortened) ?? "—"
        let end = DateCodec.parse(cycle.end)?.formatted(date: .abbreviated, time: .shortened) ?? "—"
        return start + " – " + end
    }
    private func gray(intensity: Double, unknown: Bool) -> Color {
        let level: Double
        if colorScheme == .dark {
            level = unknown ? 0.32 : 0.40 + 0.38 * intensity
        } else {
            level = unknown ? 0.90 : 0.86 - 0.28 * intensity
        }
        return Color(white: level)
    }
}

private struct QuotaCycleInteraction: NSViewRepresentable {
    let segments: [QuotaCycleSegment]
    let cycles: [ConversionSnapshot.Cycle]
    let points: [TrendPoint]
    let activityDays: [Bool]
    let highlightedID: String?
    let accent: Color?
    let select: (String) -> Void
    func makeNSView(context: Context) -> QuotaCycleHitView { QuotaCycleHitView(frame: .zero) }
    func updateNSView(_ view: QuotaCycleHitView, context: Context) {
        view.segments = segments; view.cycles = cycles; view.points = points; view.activityDays = activityDays
        view.highlightedID = highlightedID; view.accent = accent.map(NSColor.init)
        view.select = select; view.animateAccents()
    }
}

@MainActor private final class QuotaCycleHitView: NSView {
    var segments: [QuotaCycleSegment] = []
    var cycles: [ConversionSnapshot.Cycle] = []
    var points: [TrendPoint] = []
    var activityDays: [Bool] = []
    var highlightedID: String?
    var accent: NSColor?
    var select: ((String) -> Void)?
    private var hoveredID: String?
    private var hoveredDayIndex: Int?
    private var monitor: Any?
    private var animationTimer: Timer?
    private var transitionStart = ProcessInfo.processInfo.systemUptime
    private let transitionDuration: TimeInterval = 0.24
    private var initialMix: [String: CGFloat] = [:]
    private var targetMix: [String: CGFloat] = [:]
    private var initialMask: CGFloat = 0
    private var targetMask: CGFloat = 0
    private var tooltip: ChartTooltipView?
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let monitor { NSEvent.removeMonitor(monitor) }
        guard window != nil else { monitor = nil; animationTimer?.invalidate(); animationTimer = nil; clear(); return }
        window?.acceptsMouseMovedEvents = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown, .scrollWheel]) { [weak self] event in
            guard let self else { return event }
            if event.window === self.window, event.type != .scrollWheel {
                let point = self.convert(event.locationInWindow, from: nil)
                let cycleID = self.show(at: point)
                if event.type == .leftMouseDown, let cycleID {
                    self.select?(cycleID)
                    return nil
                }
            } else { self.clear() }
            return event
        }
    }
    override func viewWillMove(toWindow newWindow: NSWindow?) { clear(); super.viewWillMove(toWindow: newWindow) }
    deinit { if let monitor { NSEvent.removeMonitor(monitor) }; animationTimer?.invalidate() }
    private func clear() {
        if hoveredID != nil { hoveredID = nil; animateAccents() }
        if hoveredDayIndex != nil { hoveredDayIndex = nil; needsDisplay = true }
        tooltip?.removeFromSuperview()
    }
    private func progress(at time: TimeInterval) -> CGFloat {
        let raw = min(1, max(0, (time - transitionStart) / transitionDuration))
        return CGFloat(raw * raw * (3 - 2 * raw))
    }
    private func accentMix(for id: String, at time: TimeInterval) -> CGFloat {
        let eased = progress(at: time)
        let from = initialMix[id] ?? 0
        return from + ((targetMix[id] ?? 0) - from) * eased
    }
    private func maskMix(at time: TimeInterval) -> CGFloat {
        initialMask + (targetMask - initialMask) * progress(at: time)
    }
    func animateAccents() {
        let targets = Dictionary(uniqueKeysWithValues: Set(segments.map(\.cycleID)).map {
            ($0, CGFloat($0 == highlightedID || $0 == hoveredID ? 1 : 0))
        })
        let mask: CGFloat = hoveredID == nil ? 0 : 1
        guard targets != targetMix || mask != targetMask else { needsDisplay = true; return }
        let time = ProcessInfo.processInfo.systemUptime
        if targetMix.isEmpty { initialMix = targets; targetMix = targets; initialMask = mask; targetMask = mask; needsDisplay = true; return }
        initialMix = Dictionary(uniqueKeysWithValues: targets.keys.map { ($0, accentMix(for: $0, at: time)) })
        initialMask = maskMix(at: time)
        targetMix = targets
        targetMask = mask
        transitionStart = time
        animationTimer?.invalidate()
        animationTimer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            self.needsDisplay = true
            if ProcessInfo.processInfo.systemUptime - self.transitionStart >= self.transitionDuration {
                timer.invalidate(); self.animationTimer = nil
                self.initialMix = self.targetMix
                self.initialMask = self.targetMask
            }
        }
        if let animationTimer { RunLoop.main.add(animationTimer, forMode: .common) }
        needsDisplay = true
    }
    @discardableResult private func show(at point: NSPoint) -> String? {
        guard bounds.contains(point), let window,
              !ChartInteractionShield.blocks(point, from: self) else { clear(); return nil }
        var ancestor = superview
        while let view = ancestor {
            if let clip = view as? NSClipView, !clip.bounds.contains(clip.convert(point, from: self)) {
                clear(); return nil
            }
            ancestor = view.superview
        }
        let segment = segments.filter { QuotaCycleGeometry.hitRect(for: $0).contains(point) }
            .min { abs($0.rect.midY - point.y) < abs($1.rect.midY - point.y) }
        let cycle = segment.flatMap { segment in cycles.first { $0.id == segment.cycleID } }
        let candidate = cycle == nil ? QuotaCycleGeometry.dayIndex(at: point, count: points.count) : nil
        let index = candidate.flatMap { activityDays.indices.contains($0) && activityDays[$0] ? $0 : nil }
        guard cycle != nil || index != nil,
              let container = window.contentView?.superview else { clear(); return nil }
        if hoveredID != cycle?.id { hoveredID = cycle?.id; animateAccents() }
        if hoveredDayIndex != index { hoveredDayIndex = index; needsDisplay = true }
        let tip = tooltip ?? ChartTooltipView(frame: .zero); tooltip = tip
        let anchor = segment?.rect ?? QuotaCycleGeometry.dayRect(at: index!)
        let size: NSSize
        if let cycle {
            let used = cycle.usedPercent.map { $0.formatted(.number.precision(.fractionLength(0...1))) + "%" } ?? L10n.text("额度观测未知")
            let start = DateCodec.parse(cycle.start)?.formatted(date: .abbreviated, time: .shortened) ?? "—"
            let end = DateCodec.parse(cycle.end)?.formatted(date: .abbreviated, time: .shortened) ?? "—"
            let observed = DateCodec.parse(cycle.observedAt)?.formatted(date: .abbreviated, time: .shortened) ?? "—"
            size = tip.configure(value: L10n.text("最后观测已用 %@", used), detail: start + " –\n" + end,
                                 footnote: L10n.text("官方读数时间") + "\n" + observed,
                                 accent: accent ?? .controlAccentColor)
        } else { size = tip.configure(point: points[index!], accent: accent ?? .controlAccentColor) }
        let cell = window.convertToScreen(convert(anchor, to: nil))
        let pointer = NSPoint(x: cell.midX, y: cell.maxY - 10)
        let visible = window.frame.intersection(window.screen?.visibleFrame ?? window.frame)
        let frame = HeatmapHitTesting.tooltipFrame(pointer: pointer, cell: cell, size: size, bounds: visible)
        tip.frame = container.convert(window.convertFromScreen(frame), from: nil)
        if tip.superview !== container { container.addSubview(tip, positioned: .above, relativeTo: nil) }
        return cycle?.id
    }
    override func draw(_ dirtyRect: NSRect) {
        let color = accent ?? .controlAccentColor
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let time = ProcessInfo.processInfo.systemUptime
        func cycleFill(_ segment: QuotaCycleSegment) -> NSColor {
            let used = cycles.first { $0.id == segment.cycleID }?.usedPercent
            let fraction = sqrt(max(0, min(1, (used ?? 0) / 100)))
            let level: CGFloat = dark ? (used == nil ? 0.32 : 0.40 + 0.38 * fraction)
                                      : (used == nil ? 0.90 : 0.86 - 0.28 * fraction)
            let base = NSColor(white: level, alpha: 1)
            return base.blended(withFraction: accentMix(for: segment.cycleID, at: time), of: color) ?? base
        }
        for segment in segments {
            cycleFill(segment).setFill()
            NSBezierPath(roundedRect: segment.rect, xRadius: 1.5, yRadius: 1.5).fill()
        }
        let mask = maskMix(at: time)
        if mask > 0.001 {
            NSColor.windowBackgroundColor.withAlphaComponent(0.58 * mask).setFill()
            NSBezierPath(rect: NSRect(x: 0, y: 0, width: bounds.width, height: 78)).fill()
            for segment in segments where segment.cycleID == hoveredID {
                cycleFill(segment).setFill()
                NSBezierPath(roundedRect: segment.rect, xRadius: 1.5, yRadius: 1.5).fill()
            }
        }
        if let hoveredDayIndex, points.indices.contains(hoveredDayIndex) {
            let rect = QuotaCycleGeometry.dayRect(at: hoveredDayIndex)
            let width: CGFloat = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast ? 1.5 : 1
            let outline = NSBezierPath(roundedRect: rect, xRadius: 1.5, yRadius: 1.5)
            let path = NSBezierPath(roundedRect: rect.insetBy(dx: width / 2, dy: width / 2),
                                    xRadius: 1.5 - width / 2, yRadius: 1.5 - width / 2)
            let shadow = NSShadow()
            NSGraphicsContext.saveGraphicsState()
            shadow.shadowColor = color.withAlphaComponent(0.16)
            shadow.shadowBlurRadius = 2; shadow.shadowOffset = .zero; shadow.set()
            color.withAlphaComponent(0.8).setStroke(); path.lineWidth = width; path.stroke()
            shadow.shadowColor = .clear; shadow.set()
            color.withAlphaComponent(0.1).setFill(); outline.fill()
            NSGraphicsContext.restoreGraphicsState()
        }
    }
}
