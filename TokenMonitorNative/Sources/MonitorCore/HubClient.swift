import Foundation

public struct HubConnection: Equatable, Sendable {
    public let baseURL: URL
    public let secret: String
    public init(address: String, secret: String) throws {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed),
              ["http", "https"].contains(components.scheme?.lowercased() ?? ""),
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil else { throw HubError.invalidURL }
        components.path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if !components.path.isEmpty { components.path = "/" + components.path }
        guard let url = components.url else { throw HubError.invalidURL }
        let cleanSecret = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanSecret.isEmpty, !cleanSecret.contains("\n"), !cleanSecret.contains("\r") else { throw HubError.invalidSecret }
        baseURL = url; self.secret = cleanSecret
    }
    public func request(_ endpoint: String) -> URLRequest {
        var request = URLRequest(url: baseURL.appendingPathComponent(endpoint))
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer " + secret, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }
}

private final class NoRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        // The credential belongs to exactly the configured Hub, never a redirect target.
        completionHandler(nil)
    }
}

public final class HubClient: @unchecked Sendable {
    public let connection: HubConnection
    private let session: URLSession
    private let lifecycleLock = NSLock()
    private var cancelled = false
    public init(connection: HubConnection, protocolClasses: [AnyClass]? = nil) {
        self.connection = connection
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil; config.httpCookieStorage = nil
        config.timeoutIntervalForRequest = 75
        config.timeoutIntervalForResource = 7 * 24 * 3600
        if let protocolClasses { config.protocolClasses = protocolClasses }
        session = URLSession(configuration: config, delegate: NoRedirects(), delegateQueue: nil)
    }
    deinit { session.invalidateAndCancel() }
    public func cancel() {
        lifecycleLock.withLock { cancelled = true }
        // Async URLSession APIs may create their task after entering the method.
        // Keep the session valid until deinit, so cancellation cannot race task
        // creation into an Objective-C exception. Closed clients never reopen.
        session.getAllTasks { tasks in tasks.forEach { $0.cancel() } }
    }
    private func checkActive() throws {
        try Task.checkCancellation()
        if lifecycleLock.withLock({ cancelled }) { throw CancellationError() }
    }
    private func validate(_ response: URLResponse, stream: Bool = false) throws {
        guard let response = response as? HTTPURLResponse else { throw HubError.disconnected }
        if response.statusCode == 401 || response.statusCode == 403 { throw HubError.unauthorized }
        if stream && [404, 405, 501].contains(response.statusCode) { throw HubError.unsupportedStream }
        guard (200..<300).contains(response.statusCode) else { throw HubError.http(response.statusCode) }
        if stream && response.mimeType != "text/event-stream" { throw HubError.unsupportedStream }
    }
    public func data(_ endpoint: String) async throws -> Data {
        try checkActive()
        let (data, response) = try await session.data(for: connection.request(endpoint))
        try checkActive()
        try validate(response)
        guard data.count <= 64 * 1024 * 1024 else { throw HubError.incompatible(L10n.text("响应过大")) }
        return data
    }
    public func data(_ endpoint: String, query: [URLQueryItem]) async throws -> Data {
        try checkActive()
        var request = connection.request(endpoint)
        guard let url = request.url, var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw HubError.invalidURL
        }
        parts.queryItems = query
        request.url = parts.url
        let (data, response) = try await session.data(for: request)
        try checkActive(); try validate(response)
        guard data.count <= 64 * 1024 * 1024 else { throw HubError.incompatible(L10n.text("响应过大")) }
        return data
    }
    public func send(_ endpoint: String, body: Data?) async throws -> Data {
        try checkActive()
        var request = connection.request(endpoint)
        request.timeoutInterval = 120
        if let body { request.httpMethod = "POST"; request.httpBody = body; request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let (data, response) = try await session.data(for: request)
        try checkActive(); try validate(response)
        guard data.count <= 16 * 1024 * 1024 else { throw HubError.incompatible(L10n.text("响应过大")) }
        return data
    }
    public func health() async throws -> Health {
        let data = try await data("api/health")
        guard let health = try? JSONDecoder().decode(Health.self, from: data), health.ok, health.role == "hub" else { throw HubError.incompatible(L10n.text("健康检查")) }
        return health
    }
    public func stats() async throws -> Stats { try Stats.decode(await data("api/stats")) }
    public func history() async throws -> History { try History.decode(await data("api/history")) }
    public func stream() -> AsyncThrowingStream<Stats, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try checkActive()
                    var request = connection.request("api/stats/stream")
                    request.timeoutInterval = 75
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    let (bytes, response) = try await session.bytes(for: request)
                    try checkActive()
                    try validate(response, stream: true)
                    var parser = SSEParser(), chunk = Data()
                    for try await byte in bytes {
                        try Task.checkCancellation()
                        chunk.append(byte)
                        if byte == 10 || byte == 13 || chunk.count >= 16_384 {
                            try checkActive()
                            for event in try parser.feed(chunk) {
                                if let stats = try event.stats() { continuation.yield(stats) }
                            }
                            chunk.removeAll(keepingCapacity: true)
                        }
                    }
                    throw HubError.disconnected
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
