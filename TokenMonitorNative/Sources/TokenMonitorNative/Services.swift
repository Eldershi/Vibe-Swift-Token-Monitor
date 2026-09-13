import AppKit
import Security
import MonitorCore

enum Identity {
    static let bundleID = "local.tokenmonitor.native"
    static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Token Monitor Native", isDirectory: true)
    }
}
enum Keychain {
    static func load(address: String) throws -> String? {
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
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Identity.bundleID, kSecAttrAccount as String: address]
        let attributes = [kSecValueData as String: Data(secret.utf8)]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var add = query; add.merge(attributes) { _, new in new }
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(add as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw Failure(status: status) }
    }
    struct Failure: LocalizedError {
        let status: OSStatus
        var errorDescription: String? { "无法访问钥匙串（\(status)）。请解锁登录钥匙串后重试。" }
    }
}

protocol UpdateService { var description: String { get }; var canCheck: Bool { get } }
struct LocalUpdateService: UpdateService {
    let canCheck = false
    var description: String { "本地构建 · 尚未配置在线更新源" }
}
enum Backend {
    @MainActor static func open() {
        let url = URL(fileURLWithPath: "/Applications/Token Monitor.app")
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, _ in }
    }
}
