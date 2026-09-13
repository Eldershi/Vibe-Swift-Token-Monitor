import SwiftUI
import MonitorCore

struct SettingsView: View {
    @Bindable var store: AppStore
    @State private var address = ""
    @State private var secret = ""
    @State private var testing = false
    @State private var message: String?
    @State private var validated: (HubConnection, Health, Stats)?
    @State private var saved = false
    private let updates: any UpdateService = LocalUpdateService()
    var body: some View {
        TabView {
            if Identity.isBeta {
                Tab("后台", systemImage: "externaldrive") { BetaBackendSettings() }
                Tab("Hub", systemImage: "network") { BetaHubSettings() }
            } else {
            Tab("连接", systemImage: "network") {
                Form {
                    Section("连接到 Token Monitor Hub") {
                        TextField("Hub 地址", text: $address, prompt: Text("http://127.0.0.1:17321"))
                            .autocorrectionDisabled()
                        SecureField("共享密钥", text: $secret)
                        Text("从原应用的 Hub 设置中复制共享密钥。保存后安全存入本应用的 Keychain。").font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Button("测试连接") { test() }.disabled(testing || secret.isEmpty)
                            if testing { ProgressView().controlSize(.small) }
                            Spacer()
                            Button("保存连接") { save() }.disabled(validated == nil || testing || saved)
                        }
                        if let message { Text(message).font(.callout).textSelection(.enabled) }
                    }
                    Section {
                        Text("支持本机、局域网、Tailscale 地址和 HTTPS Hub。其他网络上的设备需先有可达的 Hub 地址。").font(.caption).foregroundStyle(.secondary)
                        if !Identity.isBeta { Button("打开 Token Monitor") { Backend.open() } }
                    }
                    if let error = store.preferencesError { Section("设置文件需要检查") { Text(error).textSelection(.enabled) } }
                }.formStyle(.grouped)
            }
            }
            Tab("首页", systemImage: "rectangle.grid.1x2") { HomeLayoutSettings(store: store) }
            Tab {
                Form {
                    Section("窗口") {
                        Toggle("启动时显示小窗口", isOn: $store.preferences.showPanelOnLaunch)
                        Toggle("小窗口置顶", isOn: $store.preferences.pinned)
                        Text("关闭窗口后仍可通过菜单栏打开。退出原生应用不会退出 Token Monitor 后台。").font(.caption).foregroundStyle(.secondary)
                    }
                    Section("外观与辅助功能") {
                        ThemeColorSettings(store: store)
                        Text("主题色用于图表、额度进度和交互强调。连接成功与过期状态仍使用绿色、橙色。外观、透明度与对比度跟随系统。").font(.caption).foregroundStyle(.secondary)
                    }
                }.formStyle(.grouped)
            } label: {
                Label { Text("通用") } icon: { InterfaceSymbols.gear }
            }
            Tab("关于", systemImage: "info.circle") {
                Form {
                    Section(Identity.name) {
                        LabeledContent("版本", value: (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "开发版本"))
                        LabeledContent("构建号", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "开发构建")
                        LabeledContent("更新方式", value: updates.description)
                        Text("通过随附安装脚本升级，可恢复上一版本。未来可接入独立签名更新源；当前未配置在线更新。").font(.caption).foregroundStyle(.secondary)
                    }
                    Section("Hub 兼容性") {
                        LabeledContent("连接状态", value: store.connectionDisplayStatus)
                        LabeledContent("接口基线", value: "Token Monitor v0.56.0")
                        if let build = store.health?.hubBuild {
                            LabeledContent("Hub 构建", value: build.coreBuildId ?? "未提供")
                            LabeledContent("Schema", value: build.schemaVersion.map(String.init) ?? "未提供")
                        }
                        if !Identity.isBeta { Button("打开 Token Monitor") { Backend.open() } }
                    }
                }.formStyle(.grouped).textSelection(.enabled)
            }
        }
        .padding(12)
        .foregroundStyle(.primary)
        .tint(.primary)
        .accentColor(.primary)
        .controlSize(.small)
        .environment(\.settingsControlTint, store.preferences.accentColor)
        .buttonStyle(SettingsActionButtonStyle(tint: store.preferences.accentColor))
        .toggleStyle(SettingsSwitchStyle(tint: store.preferences.accentColor))
        .onAppear {
            address = store.preferences.hubAddress
            let args = ProcessInfo.processInfo.arguments
            guard !Identity.isBeta, !args.contains("--smoke-test"), !args.contains("--preview-fixture") else { return }
            let initialAddress = address
            Task { @MainActor in
                do {
                    let stored = try await Task.detached(priority: .userInitiated) { try Keychain.load(address: initialAddress) }.value
                    if address == initialAddress, secret.isEmpty { secret = stored ?? "" }
                } catch { message = error.localizedDescription }
            }
        }
        .onChange(of: address) { invalidate() }
        .onChange(of: secret) { invalidate() }
        .onChange(of: store.preferences.showPanelOnLaunch) { store.savePreferences() }
        .onChange(of: store.preferences.homeSections) { store.savePreferences() }
        .onChange(of: store.preferences.hiddenHomeSections) { store.savePreferences() }
        .onChange(of: store.preferences.customThemeColor) { store.savePreferences() }
        .onChange(of: store.preferences.themeColor) { store.savePreferences() }
        .onChange(of: store.preferences.pinned) { store.savePreferences(); PanelController.shared.updatePin() }
    }
    private func invalidate() { validated = nil; message = nil; saved = false }
    private func test() {
        testing = true; validated = nil; message = nil
        let testedAddress = address, testedSecret = secret
        Task { @MainActor in
            defer { testing = false }
            do {
                let result = try await store.testConnection(address: testedAddress, secret: testedSecret)
                guard address == testedAddress, secret == testedSecret else { return }
                validated = result; message = "连接成功：已读取 \(result.2.devices.count) 台设备。点击“保存连接”开始同步。"
            } catch { message = error.localizedDescription }
        }
    }
    private func save() {
        guard let validated else { return }
        testing = true
        Task { @MainActor in
            defer { testing = false }
            do { try await store.saveConnection(validated); saved = true; message = "已保存连接，正在同步真实统计。" }
            catch { message = error.localizedDescription }
        }
    }
}

// Keep accent inheritance inside controls, away from Form labels and status text.
private struct SettingsControlTintKey: EnvironmentKey {
    static let defaultValue: Color? = nil
}
extension EnvironmentValues {
    var settingsControlTint: Color? {
        get { self[SettingsControlTintKey.self] }
        set { self[SettingsControlTintKey.self] = newValue }
    }
}
private struct SettingsActionButtonStyle: PrimitiveButtonStyle {
    let tint: Color?
    func makeBody(configuration: Configuration) -> some View {
        Button(configuration).buttonStyle(.bordered).tint(tint).accentColor(tint)
    }
}
private struct SettingsSwitchStyle: ToggleStyle {
    let tint: Color?
    func makeBody(configuration: Configuration) -> some View {
        Toggle(configuration).toggleStyle(.switch).tint(tint).accentColor(tint)
    }
}
