import XCTest
@testable import MonitorCore

final class BetaEndpointTests: XCTestCase {
    private func endpoint(_ address: String, secret: String = String(repeating: "a", count: 64)) throws -> BetaEndpoint {
        let data = try JSONSerialization.data(withJSONObject: ["version": 1, "pid": 123,
            "session": "A9E60149-D2D8-41DC-8EB5-7A120AE386CE", "address": address, "secret": secret])
        return try JSONDecoder().decode(BetaEndpoint.self, from: data)
    }
    func testOnlyAuthenticatedLoopbackRootIsAccepted() throws {
        XCTAssertEqual(try endpoint("http://127.0.0.1:38123").connection().baseURL.host, "127.0.0.1")
        for address in ["https://127.0.0.1:80", "http://localhost:123", "http://192.0.2.1:123", "http://127.0.0.1", "http://127.0.0.1:123/api", "http://user@127.0.0.1:123", "http://127.0.0.1:123?x=1"] {
            XCTAssertThrowsError(try endpoint(address).connection(), address)
        }
        XCTAssertThrowsError(try endpoint("http://127.0.0.1:123", secret: "short").connection())
    }
    func testUnsupportedDescriptorFailsClosed() throws {
        let data = Data("{\"version\":2,\"pid\":0,\"session\":\"invalid\",\"address\":\"http://127.0.0.1:123\",\"secret\":\"\(String(repeating: "a", count: 64))\"}".utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(BetaEndpoint.self, from: data).connection())
    }
    func testPrivateEndpointFileRejectsSharedPermissionsAndSymlinks() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("endpoint.json")
        try JSONEncoder().encode(endpoint("http://127.0.0.1:38123")).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        XCTAssertEqual(try BetaEndpoint.load(from: file).pid, 123)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)
        XCTAssertThrowsError(try BetaEndpoint.load(from: file))
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        let link = directory.appendingPathComponent("link.json")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
        XCTAssertThrowsError(try BetaEndpoint.load(from: link))
    }
}
