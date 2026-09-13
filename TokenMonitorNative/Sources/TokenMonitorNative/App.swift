import SwiftUI
import AppKit
import MonitorCore

@main struct TokenMonitorNativeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var store = AppStore.shared
    var body: some Scene {
        Settings { SettingsView(store: store).frame(width: 540, height: 520) }
        .commands {
            CommandGroup(after: .newItem) {
                Button("显示小窗口") { PanelController.shared.show() }
                Button("刷新") { store.refresh() }.keyboardShortcut("r")
                Button("打开 Token Monitor") { Backend.open() }
            }
        }
        MenuBarExtra {
            Text("今日 · \(store.selectedToolTitle)")
            Text("\(DisplayFormat.tokens(store.todayTokens)) tokens")
            Text(store.status)
            Divider()
            Button("显示小窗口") { PanelController.shared.show() }
            SettingsLink { Text("设置…") }.keyboardShortcut(",")
            Button("刷新") { store.refresh() }.keyboardShortcut("r")
            Button("打开 Token Monitor") { Backend.open() }
            Divider()
            Button("退出 Token Monitor Native") { NSApp.terminate(nil) }.keyboardShortcut("q")
        } label: {
            Label(DisplayFormat.compact(store.todayTokens), systemImage: "chart.bar.xaxis")
                .accessibilityLabel("Token Monitor，今日 \(DisplayFormat.tokens(store.todayTokens)) tokens")
        }
    }
}
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private var observers: [NSObjectProtocol] = []
    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--verify-live") {
            Task { @MainActor in exit(await LiveVerification.run()) }; return
        }
        if args.contains("--smoke-test") {
            print("Token Monitor Native: launch OK")
            NSApp.terminate(nil); return
        }
        if let i = args.firstIndex(of: "--preview-fixture"), args.count > i + 1 {
            let url = URL(fileURLWithPath: args[i + 1])
            try? AppStore.shared.preview(statsURL: url, historyURL: url.deletingLastPathComponent().appendingPathComponent("history.json"))
        }
        if args.contains("--benchmark-resize"), args.contains("--preview-fixture") {
            Task { @MainActor in await ResizeVerification.run(store: AppStore.shared) }; return
        }
        AppStore.shared.start()
        if AppStore.shared.preferences.showPanelOnLaunch || AppStore.shared.needsSetup { PanelController.shared.show() }
        if args.contains("--preview-fixture"), args.contains("--preview-wide") {
            PanelController.shared.show()
            PanelController.shared.verificationWindow.setContentSize(NSSize(width: 1000, height: 900))
        }
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { _ in Task { @MainActor in AppStore.shared.sleep() } })
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in Task { @MainActor in AppStore.shared.wake() } })
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { false }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        AppStore.shared.stopConnection()
        let saving = AppStore.shared.saveForTermination()
        Task.detached {
            await saving.value
            // terminate() may be inside a main-actor task's nested AppKit event loop.
            // A run-loop callback can reply without waiting for that task to return.
            RunLoop.main.perform(inModes: [.common, .modalPanel]) {
                MainActor.assumeIsolated { sender.reply(toApplicationShouldTerminate: true) }
            }
            CFRunLoopWakeUp(CFRunLoopGetMain())
        }
        return .terminateLater
    }
    func applicationWillTerminate(_ notification: Notification) { AppStore.shared.stopConnection() }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { PanelController.shared.show(); return true }
}
@MainActor final class PanelController: NSObject, NSToolbarDelegate {
    static let shared = PanelController()
    private var panel: NSPanel?
    var verificationWindow: NSPanel { panel! }
    func verificationSelectPeriod(_ index: Int) {
        guard let item = panel?.toolbar?.items.first(where: { $0.itemIdentifier == periodID }) as? NSToolbarItemGroup else { return }
        item.selectedIndex = index; selectPeriod(item)
    }
    func show() {
        if panel == nil {
            let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 460), styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView], backing: .buffered, defer: false)
            p.title = "Token Monitor Native"
            p.titleVisibility = .hidden
            p.titlebarAppearsTransparent = true
            p.titlebarSeparatorStyle = .none
            p.toolbarStyle = .unified
            let toolbar = NSToolbar(identifier: "CompactNavigation")
            toolbar.delegate = self
            toolbar.displayMode = .iconOnly
            toolbar.allowsUserCustomization = false
            toolbar.showsBaselineSeparator = false
            p.toolbar = toolbar
            p.isReleasedWhenClosed = false; p.hidesOnDeactivate = false
            p.isMovableByWindowBackground = false
            let host = NSHostingView(rootView: CompactView(store: AppStore.shared))
            host.sizingOptions = []
            p.contentView = host
            // The reference screenshot is Retina: its ~640 px window corresponds to 320 pt.
            // Apply after hosting-view installation so AppKit does not replace this constraint.
            p.contentMinSize = NSSize(width: 320, height: 400)
            p.center(); if !ProcessInfo.processInfo.arguments.contains("--benchmark-resize") { p.setFrameAutosaveName("NativeCompactWindow") }
            panel = p
        }
        if panel?.isVisible != true { AppStore.shared.historyPresentationID = UUID() }
        updatePin(); panel?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    private let periodID = NSToolbarItem.Identifier("NativePeriod")
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { [.flexibleSpace, periodID] }
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { [.flexibleSpace, periodID] }
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard id == periodID else { return nil }
        let item = NSToolbarItemGroup(itemIdentifier: id, titles: Period.allCases.map(\.title), selectionMode: .selectOne, labels: nil, target: self, action: #selector(selectPeriod(_:)))
        item.controlRepresentation = .expanded
        item.selectedIndex = Period.allCases.firstIndex(of: AppStore.shared.preferences.period) ?? 1
        item.label = ""; item.toolTip = "时间范围"
        return item
    }
    @objc private func selectPeriod(_ sender: NSToolbarItemGroup) {
        guard Period.allCases.indices.contains(sender.selectedIndex) else { return }
        AppStore.shared.preferences.period = Period.allCases[sender.selectedIndex]
        AppStore.shared.savePreferences()
    }
    func updatePin() { panel?.level = AppStore.shared.preferences.pinned ? .floating : .normal }
}
