import SwiftUI
import AppKit
import MonitorCore
import ServiceManagement

@main struct TokenMonitorNativeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var store = AppStore.shared
    var body: some Scene {
        Settings { SettingsView(store: store).frame(width: 540, height: 520) }
        .commands {
            CommandGroup(after: .newItem) {
                Button(L10n.text("显示小窗口")) { PanelController.shared.show() }
                Button(L10n.text("刷新")) { store.refresh() }.keyboardShortcut("r")
                if !Identity.isBeta { Button(L10n.text("打开 Token Monitor")) { Backend.open() } }
            }
        }
        MenuBarExtra {
            Text(L10n.text("今日 · %@", String(describing: store.selectedToolTitle)))
            Text("\(DisplayFormat.tokens(store.todayTokens)) tokens")
            Text(store.status)
            Divider()
            Button(L10n.text("显示小窗口")) { PanelController.shared.show() }
            SettingsLink { Text(L10n.text("设置…")) }.keyboardShortcut(",")
            Button(L10n.text("刷新")) { store.refresh() }.keyboardShortcut("r")
            if !Identity.isBeta { Button(L10n.text("打开 Token Monitor")) { Backend.open() } }
            Divider()
            Button(L10n.text("退出 %@", String(describing: Identity.name))) { NSApp.terminate(nil) }.keyboardShortcut("q")
        } label: {
            Label(DisplayFormat.compact(store.todayTokens) + (Identity.isBeta ? " β" : ""), systemImage: "chart.bar.xaxis")
                .accessibilityLabel(L10n.text("Token Monitor，今日 %@ tokens", String(describing: DisplayFormat.tokens(store.todayTokens))))
        }
    }
}
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private var observers: [NSObjectProtocol] = []
    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = ProcessInfo.processInfo.arguments
        if let index = args.firstIndex(of: "--verify-localization"), args.count > index + 1 {
            let expected = args[index + 1]
            let labels = [L10n.text("通用"), L10n.text("布局"), L10n.text("数据"), L10n.text("关于")]
            let baseline = expected == "zh-Hans" ? ["通用", "布局", "数据", "关于"] : ["General", "Layout", "Data", "About"]
            let dynamic = L10n.text("连接成功：已读取 %@ 台设备。点击“保存连接”开始同步。", "2")
            let expectedDynamic = expected == "zh-Hans"
                ? "连接成功：已读取 2 台设备。点击“保存连接”开始同步。"
                : "Connection successful. Devices read: 2. Click “Save connection” to start syncing."
            guard labels == baseline, dynamic == expectedDynamic else {
                fputs("Localization verification failed.\n", stderr); exit(1)
            }
            print("Localization verified: \(expected); \(labels.joined(separator: ", ")); \(dynamic)")
            exit(0)
        }
        if Identity.isBeta, args.contains("--beta-prepare-hub") || args.contains("--beta-enable-hub") {
            Task { @MainActor in exit(await BetaHubProvisioning.run(enable: args.contains("--beta-enable-hub"))) }; return
        }
        if Identity.isBeta, args.contains("--beta-unregister") || args.contains("--beta-register") || args.contains("--beta-service-status") {
            Task { @MainActor in
                let service = SMAppService.agent(plistName: "local.tokenmonitor.native.beta.backend.plist")
                do {
                    if args.contains("--beta-unregister"), service.status != .notRegistered { try await service.unregister() }
                    if args.contains("--beta-register"), (service.status == .notRegistered || service.status == .notFound) { try service.register() }
                    print("Beta service status: \(service.status.rawValue)")
                    exit(0)
                } catch { print("Beta service operation failed: \(error)"); exit(1) }
            }; return
        }
        if args.contains("--verify-live") {
            Task { @MainActor in exit(await LiveVerification.run()) }; return
        }
        if args.contains("--smoke-test") {
            guard InterfaceSymbols.resourceBundle.image(forResource: "ReferenceGear") != nil else {
                fputs("Missing compiled gear symbol resource.\n", stderr); exit(1)
            }
            guard ["DeviceMac", "DeviceWindows", "DeviceLinux"].allSatisfy({ InterfaceSymbols.resourceBundle.image(forResource: $0) != nil }),
                  NSImage(systemSymbolName: "binoculars.fill", accessibilityDescription: nil) != nil,
                  NSImage(systemSymbolName: "macbook", accessibilityDescription: nil) != nil else {
                fputs("Missing device or overview icon resource.\n", stderr); exit(1)
            }
            print("Token Monitor Native: launch, gear and device icon resources OK")
            NSApp.terminate(nil); return
        }
        if let i = args.firstIndex(of: "--preview-fixture"), args.count > i + 1 {
            if args.contains("--preview-dark") { NSApp.appearance = NSAppearance(named: .darkAqua) }
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
        if args.contains("--preview-fixture"), args.contains("--preview-narrow") {
            PanelController.shared.show()
            PanelController.shared.verificationWindow.setContentSize(NSSize(width: 320, height: 500))
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
            let p = CompactPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 460), styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView], backing: .buffered, defer: false)
            p.title = Identity.name
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
            p.installSizeConstraints()
            p.center(); if !ProcessInfo.processInfo.arguments.contains("--benchmark-resize"), !ProcessInfo.processInfo.arguments.contains("--preview-fixture") { p.setFrameAutosaveName("NativeCompactWindow") }
            p.installSizeConstraints() // Recheck after restoring an older saved frame.
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
        item.label = ""; item.toolTip = L10n.text("时间范围")
        return item
    }
    @objc private func selectPeriod(_ sender: NSToolbarItemGroup) {
        guard Period.allCases.indices.contains(sender.selectedIndex) else { return }
        AppStore.shared.preferences.period = Period.allCases[sender.selectedIndex]
        AppStore.shared.savePreferences()
    }
    func updatePin() { panel?.level = AppStore.shared.preferences.pinned ? .floating : .normal }
}
