import AppKit
import Security
import MonitorCore

enum Identity {
    static var isBeta: Bool { Bundle.main.bundleIdentifier == "local.tokenmonitor.native.beta" }
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "TokenMonitorReleaseVersion") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? L10n.text("开发版本")
    }
    static var bundleID: String { isBeta ? "local.tokenmonitor.native.beta" : "local.tokenmonitor.native" }
    static var name: String { isBeta ? "Token Monitor Native Beta" : "Token Monitor Native" }
    static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent(name, isDirectory: true)
    }
}
enum Keychain {
    static func load(address: String) throws -> String? {
        guard !Identity.isBeta else { throw Failure(status: errSecParam) }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Identity.bundleID, kSecAttrAccount as String: address,
            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else { throw Failure(status: status) }
        return String(data: data, encoding: .utf8)
    }
    static func save(_ secret: String, address: String) throws {
        guard !Identity.isBeta else { throw Failure(status: errSecParam) }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Identity.bundleID, kSecAttrAccount as String: address]
        let attributes: [String: Any] = [kSecValueData as String: Data(secret.utf8)]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var add = query; add.merge(attributes) { _, new in new }
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(add as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw Failure(status: status) }
    }
    static func authorizeClaude() throws {
        let process = Process()
        process.executableURL = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/TokenMonitorBackend")
        process.arguments = ["--authorize-claude"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run(); process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw Failure(status: errSecAuthFailed) }
    }
    struct Failure: LocalizedError {
        let status: OSStatus
        var errorDescription: String? { L10n.text("无法访问钥匙串（%@）。请解锁登录钥匙串后重试。", String(describing: status)) }
    }
}

protocol UpdateService { var description: String { get }; var canCheck: Bool { get } }
struct LocalUpdateService: UpdateService {
    let canCheck = false
    var description: String { L10n.text("本地构建 · 尚未配置在线更新源") }
}
enum Backend {
    @MainActor static func open() {
        guard !Identity.isBeta else { return }
        let url = URL(fileURLWithPath: "/Applications/Token Monitor.app")
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, _ in }
    }
}
