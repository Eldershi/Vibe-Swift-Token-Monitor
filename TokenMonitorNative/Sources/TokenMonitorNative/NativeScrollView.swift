import AppKit
import SwiftUI
import MonitorCore

/// Offset policy is independent of SwiftUI identity and late geometry updates.
struct HistoryScrollPosition {
    private(set) var followsLatest = true
    private(set) var offset: CGFloat = 0
    private var contentWidth: CGFloat = 0
    mutating func reset() { followsLatest = true }
    mutating func userScrolled(to value: CGFloat) { followsLatest = false; offset = value }
    mutating func layout(content: CGFloat, viewport: CGFloat, prepends: Bool = false) -> CGFloat {
        let maximum = max(0, content - viewport)
        if followsLatest { offset = maximum }
        else { offset = min(maximum, max(0, offset + (prepends ? max(0, content - contentWidth) : 0))) }
        contentWidth = content
        return offset
    }
}

/// Owns a fixed-size document and sets its offset only after AppKit has a real viewport.
struct HistoryScrollView<Content: View>: NSViewRepresentable {
    var width: CGFloat
    var height: CGFloat
    var resetKey: String
    var prepends = false
    var points: [TrendPoint]
    var tint: Color?
    @ViewBuilder var content: () -> Content
    func makeNSView(context: Context) -> HistoryNativeScroll { HistoryNativeScroll(content: AnyView(content().environment(\.self, context.environment))) }
    func updateNSView(_ view: HistoryNativeScroll, context: Context) {
        let key = HistoryDrawingKey(points: points, tint: tint, scheme: context.environment.colorScheme,
                                    differentiate: context.environment.accessibilityDifferentiateWithoutColor,
                                    locale: context.environment.locale, calendar: context.environment.calendar,
                                    scale: context.environment.displayScale)
        if view.drawingKey != key {
            view.drawingKey = key
            view.host.rootView = AnyView(content().environment(\.self, context.environment).tint(tint).accentColor(tint))
        }
        view.documentSize = NSSize(width: width, height: height)
        view.prepends = prepends
        if view.resetKey != resetKey { view.resetKey = resetKey; view.position.reset() }
        view.needsLayout = true
    }
}
struct HistoryDrawingKey: Equatable {
    let points: [TrendPoint]
    let tint: Color?
    let scheme: ColorScheme
    let differentiate: Bool
    let locale: Locale
    let calendar: Calendar
    let scale: CGFloat
}
final class HistoryNativeScroll: NSScrollView {
    var drawingKey: HistoryDrawingKey?
    let host: NSHostingView<AnyView>
    var documentSize = NSSize.zero
    var resetKey = ""
    var prepends = false
    var position = HistoryScrollPosition()
    private var positioning = false
    private var lastViewport = NSSize.zero
    init(content: AnyView) {
        host = NSHostingView(rootView: content)
        super.init(frame: .zero)
        drawsBackground = false
        hasHorizontalScroller = false; hasVerticalScroller = false
        horizontalScrollElasticity = .none; verticalScrollElasticity = .none
        host.sizingOptions = []; documentView = host
        contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(boundsChanged), name: NSView.boundsDidChangeNotification, object: contentView)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layout() {
        positioning = true
        super.layout()
        host.setFrameSize(documentSize)
        let x = position.layout(content: documentSize.width, viewport: contentView.bounds.width, prepends: prepends)
        contentView.scroll(to: NSPoint(x: x, y: 0)); reflectScrolledClipView(contentView)
        lastViewport = contentView.bounds.size
        positioning = false
    }
    @objc private func boundsChanged() {
        guard !positioning else { return }
        guard contentView.bounds.size == lastViewport else { lastViewport = contentView.bounds.size; return }
        position.userScrolled(to: contentView.bounds.minX)
    }
    override func scrollWheel(with event: NSEvent) {
        // Vertical trackpad/wheel gestures continue scrolling the surrounding page.
        if !event.modifierFlags.contains(.shift), abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX) {
            nextResponder?.scrollWheel(with: event)
        } else { super.scrollWheel(with: event) }
    }
}

/// An application-owned 14 pt hit target with a 5 pt visual thumb. System scrollbar
/// preferences do not affect its track or inactivity policy.
final class QuietScroller: NSScroller {
    override class var isCompatibleWithOverlayScrollers: Bool { true }
    override func draw(_ dirtyRect: NSRect) { if alphaValue > 0 { drawKnob() } }
    override func drawKnob() {
        let knob = rect(for: .knob)
        NSColor(calibratedWhite: 0.72, alpha: 0.65).setFill()
        NSBezierPath(roundedRect: NSRect(x: bounds.midX - 2.5, y: knob.minY, width: 5, height: knob.height), xRadius: 2.5, yRadius: 2.5).fill()
    }
    var interaction: ((Bool) -> Void)?
    override func mouseDown(with event: NSEvent) {
        interaction?(true); super.mouseDown(with: event); interaction?(false)
    }
}

struct PageScrollView<Content: View>: NSViewRepresentable {
    @ViewBuilder var content: () -> Content
    func makeNSView(context: Context) -> PageNativeScroll { PageNativeScroll(content: AnyView(content().environment(\.self, context.environment))) }
    func updateNSView(_ view: PageNativeScroll, context: Context) {
        view.setContent(AnyView(content().environment(\.self, context.environment)))
    }
}
final class PageNativeScroll: NSScrollView {
    let host: NSHostingView<AnyView>
    private let thumb = QuietScroller()
    private var edgeTracking: NSTrackingArea?
    private var hideWork: DispatchWorkItem?
    private var hovering = false
    private var dragging = false
    private var measuring = false
    private var documentHeight: CGFloat = 0
    init(content: AnyView) {
        host = NSHostingView(rootView: content)
        super.init(frame: .zero)
        drawsBackground = false
        hasVerticalScroller = false; hasHorizontalScroller = false
        verticalScrollElasticity = .automatic; horizontalScrollElasticity = .none
        host.sizingOptions = []
        documentView = host
        addSubview(thumb)
        thumb.scrollerStyle = .legacy; thumb.controlSize = .small
        thumb.alphaValue = 0; thumb.target = self; thumb.action = #selector(dragThumb(_:))
        thumb.interaction = { [weak self] active in self?.dragging = active; self?.reveal() }
        contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(scrolled), name: NSView.boundsDidChangeNotification, object: contentView)
    }
    func setContent(_ content: AnyView) {
        host.rootView = AnyView(content.fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { [weak self] height in
                guard let self, abs(self.documentHeight - height) > 0.5 else { return }
                self.documentHeight = height; self.needsLayout = true
            })
        needsLayout = true
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layout() {
        guard !measuring else { return }
        measuring = true; defer { measuring = false }
        super.layout()
        let width = contentView.bounds.width
        // SwiftUI reports only its ideal height; AppKit owns the viewport width.
        // Avoid asking the entire tree for another sizeThatFits pass during every resize.
        host.setFrameSize(NSSize(width: width, height: max(contentView.bounds.height, ceil(documentHeight))))
        thumb.frame = NSRect(x: bounds.width - 14, y: 0, width: 14, height: bounds.height)
        updateThumb()
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let edgeTracking { removeTrackingArea(edgeTracking) }
        let area = NSTrackingArea(rect: NSRect(x: bounds.width - 18, y: 0, width: 18, height: bounds.height), options: [.mouseEnteredAndExited, .activeAlways], owner: self)
        addTrackingArea(area); edgeTracking = area
    }
    override func mouseEntered(with event: NSEvent) { hovering = true; reveal() }
    override func mouseExited(with event: NSEvent) { hovering = false; reveal() }
    override func scrollWheel(with event: NSEvent) { reveal(); super.scrollWheel(with: event) }
    @objc private func scrolled() { updateThumb() }
    private func updateThumb() {
        let height = max(1, host.frame.height), viewport = contentView.bounds.height
        thumb.knobProportion = min(1, viewport / height)
        thumb.doubleValue = Double(contentView.bounds.minY / max(1, height - viewport))
        thumb.isEnabled = height > viewport
        if !thumb.isEnabled { thumb.alphaValue = 0 }
    }
    private func reveal() {
        hideWork?.cancel()
        guard thumb.isEnabled else { return }
        thumb.alphaValue = 1
        guard !hovering, !dragging else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            NSAnimationContext.runAnimationGroup { context in context.duration = 0.25; self.thumb.animator().alphaValue = 0 }
        }
        hideWork = work; DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
    }
    @objc private func dragThumb(_ sender: NSScroller) {
        let maximum = max(0, host.frame.height - contentView.bounds.height)
        var y = CGFloat(sender.doubleValue) * maximum
        switch sender.hitPart {
        case .decrementPage: y = contentView.bounds.minY - contentView.bounds.height
        case .incrementPage: y = contentView.bounds.minY + contentView.bounds.height
        default: break
        }
        contentView.scroll(to: NSPoint(x: 0, y: min(maximum, max(0, y))))
        reflectScrolledClipView(contentView); reveal()
    }
}
