import AppKit
import SwiftUI
import MonitorCore

/// Opt-in comparison only. No ticker, network, saved page, or real preferences.
@MainActor final class PeriodAnimationVerification {
    enum Mode: String { case baseline = "A", frozen = "B", live = "C" }
    static var active: PeriodAnimationVerification?
    private(set) var mode: Mode = .baseline
    private(set) var eventCount = 0
    private let store: AppStore
    private let window: NSPanel
    private let item: NSToolbarItem
    private var group: NSToolbarItemGroup? { item as? NSToolbarItemGroup }
    private var segmented: NSSegmentedControl? { item.view as? NSSegmentedControl }
    private var selectedIndex: Int {
        get { group?.selectedIndex ?? segmented?.selectedSegment ?? -1 }
        set {
            if let group { group.selectedIndex = newValue }
            else { segmented?.selectedSegment = newValue }
        }
    }
    private let toolbar: NSToolbar
    private let originalContent: NSView
    private let blank = NSHostingView(rootView: Color(nsColor: .windowBackgroundColor))
    private let output: FileHandle
    private var monitor: Any?
    private var timer: Timer?
    private var lastAppearance = ""
    private let started = ProcessInfo.processInfo.systemUptime

    static func start(arguments: [String]) throws {
        func value(_ flag: String) -> String? {
            guard let i = arguments.firstIndex(of: flag), arguments.indices.contains(i + 1) else { return nil }
            return arguments[i + 1]
        }
        guard let fixture = value("--preview-fixture"), let log = value("--period-log") else {
            throw NSError(domain: "PeriodComparison", code: 1, userInfo: [NSLocalizedDescriptionKey: "Requires --preview-fixture and --period-log"])
        }
        let store = AppStore.shared
        let url = URL(fileURLWithPath: fixture)
        try store.preview(statsURL: url, historyURL: url.deletingLastPathComponent().appendingPathComponent("history.json"))
        store.preferences.period = .month
        NSApp.appearance = NSAppearance(named: arguments.contains("--preview-dark") ? .darkAqua : .aqua)
        PanelController.shared.show()
        let window = PanelController.shared.verificationWindow
        window.setContentSize(NSSize(width: 320, height: 500)); window.center()
        let runner = try PeriodAnimationVerification(store: store, window: window, log: log)
        active = runner
        PanelController.shared.periodDiagnostic = { [weak runner] in runner?.selected($0) }
        runner.installMonitoring()
        runner.setMode(.baseline)
        runner.setValueSelection(arguments.contains("--period-value-selection") || arguments.contains("--period-rounded"))
        print("PERIOD COMPARISON: Cmd+1 A blank; Cmd+2 B frozen; Cmd+3 C live; Cmd+4 automatic role; Cmd+5 valueSelection role (macOS 27); Cmd+Shift+L light; Cmd+Shift+D dark. Native pointer and keyboard interactions only.")
        fflush(stdout)
    }
    private init(store: AppStore, window: NSPanel, log: String) throws {
        self.store = store; self.window = window
        item = PanelController.shared.verificationPeriodItem!
        toolbar = window.toolbar!; originalContent = window.contentView!
        blank.sizingOptions = []
        // Refuse to overwrite another run's evidence.
        guard !FileManager.default.fileExists(atPath: log) else {
            throw NSError(domain: "PeriodComparison", code: 2, userInfo: [NSLocalizedDescriptionKey: "Log already exists"])
        }
        guard FileManager.default.createFile(atPath: log, contents: nil) else { throw CocoaError(.fileWriteUnknown) }
        output = try FileHandle(forWritingTo: URL(fileURLWithPath: log))
    }
    private func setValueSelection(_ enabled: Bool) {
        if #available(macOS 27.0, *) {
            if let group { group.role = enabled ? .valueSelection : .automatic }
            else { segmented?.role = enabled ? .valueSelection : .automatic }
            record("role")
        } else {
            record("role-unavailable")
        }
    }
    func setMode(_ next: Mode) {
        mode = next
        store.preferences.period = .month
        selectedIndex = Period.allCases.firstIndex(of: .month)!
        window.contentView = next == .baseline ? blank : originalContent
        window.setContentSize(NSSize(width: 320, height: 500))
        window.contentView?.layoutSubtreeIfNeeded()
        record("mode", extra: ["mode": next.rawValue])
    }
    func selected(_ index: Int) {
        let before = store.preferences.period
        eventCount += 1
        if mode == .live { store.preferences.period = Period.allCases[index] }
        record("selection", extra: ["event": eventCount, "before": before.rawValue, "after": store.preferences.period.rawValue,
                                    "input": NSApp.currentEvent?.type.rawValue ?? 0])
    }
    private func record(_ kind: String, extra: [String: Any] = [:]) {
        var value: [String: Any] = ["kind": kind, "seconds": ProcessInfo.processInfo.systemUptime - started,
            "mode": mode.rawValue, "selected": selectedIndex, "period": store.preferences.period.rawValue,
            "sameItem": PanelController.shared.verificationPeriodItem === item, "sameToolbar": window.toolbar === toolbar,
            "appearance": window.effectiveAppearance.name.rawValue, "key": window.isKeyWindow,
            "width": window.contentView?.bounds.width ?? 0]
        if #available(macOS 27.0, *) {
            value["role"] = (group?.role == .valueSelection || segmented?.role == .valueSelection) ? "valueSelection" : "automatic"
        }
        value["control"] = group != nil ? "toolbarGroup" : "roundedSegmentedControl"
        value.merge(extra) { _, new in new }
        if let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) {
            output.write(data); output.write(Data([10]))
        }
    }
    private func installMonitoring() {
        window.acceptsMouseMovedEvents = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .mouseMoved, .leftMouseDown, .leftMouseUp]) { [weak self] event in
            guard let self, event.window === self.window else { return event }
            if event.type == .keyDown, event.modifierFlags.contains(.command) {
                switch event.charactersIgnoringModifiers?.lowercased() {
                case "1": self.setMode(.baseline); return nil
                case "2": self.setMode(.frozen); return nil
                case "3": self.setMode(.live); return nil
                case "4": self.setValueSelection(false); return nil
                case "5": self.setValueSelection(true); return nil
                case "l" where event.modifierFlags.contains(.shift): NSApp.appearance = NSAppearance(named: .aqua)
                case "d" where event.modifierFlags.contains(.shift): NSApp.appearance = NSAppearance(named: .darkAqua)
                default: break
                }
            }
            let p = event.locationInWindow
            if event.type == .keyDown || p.y > self.window.frame.height - 90 {
                self.record("input", extra: ["type": event.type.rawValue, "x": p.x, "y": p.y,
                    "keyCode": event.type == .keyDown ? Int(event.keyCode) : -1])
            }
            return event
        }
        timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let names = [self.window.effectiveAppearance.name.rawValue,
                             self.item.view?.effectiveAppearance.name.rawValue ?? "no-view",
                             self.window.isKeyWindow ? "key" : "inactive"].joined(separator: "/")
                if names != self.lastAppearance {
                    self.lastAppearance = names; self.record("appearance", extra: ["value": names])
                }
            }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }
}
