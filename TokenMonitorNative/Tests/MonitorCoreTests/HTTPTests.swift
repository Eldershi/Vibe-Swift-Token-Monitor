import XCTest
@testable import MonitorCore

final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    static var handler: ((URLRequest) -> (Int, String, [Data]))!
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let (code, type, chunks) = Self.handler(request)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url:request.url!,statusCode:code,httpVersion:"HTTP/1.1",headerFields:["Content-Type":type])!, cacheStoragePolicy:.notAllowed)
        for chunk in chunks { client?.urlProtocol(self,didLoad:chunk) }
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
final class HTTPTests: XCTestCase {
    func client() throws -> HubClient { HubClient(connection:try HubConnection(address:"http://test.invalid",secret:"fixture-secret"),protocolClasses:[MockURLProtocol.self]) }
    func fixture(_ name: String) throws -> Data { try Data(contentsOf:Bundle.module.url(forResource:name,withExtension:"json",subdirectory:"Fixtures")!) }
    func testHealthAndAuthenticatedStats() async throws {
        let health = try fixture("health"), stats = try fixture("stats")
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField:"Authorization"),"Bearer fixture-secret")
            return (200,"application/json",[request.url!.path == "/api/health" ? health : stats])
        }
        let c = try client(); defer { c.cancel() }
        let h = try await c.health(); XCTAssertTrue(h.ok)
        let s = try await c.stats(); XCTAssertEqual(s.devices.count,2)
    }
    func testWrongKeyStopsWithAuthError() async throws {
        MockURLProtocol.handler = { _ in (401,"application/json",[Data("{}".utf8)]) }
        let c = try client(); defer { c.cancel() }
        do { _ = try await c.stats(); XCTFail("accepted wrong key") } catch { XCTAssertEqual(error as? HubError,.unauthorized) }
        do { for try await _ in c.stream() {} ; XCTFail("accepted SSE wrong key") } catch { XCTAssertEqual(error as? HubError,.unauthorized) }
    }
    func testUnsupportedStreamIsDistinctFromAuthAndNetwork() async throws {
        for code in [404,405,501,200] {
            MockURLProtocol.handler = { _ in (code,"application/json",[Data("{}".utf8)]) }
            let c = try client(); defer { c.cancel() }
            do { for try await _ in c.stream() {}; XCTFail("accepted unsupported SSE") } catch { XCTAssertEqual(error as? HubError,.unsupportedStream) }
        }
    }
    func testStreamDeliversSnapshotThenSignalsDisconnect() async throws {
        let obj = try JSONSerialization.jsonObject(with:fixture("stats"))
        let json = try JSONSerialization.data(withJSONObject:["stats":obj])
        var wire = Data(": hb\n\nevent: snapshot\ndata: ".utf8); wire.append(json); wire.append(Data("\n\n".utf8))
        MockURLProtocol.handler = { _ in (200,"text/event-stream",[wire]) }
        let c = try client(); defer { c.cancel() }; var count = 0
        do { for try await snapshot in c.stream() { count += 1; XCTAssertEqual(snapshot.devices.count,2) } } catch { XCTAssertEqual(error as? HubError,.disconnected) }
        XCTAssertEqual(count,1)
    }
    func testInvalidHealthAndServerFailure() async throws {
        let c = try client(); defer { c.cancel() }
        MockURLProtocol.handler = { _ in (200,"application/json",[Data(#"{"ok":true,"role":"unrelated"}"#.utf8)]) }
        do { _ = try await c.health(); XCTFail() } catch { guard case .incompatible = error as? HubError else { return XCTFail("wrong error") } }
        MockURLProtocol.handler = { _ in (503,"application/json",[]) }
        do { _ = try await c.stats(); XCTFail() } catch { XCTAssertEqual(error as? HubError,.http(503)) }
    }
}
