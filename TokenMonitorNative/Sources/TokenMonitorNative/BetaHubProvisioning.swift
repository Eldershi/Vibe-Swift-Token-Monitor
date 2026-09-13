import Foundation

/// Legacy flags remain recognizable but never import credentials from Keychain.
@MainActor enum BetaHubProvisioning {
    static func run(enable: Bool) async -> Int32 {
        fputs("请在 Beta 设置的 Hub 页面手动输入地址和密钥。\n", stderr)
        return 1
    }
}
