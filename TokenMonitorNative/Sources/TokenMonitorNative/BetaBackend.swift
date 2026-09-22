import SwiftUI
import ServiceManagement
import MonitorCore

private struct BetaHubErrorResponse: Decodable { let error: String }
private struct BetaHubConfigurationError: LocalizedError {
    let code: String
    var errorDescription: String? {
        switch code {
        case "busy": L10n.text("Hub 正在同步，请稍后重试。")
        case "localHistoryNotReady": L10n.text("本机历史尚未准备完成，请先刷新后重试。")
        case "deviceNotMatched": L10n.text("所选设备已不在此 Hub 中，请重新验证并选择。")
        case "existingBaselineRequiresExplicitReset": L10n.text("现有同步基线与所选 Hub 设备不一致，已停止以避免重复计数。")
        case "invalidConfiguration": L10n.text("Hub 地址或设备选择无效，请重新验证。")
        case "invalidCredential", "credentialUnavailable", "unauthorized": L10n.text("Hub 密钥无效，请重新输入。")
        case "rateLimited": L10n.text("Hub 请求受限，请稍后重试。")
        case "credentialSaveFailed": L10n.text("无法安全保存 Hub 密钥。")
        default: L10n.text("Hub 配置失败，请检查连接后重试。")
        }
    }
}

@MainActor @Observable final class BetaBackend {
    static let shared = BetaBackend()
    var message = L10n.text("等待后台启动")
    var snapshot: BetaBackendStatus?
    var busy = false
    var requiresApproval = false
    var localOnly = UserDefaults.standard.bool(forKey: "betaViewLocal")
    var syncMessage: String {
        guard let sync = snapshot?.sync, sync.enabled else { return Identity.isNativeBeta2 ? L10n.text("Hub 只读未启用") : L10n.text("Hub 同步未启用") }
        if let error = sync.error { return error == "unauthorized" ? L10n.text("Hub 密钥需要检查") : error == "credentialUnavailable" ? L10n.text("请在“数据”设置中输入地址和密钥") : error == "rateLimited" ? L10n.text("Hub 请求受限，稍后重试") : L10n.text("Hub 离线 保留上次汇总") }
        if Identity.isNativeBeta2 {
            if sync.uploadEnabled == true {
                if sync.syncing { return L10n.text("正在同步 Hub…") }
                return sync.lastSuccess == nil ? L10n.text("等待首次上传") : L10n.text("Hub 已连接 多设备同步")
            }
            return L10n.text("Hub 只读已连接")
        }
        return sync.syncing ? L10n.text("正在同步 Hub…") : L10n.text("Hub 已连接 多设备同步")
    }
    func selectLocal(_ local: Bool) { localOnly = local; UserDefaults.standard.set(local, forKey: "betaViewLocal"); reconnect() }
    func configureHub(address: String = "", secret: String = "", deviceId: String = "", enabled: Bool,
                      uploadEnabled: Bool = false) async throws {
        guard let endpoint else { throw HubError.disconnected }
        var request = try endpoint.connection().request("api/beta/hub")
        request.httpMethod = "POST"; request.timeoutInterval = 70
        request.httpBody = try JSONSerialization.data(withJSONObject: ["address": address, "secret": secret,
                                                                  "deviceId": deviceId, "enabled": enabled,
                                                                  "uploadEnabled": uploadEnabled])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            let code = (try? JSONDecoder().decode(BetaHubErrorResponse.self, from: data).error) ?? "hubConfigurationFailed"
            throw BetaHubConfigurationError(code: code)
        }
        reconnect(); await poll()
    }
    var enabled = !UserDefaults.standard.bool(forKey: "betaBackgroundDisabled")
    @ObservationIgnored private let service = SMAppService.agent(plistName: Identity.servicePlist)
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
        guard ["refresh", "pause", "resume", "restart"].contains(action), !busy else { return }
        guard let endpoint else {
            message = L10n.text("等待后台连接…")
            reconnect()
            return
        }
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
                try BetaEndpoint.load(from: url)
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
            let configured = (backend.snapshot?.providers ?? []).filter { $0.provider == "codex" && !["notConfigured", "disabled"].contains($0.status) }
            if !configured.isEmpty {
            Section(L10n.text("账号额度")) {
                ForEach(configured, id: \.provider) { provider in
                    LabeledContent("Codex", value: quotaMessage(provider.status))
                }
            }
            }
            BetaHubSettings()

        }
    }
}
