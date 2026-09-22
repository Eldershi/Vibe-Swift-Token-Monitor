import XCTest
@testable import MonitorCore
@testable import TokenMonitorNative

final class GitHubUpdateTests: XCTestCase {
    func release(_ tag: String, draft: Bool = false, beta: Bool = false, url: String? = nil) throws -> GitHubRelease {
        let path = url ?? "https://github.com/Eldershi/Vibe-Swift-Token-Monitor/releases/download/\(tag)/appcast.xml"
        let object: [String: Any] = ["tag_name": tag, "draft": draft, "prerelease": beta,
                                   "assets": [["name": "appcast.xml", "browser_download_url": path]]]
        return try JSONDecoder().decode(GitHubRelease.self, from: JSONSerialization.data(withJSONObject: object))
    }
    func testStableReleaseComparisonNeverDowngradesBetaOrUsesDrafts() throws {
        XCTAssertFalse(try release("v0.5.1").isNewer(than: "0.5.2-beta.1"))
        XCTAssertTrue(try release("v0.5.2").isNewer(than: "0.5.2-beta.1"))
        XCTAssertFalse(try release("v0.5.2").isNewer(than: "0.5.2"))
        XCTAssertTrue(try release("v0.10.0").isNewer(than: "0.9.9"))
        XCTAssertFalse(try release("v0.6.0", draft: true).isNewer(than: "0.5.2"))
        XCTAssertFalse(try release("v0.6.0-beta.1", beta: true).isNewer(than: "0.5.2"))
        XCTAssertFalse(try release("v0.6.0-beta.1").isNewer(than: "0.5.2"))
        for invalid in ["", "0.5", "../1.0.0", "1.0.0-rc.1", "1.0.0-beta.0", "1.0.0-beta.-1", "99999999999999999999999.0.0"] {
            XCTAssertNil(ReleaseVersion(invalid))
        }
    }
    func testOnlyExactRepositoryAndReleaseFeedCanInstall() throws {
        XCTAssertNotNil(try release("v0.6.0").appcastURL)
        for url in ["http://github.com/Eldershi/Vibe-Swift-Token-Monitor/releases/download/v0.6.0/appcast.xml",
                    "https://github.com/other/repo/releases/download/v0.6.0/appcast.xml",
                    "https://github.com/Eldershi/Vibe-Swift-Token-Monitor/releases/download/v0.7.0/appcast.xml",
                    "https://github.com.evil.invalid/Eldershi/Vibe-Swift-Token-Monitor/releases/download/v0.6.0/appcast.xml"] {
            XCTAssertNil(try release("v0.6.0", url: url).appcastURL)
        }
    }
    func testNativeFeedIsSeparateFromLegacyIdentityAndRejectsOtherLocations() throws {
        let root = "https://github.com/Eldershi/Vibe-Swift-Token-Monitor/releases/download/v0.7.0/"
        func native(_ url: String) throws -> GitHubRelease {
            let value: [String: Any] = ["tag_name": "v0.7.0", "draft": false, "prerelease": false,
                "assets": [["name": "appcast-native.xml", "browser_download_url": url]]]
            return try JSONDecoder().decode(GitHubRelease.self, from: JSONSerialization.data(withJSONObject: value))
        }
        let current = try native(root + "appcast-native.xml")
        XCTAssertNotNil(current.nativeAppcastURL)
        XCTAssertNil(current.appcastURL)
        XCTAssertNil(try release("v0.7.0").nativeAppcastURL)
        for invalid in [root + "appcast.xml", root.replacingOccurrences(of: "https:", with: "http:") + "appcast-native.xml",
                        root.replacingOccurrences(of: "v0.7.0", with: "v0.6.0") + "appcast-native.xml",
                        root.replacingOccurrences(of: "Eldershi", with: "other") + "appcast-native.xml"] {
            XCTAssertNil(try native(invalid).nativeAppcastURL)
        }
    }
    @MainActor func testAutomaticCheckPreferenceDefaultsOffAndPersists() throws {
        let old = try JSONDecoder().decode(Preferences.self, from: Data(#"{"schemaVersion":3}"#.utf8))
        XCTAssertFalse(old.automaticallyCheckForUpdates)
        let preferences = RuntimePreferences(old)
        preferences.automaticallyCheckForUpdates = true
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = PreferencesFile(url: directory.appendingPathComponent("settings.json"))
        try file.save(preferences.snapshot)
        XCTAssertTrue(try file.load().automaticallyCheckForUpdates)
        preferences.automaticallyCheckForUpdates = false
        try file.save(preferences.snapshot)
        XCTAssertFalse(try file.load().automaticallyCheckForUpdates)
    }
    func testHTTPStatusFailuresAndSuccessfulDecoding() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [UpdateURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        for status in [200, 403, 404, 429, 500] {
            UpdateURLProtocol.status = status
            do {
                let result = try await GitHubReleaseClient.latest(using: session)
                XCTAssertEqual(status, 200)
                XCTAssertEqual(result.tag_name, "v0.6.0")
            } catch ReleaseCheckError.rateLimited { XCTAssertTrue([403, 429].contains(status)) }
            catch ReleaseCheckError.unavailable { XCTAssertTrue([404, 500].contains(status)) }
        }
    }
}
private final class UpdateURLProtocol: URLProtocol {
    static var status = 200
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        XCTAssertEqual(request.url, GitHubRelease.latestURL)
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"tag_name":"v0.6.0","draft":false,"prerelease":false,"assets":[]}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
