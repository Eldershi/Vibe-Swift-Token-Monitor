import SwiftUI
import MonitorCore

struct BetaHubSettings: View {
    @Environment(\.settingsControlTint) private var controlTint
    @Bindable var backend = BetaBackend.shared
    @State private var address = ""
    @State private var secret = ""
    @State private var deviceID = ""
    @State private var devices: [Device] = []
    @State private var busy = false
    @State private var message = ""
    @State private var loadedConfiguration = false
    @State private var validatedAddress = ""
    @State private var validatedSecret = ""
    var body: some View {
        Form {
            Section("Hub") {
                LabeledContent("同步状态", value: backend.syncMessage)
                LabeledContent("最后成功同步", value: backend.snapshot?.sync?.lastSuccess.flatMap(DateCodec.parse)?.formatted(date: .abbreviated, time: .standard) ?? "尚未同步")
                Picker("查看数据", selection: Binding(get: { backend.localOnly }, set: { backend.selectLocal($0) })) {
                    Text("共享 Hub · 全部设备").tag(false)
                    Text("仅本机").tag(true)
                }.tint(controlTint).accentColor(controlTint)
                TextField("Hub 地址", text: $address).disabled(busy)
                SecureField("共享密钥", text: $secret).disabled(busy)
                Button("验证连接并读取设备") { Task { await validate() } }.disabled(busy || secret.isEmpty)
                if !devices.isEmpty {
                    Picker("此 Mac 对应的已有设备", selection: $deviceID) {
                        Text("请选择设备").tag("")
                        ForEach(devices) { Text($0.id).tag($0.id) }
                    }.tint(controlTint).accentColor(controlTint)
                    Button("保存并启用同步") { Task { await enable() } }.disabled(busy || deviceID.isEmpty)
                }
                if backend.snapshot?.sync?.enabled == true {
                    Button("停用 Hub 同步") { Task {
                        do { try await backend.configureHub(enabled: false) } catch { message = error.localizedDescription }
                    } }.disabled(busy)
                }
                if !message.isEmpty { Text(message).font(.caption) }

            }
        }.formStyle(.grouped)
            .onAppear { loadConfiguration() }
            .onChange(of: backend.snapshot?.sync?.address) { loadConfiguration() }
            .onChange(of: address) { if address != validatedAddress { devices = [] } }
            .onChange(of: secret) { if secret != validatedSecret { devices = [] } }
    }
    private func loadConfiguration() {
        guard !loadedConfiguration, let sync = backend.snapshot?.sync else { return }
        if address.isEmpty { address = sync.address }
        if deviceID.isEmpty { deviceID = sync.deviceId }
        loadedConfiguration = true
    }
    private func validate() async {
        busy = true; defer { busy = false }
        do {
            let connection = try HubConnection(address: address, secret: secret)
            let client = HubClient(connection: connection); defer { client.cancel() }
            _ = try await client.health()
            let stats = try await client.stats()
            validatedAddress = connection.baseURL.absoluteString; validatedSecret = secret
            address = validatedAddress
            devices = stats.devices
            message = "连接有效"
        } catch { message = error.localizedDescription; devices = [] }
    }
    private func enable() async {
        busy = true; defer { busy = false }
        do {
            try await backend.configureHub(address: address, secret: secret, deviceId: deviceID, enabled: true)
            secret = ""; validatedSecret = ""; devices = []; message = "已保存并启用"
        } catch { message = error.localizedDescription }
    }
}
