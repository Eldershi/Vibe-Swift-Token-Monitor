import Foundation

public struct ReleaseVersion: Comparable, Equatable, Sendable {
    let major: Int, minor: Int, patch: Int
    let beta: Int?
    public init?(_ text: String) {
        let value = text.hasPrefix("v") ? String(text.dropFirst()) : text
        let parts = value.components(separatedBy: "-beta.")
        guard parts.count <= 2 else { return nil }
        let numbers = parts[0].split(separator: ".", omittingEmptySubsequences: false)
        guard numbers.count == 3,
              numbers.allSatisfy({ !$0.isEmpty && $0.allSatisfy({ $0.isASCII && $0.isNumber }) }),
              let major = Int(numbers[0]), let minor = Int(numbers[1]), let patch = Int(numbers[2]) else { return nil }
        self.major = major; self.minor = minor; self.patch = patch
        if parts.count == 2 {
            guard let beta = Int(parts[1]), beta > 0, parts[1].allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
            self.beta = beta
        } else { beta = nil }
    }
    public static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }
        switch (lhs.beta, rhs.beta) {
        case (nil, _): return false
        case (_, nil): return true
        case let (a?, b?): return a < b
        }
    }
}

public struct GitHubRelease: Decodable, Sendable {
    public static let repository = "Eldershi/Vibe-Swift-Token-Monitor"
    public static let latestURL = URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!
    public static let releasesURL = URL(string: "https://github.com/\(repository)/releases")!
    public let tag_name: String
    public let draft: Bool
    public let prerelease: Bool
    public let assets: [Asset]
    public struct Asset: Decodable, Sendable {
        public let name: String
        public let browser_download_url: URL
    }
    public func isNewer(than current: String) -> Bool {
        guard !draft, !prerelease, let remote = ReleaseVersion(tag_name), remote.beta == nil,
              let local = ReleaseVersion(current) else { return false }
        return local < remote
    }
    public var appcastURL: URL? {
        let expected = URL(string: "https://github.com/\(Self.repository)/releases/download/")!
            .appendingPathComponent(tag_name).appendingPathComponent("appcast.xml")
        return assets.first { $0.name == "appcast.xml" && $0.browser_download_url == expected }?.browser_download_url
    }
}

public enum ReleaseCheckError: Error { case rateLimited, unavailable }
public enum GitHubReleaseClient {
    public static func latest(using session: URLSession) async throws -> GitHubRelease {
        var request = URLRequest(url: GitHubRelease.latestURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("TokenMonitorNative", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw ReleaseCheckError.unavailable }
        if [403, 429].contains(http.statusCode) { throw ReleaseCheckError.rateLimited }
        guard http.statusCode == 200 else { throw ReleaseCheckError.unavailable }
        return try JSONDecoder().decode(GitHubRelease.self, from: data)
    }
}
