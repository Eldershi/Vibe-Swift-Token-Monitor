import AppKit
import SwiftUI
import Sparkle
import MonitorCore
import ServiceManagement

/// GitHub discovers stable releases; Sparkle owns signed download, confirmation and replacement.
@MainActor @Observable final class GitHubUpdater: NSObject, SPUUpdaterDelegate {
    static let shared = GitHubUpdater()
    private(set) var checking = false
    private(set) var message = ""
    private(set) var available: GitHubRelease?
    private(set) var lastChecked: Date?
    private(set) var installing = false
    @ObservationIgnored private var controller: SPUStandardUpdaterController?
    @ObservationIgnored private var timer: Task<Void, Never>?
    @ObservationIgnored private var checkTask: Task<Void, Never>?
    @ObservationIgnored private var observation: NSKeyValueObservation?
    private(set) var installerBusy = false
    @ObservationIgnored private var feedURL: URL?
    @ObservationIgnored private let session: URLSession
    @ObservationIgnored private var serviceWasEnabled = false
    @ObservationIgnored private var automaticRequest = false
    static var isIsolatedRun: Bool {
        ProcessInfo.processInfo.arguments.contains { $0.hasPrefix("--preview") || $0.hasPrefix("--verify") || $0.hasPrefix("--benchmark") || $0.hasPrefix("--beta-") || $0 == "--smoke-test" }
    }
    static func verifyConfiguration() throws {
        let value = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
        try value.updater.start()
        guard !value.updater.automaticallyChecksForUpdates, !value.updater.automaticallyDownloadsUpdates,
              let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
              Data(base64Encoded: key)?.count == 32 else { throw ReleaseCheckError.unavailable }
        print("Sparkle configuration: signed feed/archive required, automatic download disabled")
    }
    override init() {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil; config.urlCache = nil
        config.timeoutIntervalForRequest = 20; config.timeoutIntervalForResource = 30
        session = URLSession(configuration: config)
        super.init()
    }
    func setAutomaticChecks(_ enabled: Bool) {
        timer?.cancel(); timer = nil
        if !enabled, automaticRequest { checkTask?.cancel() }
        guard enabled, Identity.isBeta, !Self.isIsolatedRun else { return }
        timer = Task { [weak self] in
            while !Task.isCancelled {
                self?.check(automatic: true)
                try? await Task.sleep(for: .seconds(6 * 60 * 60))
            }
        }
    }
    func check(automatic: Bool = false) {
        guard !checking, !installerBusy, !Self.isIsolatedRun else { return }
        automaticRequest = automatic
        checking = true; message = L10n.text("正在检查 GitHub 更新…")
        checkTask = Task {
            defer { checking = false }
            do {
                let release = try await GitHubReleaseClient.latest(using: session)
                lastChecked = Date()
                guard release.isNewer(than: Identity.version) else {
                    available = nil; message = L10n.text("当前没有较新的正式版本。")
                    return
                }
                let previous = available?.tag_name
                available = release
                message = L10n.text("发现新版本：%@", release.tag_name)
                if automatic, previous != release.tag_name {
                    let alert = NSAlert()
                    alert.messageText = message
                    alert.informativeText = L10n.text("是否查看并安装此更新？安装前会再次确认。")
                    alert.addButton(withTitle: L10n.text("查看更新"))
                    alert.addButton(withTitle: L10n.text("稍后"))
                    if alert.runModal() == .alertFirstButtonReturn { installAvailable() }
                }
            } catch ReleaseCheckError.rateLimited {
                message = L10n.text("GitHub 请求受限，请稍后再试。")
            } catch ReleaseCheckError.unavailable {
                message = L10n.text("无法获取 GitHub 版本，请稍后重试。")
            } catch is CancellationError {
                message = ""
            } catch {
                message = Task.isCancelled ? "" : L10n.text("更新检查失败，请检查网络后重试。")
            }
        }
    }
    func installAvailable() {
        guard !Self.isIsolatedRun, let release = available, !installerBusy, controller?.updater.sessionInProgress != true else { return }
        guard let url = release.nativeAppcastURL else {
            message = L10n.text("此版本尚未提供应用内更新包，请前往 GitHub 下载。")
            return
        }
        guard Identity.isBeta, Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String != nil else {
            message = L10n.text("此构建未配置更新签名，请使用独立安装包。")
            return
        }
        feedURL = url
        if controller == nil {
            let value = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
            controller = value
            do { try value.updater.start() } catch {
                controller = nil; message = L10n.text("无法启动更新安装程序。")
                return
            }
            value.updater.automaticallyChecksForUpdates = false
            value.updater.automaticallyDownloadsUpdates = false
            observation = value.updater.observe(\.sessionInProgress, options: [.initial, .new]) { [weak self] updater, _ in
                Task { @MainActor in self?.installerBusy = updater.sessionInProgress }
            }
        }
        controller?.checkForUpdates(nil)
    }
    func feedURLString(for updater: SPUUpdater) -> String? { feedURL?.absoluteString }
    func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) { installing = true }
    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        installing = false; message = L10n.text("更新未完成，当前版本仍可继续使用。")
        restoreBackendAfterCancelledInstall()
    }
    /// Called by the existing asynchronous termination path, after explicit Sparkle confirmation.
    func prepareForTermination() async -> Bool {
        guard installing, Identity.isBeta else { return true }
        let service = SMAppService.agent(plistName: Identity.servicePlist)
        serviceWasEnabled = service.status == .enabled
        do {
            if service.status != .notRegistered && service.status != .notFound { try await service.unregister() }
            return true
        } catch {
            installing = false
            message = L10n.text("无法停止后台，已取消退出。请重试更新。")
            return false
        }
    }
    private func restoreBackendAfterCancelledInstall() {
        guard serviceWasEnabled else { return }
        serviceWasEnabled = false
        try? SMAppService.agent(plistName: Identity.servicePlist).register()
    }
}

struct UpdateSettings: View {
    @Bindable var store: AppStore
    @State private var updater = GitHubUpdater.shared
    var body: some View {
        Section(L10n.text("软件更新")) {
            Toggle(L10n.text("自动检查更新"), isOn: $store.preferences.automaticallyCheckForUpdates)
                .disabled(!Identity.isBeta || GitHubUpdater.isIsolatedRun)
            if !updater.message.isEmpty { Text(updater.message).font(.caption).textSelection(.enabled) }
            if updater.available != nil {
                Button(L10n.text("下载并安装…")) { updater.installAvailable() }
                    .disabled(updater.checking || updater.installerBusy)
            }
            HStack {
                Button(L10n.text("检查更新")) { updater.check() }
                    .disabled(updater.checking || updater.installerBusy || GitHubUpdater.isIsolatedRun || !Identity.isBeta)
                if updater.checking { ProgressView().controlSize(.small) }
                Spacer()
                Link(L10n.text("在 GitHub 查看版本"), destination: GitHubRelease.releasesURL)
            }
        }
        .onChange(of: store.preferences.automaticallyCheckForUpdates) {
            store.savePreferences()
            updater.setAutomaticChecks(store.preferences.automaticallyCheckForUpdates)
        }
    }
}
