import SwiftUI
import ServiceManagement
import MonitorCore

@MainActor @Observable final class BetaBackend {
    static let shared = BetaBackend()
    var message = "等待后台启动"
    var snapshot: BetaBackendStatus?
    var busy = false
    var requiresApproval = false
    var localOnly = UserDefaults.standard.bool(forKey: "betaViewLocal")
    var syncMessage: String {
        guard let sync = snapshot?.sync, sync.enabled else { return "Hub 同步未启用" }
        if let error = sync.error { return error == "unauthorized" ? "Hub 密钥需要检查" : error == "credentialUnavailable" ? "请在 Hub 设置中输入地址和密钥" : error == "rateLimited" ? "Hub 请求受限，稍后重试" : "Hub 离线 · 保留上次汇总" }
        return sync.syncing ? "正在同步 Hub…" : "Hub 已连接 · 多设备同步"
    }
    func selectLocal(_ local: Bool) { localOnly = local; UserDefaults.standard.set(local, forKey: "betaViewLocal"); reconnect() }
    func configureHub(address: String = "", secret: String = "", deviceId: String = "", enabled: Bool) async throws {
        guard let endpoint else { throw HubError.disconnected }
        var request = try endpoint.connection().request("api/beta/hub")
        request.httpMethod = "POST"; request.timeoutInterval = 70
        request.httpBody = try JSONSerialization.data(withJSONObject: ["address": address, "secret": secret, "deviceId": deviceId, "enabled": enabled])
        let (_, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw HubError.incompatible("Hub 配置失败：检查本机历史、设备身份和连接") }
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
        guard let value = snapshot?.lastSuccess, let date = DateCodec.parse(value) else { return "暂无成功采集时间" }
        return date.formatted(date: .abbreviated, time: .standard)
    }
    func start() {
        guard Identity.isBeta, monitor == nil else { return }
        if enabled { message = "正在准备后台…" } else { message = "后台已停用" }
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
            message = requiresApproval ? "请在系统设置中允许 Beta 后台运行" : "正在启动后台…"
        } catch { message = "后台注册失败，请检查系统的登录项与扩展设置" }
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
            message = "后台已停用"; disconnected?()
        } catch { message = "未能停用后台，请在系统设置中检查后台项目" }
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
            if action == "restart" { connectedSession = nil; message = "正在重启后台…" }
            await poll()
        } catch { message = "后台操作未完成，请稍后重试" }
    }
    private func poll() async {
        guard enabled else { return }
        requiresApproval = service.status == .requiresApproval
        if requiresApproval { message = "请在系统设置中允许 Beta 后台运行"; return }
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
            message = state.paused ? "采集已暂停" : state.collecting ? "正在采集本机数据…" : state.failure != nil ? "采集失败，将自动重试" : "后台运行中"
            let identity = value.session + String(localOnly) + String(state.sync?.enabled ?? false)
            if connectedSession != identity {
                connectedSession = identity
                let source = localOnly ? try HubConnection(address: value.address + "/local", secret: value.secret) : connection
                connected?(source)
            }
            AppStore.shared.applyBetaSyncStatus()
        } catch {
            if connectedSession != nil { connectedSession = nil; disconnected?() }
            endpoint = nil; message = "等待后台连接…"
        }
    }
}

struct BetaBackendSettings: View {
    @Bindable var backend = BetaBackend.shared
    @State private var authorizingClaude = false
    @State private var authorizationMessage: String?
    private func quotaMessage(_ status: String) -> String {
        switch status {
        case "ok": "已获取"
        case "notConfigured": "未配置登录"
        case "unauthorized": "登录失效，请在原工具重新登录"
        case "sourceRateLimited": "请求受限，稍后自动重试"
        default: "暂不可用，保留用量统计"
        }
    }
    var body: some View {
        Form {
            Section("本机独立采集 · Beta") {
                LabeledContent("后台状态", value: backend.message)
                    .accessibilityElement(children: .ignore).accessibilityLabel("后台状态").accessibilityValue(backend.message)
                LabeledContent("最近成功采集", value: backend.lastSuccess)
                    .accessibilityElement(children: .ignore).accessibilityLabel("最近成功采集").accessibilityValue(backend.lastSuccess)
                Text("支持 Codex 和 Claude Code。本机日志用于恢复历史。共享 Hub 的连接与设备绑定在“Hub”中设置。")
                    .font(.caption).foregroundStyle(.secondary)
                if backend.requiresApproval { Button("打开系统后台设置") { backend.openSystemSettings() } }
                if backend.enabled {
                    HStack {
                        Button("立即刷新") { Task { await backend.command("refresh") } }
                        Button(backend.snapshot?.paused == true ? "恢复采集" : "暂停采集") {
                            Task { await backend.command(backend.snapshot?.paused == true ? "resume" : "pause") }
                        }
                        Button("重启后台") { Task { await backend.command("restart") } }
                    }.disabled(backend.busy || backend.snapshot == nil)
                    Button("停用后台") { Task { await backend.disable() } }.disabled(backend.busy)
                } else { Button("启用后台") { backend.enable() } }
            }
            Section("账号额度") {
                if backend.snapshot?.providers?.contains(where: { $0.provider == "claude" && $0.status == "unauthorized" }) == true {
                    Button("授权读取 Claude 额度") { Task {
                        authorizingClaude = true; defer { authorizingClaude = false }
                        do {
                            try await Task.detached { try Keychain.authorizeClaude() }.value
                            authorizationMessage = "已完成访问请求，正在重新读取额度。"
                            await backend.command("refresh")
                        } catch { authorizationMessage = "未获得钥匙串访问权限；日志统计仍可继续。" }
                    } }.disabled(authorizingClaude)
                }
                if let authorizationMessage { Text(authorizationMessage).font(.caption) }

                ForEach(backend.snapshot?.providers ?? [], id: \.provider) { provider in
                    LabeledContent(provider.provider == "codex" ? "Codex" : "Claude Code", value: quotaMessage(provider.status))
                }
                Text("只读取原工具已有的登录信息。登录失效时，请在 Codex 或 Claude Code 中重新登录，再点击立即刷新。Beta 不会刷新账号凭据或发起模型对话。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("后台运行") {
                Text("退出 Beta 界面后仍继续采集，并在登录时恢复。暂停会保留后台连接；停用会注销后台服务。原版可保留在仅本机模式用于参考，避免同时向共享 Hub 上传。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
    }
}
