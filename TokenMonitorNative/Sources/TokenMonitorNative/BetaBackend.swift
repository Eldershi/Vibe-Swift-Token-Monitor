import SwiftUI
import ServiceManagement
import MonitorCore

@MainActor @Observable final class BetaBackend {
    static let shared = BetaBackend()
    var message = L10n.text("等待后台启动")
    var snapshot: BetaBackendStatus?
    var busy = false
    var requiresApproval = false
    var localOnly = UserDefaults.standard.bool(forKey: "betaViewLocal")
    var syncMessage: String {
        guard let sync = snapshot?.sync, sync.enabled else { return L10n.text("Hub 同步未启用") }
        if let error = sync.error { return error == "unauthorized" ? L10n.text("Hub 密钥需要检查") : error == "credentialUnavailable" ? L10n.text("请在“数据”设置中输入地址和密钥") : error == "rateLimited" ? L10n.text("Hub 请求受限，稍后重试") : L10n.text("Hub 离线 保留上次汇总") }
        return sync.syncing ? L10n.text("正在同步 Hub…") : L10n.text("Hub 已连接 多设备同步")
    }
    func selectLocal(_ local: Bool) { localOnly = local; UserDefaults.standard.set(local, forKey: "betaViewLocal"); reconnect() }
    func configureHub(address: String = "", secret: String = "", deviceId: String = "", enabled: Bool) async throws {
        guard let endpoint else { throw HubError.disconnected }
        var request = try endpoint.connection().request("api/beta/hub")
        request.httpMethod = "POST"; request.timeoutInterval = 70
        request.httpBody = try JSONSerialization.data(withJSONObject: ["address": address, "secret": secret, "deviceId": deviceId, "enabled": enabled])
        let (_, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw HubError.incompatible(L10n.text("Hub 配置失败：检查本机历史、设备身份和连接")) }
        reconnect(); await poll()
    }
    var enabled = !UserDefaults.standard.bool(forKey: "betaBackgroundDisabled")
    @ObservationIgnored private let service = SMAppService.agent(plistName: "local.tokenmonitor.native.beta.backend.plist")
    @ObservationIgnored private var monitor: Task<Void, Never>?
    @ObservationIgnored private var endpoint: BetaEndpoint?
    @ObservationIgnored private var connectedSession: String?
    @ObservationIgnored var connected: ((HubConnection) -> Void)?
    @ObservationIgnored var disconnected: (() -> Void)?
    var lastSuccess: String {
        guard let value = snapshot?.lastSuccess, let date = DateCodec.parse(value) else { return L10n.text("暂无成功采集时间") }
        return date.formatted(date: .abbreviated, time: .standard)
    }
    func start() {
        guard Identity.isBeta, monitor == nil else { return }
        if enabled { message = L10n.text("正在准备后台…") } else { message = L10n.text("后台已停用") }
        // Starting/reopening the UI never reads or rewrites Keychain permissions.
        if enabled { register() }
        monitor = Task { [weak self] in
            while !Task.isCancelled {
                await self?.poll()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }
    private func register() {
        do {
            if (service.status == .notRegistered || service.status == .notFound) { try service.register() }
            requiresApproval = service.status == .requiresApproval
            message = requiresApproval ? L10n.text("请在系统设置中允许 Beta 后台运行") : L10n.text("正在启动后台…")
        } catch { message = L10n.text("后台注册失败，请检查系统的登录项与扩展设置") }
    }
    func enable() {
        enabled = true; UserDefaults.standard.set(false, forKey: "betaBackgroundDisabled")
        register(); reconnect()
    }
    func disable() async {
        busy = true; defer { busy = false }
        do {
            try await service.unregister()
            enabled = false; UserDefaults.standard.set(true, forKey: "betaBackgroundDisabled")
            endpoint = nil; connectedSession = nil
            message = L10n.text("后台已停用"); disconnected?()
        } catch { message = L10n.text("未能停用后台，请在系统设置中检查后台项目") }
    }
    func reconnect() { connectedSession = nil }
    func openSystemSettings() { SMAppService.openSystemSettingsLoginItems() }
    func command(_ action: String) async {
        guard ["refresh", "pause", "resume", "restart"].contains(action), let endpoint else { return }
        busy = true; defer { busy = false }
        do {
            var request = try endpoint.connection().request("api/beta/\(action)")
            request.httpMethod = "POST"; request.timeoutInterval = 5
            let (_, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 202 else { throw HubError.disconnected }
            if action == "restart" { connectedSession = nil; message = L10n.text("正在重启后台…") }
            await poll()
        } catch { message = L10n.text("后台操作未完成，请稍后重试") }
    }
    private func poll() async {
        guard enabled else { return }
        requiresApproval = service.status == .requiresApproval
        if requiresApproval { message = L10n.text("请在系统设置中允许 Beta 后台运行"); return }
        let url = Identity.directory.appendingPathComponent("Backend/endpoint.json")
        do {
            let value = try await Task.detached(priority: .utility) {
                let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                guard (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid(),
                      (attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600,
                      attributes[.type] as? FileAttributeType == .typeRegular else { throw HubError.disconnected }
                return try JSONDecoder().decode(BetaEndpoint.self, from: Data(contentsOf: url))
            }.value
            let connection = try value.connection()
            let probe = HubClient(connection: connection); defer { probe.cancel() }
            let data = try await probe.data("api/beta/status")
            let state = try JSONDecoder().decode(BetaBackendStatus.self, from: data)
            guard state.session == value.session, state.pid == value.pid else { throw HubError.disconnected }
            guard enabled else { return }
            endpoint = value
            if snapshot != state { snapshot = state }
            message = state.paused ? L10n.text("采集已暂停") : state.collecting ? L10n.text("正在采集本机数据…") : state.failure != nil ? L10n.text("采集失败，将自动重试") : L10n.text("后台运行中")
            let identity = value.session + String(localOnly) + String(state.sync?.enabled ?? false)
            if connectedSession != identity {
                connectedSession = identity
                let source = localOnly ? try HubConnection(address: value.address + "/local", secret: value.secret) : connection
                connected?(source)
            }
            AppStore.shared.applyBetaSyncStatus()
        } catch {
            if connectedSession != nil { connectedSession = nil; disconnected?() }
            endpoint = nil; message = L10n.text("等待后台连接…")
        }
    }
}

struct BetaBackendSettings: View {
    @Bindable var backend = BetaBackend.shared
    @State private var authorizingClaude = false
    @State private var authorizationMessage: String?
    private func quotaMessage(_ status: String) -> String {
        switch status {
        case "ok": L10n.text("已获取")
        case "notConfigured": L10n.text("未配置登录")
        case "unauthorized": L10n.text("登录失效，请在原工具重新登录")
        case "sourceRateLimited": L10n.text("请求受限，稍后自动重试")
        default: L10n.text("暂不可用，保留用量统计")
        }
    }
    private var collectionActions: some View {
        Group {
            Button(L10n.text("立即刷新")) { Task { await backend.command("refresh") } }
            Button(backend.snapshot?.paused == true ? L10n.text("恢复采集") : L10n.text("暂停采集")) {
                Task { await backend.command(backend.snapshot?.paused == true ? "resume" : "pause") }
            }
            Button(L10n.text("重启后台")) { Task { await backend.command("restart") } }
        }
    }
    var body: some View {
        Group {
            Section(L10n.text("本机采集")) {
                LabeledContent(L10n.text("后台状态"), value: backend.message)
                    .accessibilityElement(children: .ignore).accessibilityLabel(L10n.text("后台状态")).accessibilityValue(backend.message)
                LabeledContent(L10n.text("最近成功采集"), value: backend.lastSuccess)
                    .accessibilityElement(children: .ignore).accessibilityLabel(L10n.text("最近成功采集")).accessibilityValue(backend.lastSuccess)
                if backend.requiresApproval { Button(L10n.text("打开系统后台设置")) { backend.openSystemSettings() } }
                if backend.enabled {
                    ViewThatFits(in: .horizontal) {
                        HStack { collectionActions }
                        VStack(alignment: .leading) { collectionActions }
                    }.disabled(backend.busy || backend.snapshot == nil)
                    Button(L10n.text("停用后台")) { Task { await backend.disable() } }.disabled(backend.busy)
                } else { Button(L10n.text("启用后台")) { backend.enable() } }
            }
            let configured = (backend.snapshot?.providers ?? []).filter { !["notConfigured", "disabled"].contains($0.status) }.sorted { $0.provider == "codex" && $1.provider != "codex" }
            if !configured.isEmpty {
            Section(L10n.text("账号额度")) {
                if backend.snapshot?.providers?.contains(where: { $0.provider == "claude" && $0.status == "unauthorized" }) == true {
                    Button(L10n.text("授权读取 Claude 额度")) { Task {
                        authorizingClaude = true; defer { authorizingClaude = false }
                        do {
                            try await Task.detached { try Keychain.authorizeClaude() }.value
                            authorizationMessage = L10n.text("已完成访问请求，正在重新读取额度。")
                            await backend.command("refresh")
                        } catch { authorizationMessage = L10n.text("未获得钥匙串访问权限；日志统计仍可继续。") }
                    } }.disabled(authorizingClaude)
                }
                if let authorizationMessage { Text(authorizationMessage).font(.caption) }

                ForEach(configured, id: \.provider) { provider in
                    LabeledContent(provider.provider == "codex" ? "Codex" : provider.provider == "claude" ? "Claude Code" : provider.provider, value: quotaMessage(provider.status))
                }
            }
            }
            BetaHubSettings()

        }
    }
}
