import Foundation

public struct BetaEndpoint: Codable, Equatable, Sendable {
    public let version: Int
    public let session: String
    public let pid: Int
    public let address: String
    public let secret: String
    public static func load(from url: URL) throws -> BetaEndpoint {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid(),
              (attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600,
              attributes[.type] as? FileAttributeType == .typeRegular else { throw HubError.disconnected }
        let endpoint = try JSONDecoder().decode(BetaEndpoint.self, from: Data(contentsOf: url))
        _ = try endpoint.connection()
        return endpoint
    }
    public func connection() throws -> HubConnection {
        guard version == 1, pid > 0, UUID(uuidString: session) != nil,
              let url = URLComponents(string: address), url.scheme == "http", url.host == "127.0.0.1",
              let port = url.port, (1...65535).contains(port), url.path.isEmpty,
              secret.count == 64, secret.allSatisfy({ $0.isHexDigit && $0.isASCII }) else {
            throw HubError.incompatible(L10n.text("本机后台连接信息"))
        }
        return try HubConnection(address: address, secret: secret)
    }
}

public struct BetaBackendStatus: Codable, Equatable, Sendable {
    public let version: String
    public let session: String
    public let paused: Bool
    public let lastSuccess: String?
    public let failure: String?
    public let providers: [BetaProviderStatus]?
    public let collecting: Bool
    public let pid: Int
    public let sync: BetaSyncStatus?
}

public struct BetaProviderStatus: Codable, Equatable, Sendable {
    public let provider: String
    public let status: String
}

public struct BetaSyncStatus: Codable, Equatable, Sendable {
    public let enabled: Bool
    public let uploadEnabled: Bool?
    public let configured: Bool
    public let address: String
    public let deviceId: String
    public let lastSuccess: String?
    public let error: String?
    public let syncing: Bool
}
