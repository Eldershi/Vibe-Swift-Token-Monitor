import Foundation
import Network
import Security
import Darwin
import NativeBackendCore

private final class NoRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

private struct HubConfig: Codable {
    var enabled: Bool
    var address: String
    var secret: String
    var deviceId: String
    var uploadEnabled: Bool?
}

private final class CodexScanCache {
    private struct Entry { let size: Int; let modified: Date; let events: [NativeUsageEvent] }
    private var files: [URL: Entry] = [:]
    func scan(roots: [URL]) throws -> [NativeUsageEvent] {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey]
        var present = Set<URL>()
        for root in roots {
        guard let iterator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: Array(keys)) else { continue }
        for case let url as URL in iterator where url.pathExtension == "jsonl" {
            let info = try url.resourceValues(forKeys: keys)
            guard info.isRegularFile == true, info.isSymbolicLink != true,
                  let size = info.fileSize,
                  let modified = info.contentModificationDate else { continue }
            present.insert(url)
            if let old = files[url], old.size == size, old.modified == modified { continue }
            files[url] = Entry(size: size, modified: modified, events: try CodexScanner.scanFile(url))
        }
        }
        files = files.filter { present.contains($0.key) }
        return files.values.flatMap(\.events).sorted { $0.timestamp < $1.timestamp }
    }
}

final class NativeService: @unchecked Sendable {
    private let directory: URL
    private let queue = DispatchQueue(label: "local.tokenmonitor.native.beta2.backend")
    private let listener: NWListener
    private let http = URLSession(configuration: .ephemeral, delegate: NoRedirects(), delegateQueue: nil)
    private let session = UUID().uuidString.lowercased()
    private let secret: String
    private var config: HubConfig?
    private var paused = false
    private var stats = Data() { didSet { localPricingCache = nil } }
    private var history = Data()
    private var localConversion = Data()
    private var remoteStats: Data? { didSet { remotePricingCache = nil } }
    private var remoteHistory: Data?
    private var remoteDevices: Data? { didSet { remotePricingCache = nil } }
    private var localPricingCache: Data?
    private var remotePricingCache: (stats: Data, devices: Data)?
    private var conversionChoiceID: String?
    private var quotaCollecting = false
    private var quotaUploading = false
    private var quotaNextCheck = Date.distantPast
    private var quotaError: String?
    private var quotaState: [String: Any] = [:]
    private var cycleState: [String: Any] = [:]
    private var quotaHistoryState: [String: Any] = [:]
    private var cycleFetching = false
    private var quotaHistoryFetching = false
    private var cycleNextCheck = Date.distantPast
    private var cycleCapability = false
    private var fetchingRemote = false
    private var lastSuccess: String?
    private var syncSuccess: String?
    private var failure: String?
    private var readError: String?
    private var uploadError: String?
    private var uploadSuccess: String?
    private var handoff: HubHandoff?
    private var establishingHandoff = false
    private var uploading = false
    private var latestEvents: [NativeUsageEvent] = [] {
        didSet { localPricingCache = nil; remotePricingCache = nil }
    }
    private var scanning = false
    private var timer: DispatchSourceTimer?
    private let scanCache = CodexScanCache()
    private let deviceID: String

    init(directory: URL) throws {
        self.directory = directory
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
        listener = try NWListener(using: parameters, on: .any)
        let random = (0..<32).map { _ -> UInt8 in
            var value: UInt8 = 0
            guard SecRandomCopyBytes(kSecRandomDefault, 1, &value) == errSecSuccess else { fatalError("random unavailable") }
            return value
        }
        secret = random.map { String(format: "%02x", $0) }.joined()
        let settings = try Self.readJSON(directory.appendingPathComponent("backend-config.json"))
        paused = settings?["paused"] as? Bool == true
        deviceID = settings?["deviceId"] as? String ?? UUID().uuidString.lowercased()
        if let hub = try Self.readJSON(directory.appendingPathComponent("hub-config.json")),
           let data = try? JSONSerialization.data(withJSONObject: hub) {
            config = try? JSONDecoder().decode(HubConfig.self, from: data)
        }
        conversionChoiceID = (try Self.readJSON(directory.appendingPathComponent("conversion-config.json")))?["choiceId"] as? String
        quotaState = try Self.readJSON(directory.appendingPathComponent("quota-outbox.json")) ?? [:]
        cycleState = try Self.readJSON(directory.appendingPathComponent("quota-cycles.json")) ?? [:]
        quotaHistoryState = try Self.readJSON(directory.appendingPathComponent("quota-history.json")) ?? [:]
        let handoffFile = directory.appendingPathComponent("hub-handoff.json")
        if FileManager.default.fileExists(atPath: handoffFile.path) {
            handoff = try HubHandoff(saved: Data(contentsOf: handoffFile))
        }
        try Self.writeJSON(["paused": paused, "deviceId": deviceID], to: directory.appendingPathComponent("backend-config.json"))
        let empty = try NativeSnapshot.make(events: [], deviceID: deviceID)
        stats = empty.stats; history = empty.history
        localConversion = try empty.conversion(deviceID: deviceID, local: true)
    }

    func start() throws {
        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            if case .ready = state, let port = self.listener.port?.rawValue {
                do {
                    try Self.writeJSON(["version": 1, "session": self.session, "pid": Int(getpid()),
                                        "address": "http://127.0.0.1:\(port)", "secret": self.secret],
                                       to: self.directory.appendingPathComponent("endpoint.json"))
                } catch { fputs("Native endpoint write failed\n", stderr); exit(1) }
                self.refresh()
                self.flushUpload()
                let timer = DispatchSource.makeTimerSource(queue: self.queue)
                timer.schedule(deadline: .now() + 20, repeating: 20)
                timer.setEventHandler { [weak self] in self?.refresh() }
                self.timer = timer; timer.resume()
            }
        }
        listener.newConnectionHandler = { [weak self] connection in self?.serve(connection) }
        listener.start(queue: queue)
    }

    private func refresh() {
        if !paused && !scanning {
            scanning = true
            DispatchQueue.global(qos: .utility).async { [weak self] in
                guard let self else { return }
                do {
                    let home = ProcessInfo.processInfo.environment["TOKEN_MONITOR_BETA2_CODEX_ROOT"]
                        .map { URL(fileURLWithPath: $0, isDirectory: true) }
                        ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
                    let events = try self.scanCache.scan(roots: [home.appendingPathComponent("sessions"), home.appendingPathComponent("archived_sessions")])
                    let snapshot = try NativeSnapshot.make(events: events, deviceID: self.deviceID)
                    self.queue.async {
                        self.stats = self.withLocalQuota(snapshot.stats); self.history = snapshot.history
                        self.localConversion = (try? snapshot.conversion(deviceID: self.deviceID, local: true)) ?? self.localConversion
                        self.lastSuccess = Self.now(); self.failure = nil; self.scanning = false
                        self.latestEvents = events
                        self.syncLocal()
                    }
                } catch {
                    self.queue.async { self.failure = "collectionFailed"; self.scanning = false }
                }
            }
        }
        guard let config, config.enabled else { return }
        fetchRemote(config)
        refreshQuota(config)
        fetchCycles(config)
        flushUpload()
    }

    private func fetchRemote(_ hub: HubConfig) {
        guard !fetchingRemote else { return }
        guard let url = Self.baseURL(hub) else {
            readError = "invalidConfiguration"; return
        }
        fetchingRemote = true
        let base = url.absoluteString.hasSuffix("/") ? url : url.appendingPathComponent("")
        let endpoints = ["api/stats", "api/history", "api/devices"]
        let group = DispatchGroup()
        var outputs: [String: Data] = [:]
        var failed = false
        let resultQueue = DispatchQueue(label: "beta2.hub.fetch")
        for endpoint in endpoints {
            var request = URLRequest(url: base.appendingPathComponent(endpoint))
            request.timeoutInterval = 15
            request.setValue("Bearer \(hub.secret)", forHTTPHeaderField: "Authorization")
            group.enter()
            http.dataTask(with: request) { data, response, _ in
                resultQueue.sync {
                    if let response = response as? HTTPURLResponse, response.statusCode == 200,
                       let data, data.count <= 64 * 1024 * 1024 { outputs[endpoint] = data }
                    else { failed = true }
                }
                group.leave()
            }.resume()
        }
        group.notify(queue: queue) { [weak self] in
            guard let self else { return }
            self.fetchingRemote = false
            guard self.config?.address == hub.address, self.config?.secret == hub.secret else { return }
            if failed || outputs.count != 3 { self.readError = "hubUnavailable"; return }
            self.remoteStats = outputs["api/stats"]
            self.remoteHistory = outputs["api/history"]
            self.remoteDevices = outputs["api/devices"]
            self.syncSuccess = Self.now(); self.readError = nil
        }
    }

    private func syncLocal() {
        guard let config, config.enabled, config.uploadEnabled == true, !paused,
              lastSuccess != nil else { return }
        guard var handoff else { establishHandoff(config); return }
        guard handoff.address == config.address, handoff.deviceID == config.deviceId else {
            uploadError = "existingBaselineRequiresExplicitReset"; return
        }
        do {
            let local = try NativeSnapshot.make(events: latestEvents, deviceID: config.deviceId,
                                                hostname: handoff.hostname)
            if try handoff.advance(localData: local.deviceRecord) {
                try Self.writeData(handoff.saved(), to: directory.appendingPathComponent("hub-handoff.json"))
            }
            self.handoff = handoff
            flushUpload()
        } catch { uploadError = "baselineSaveFailed" }
    }

    private func establishHandoff(_ hub: HubConfig) {
        guard !establishingHandoff else { return }
        guard let url = Self.remoteURL(hub, path: "api/devices") else { uploadError = "invalidConfiguration"; return }
        establishingHandoff = true
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("Bearer \(hub.secret)", forHTTPHeaderField: "Authorization")
        http.dataTask(with: request) { [weak self] data, response, _ in
            guard let self else { return }
            self.queue.async {
                self.establishingHandoff = false
                guard self.config?.address == hub.address, self.config?.deviceId == hub.deviceId,
                      self.config?.uploadEnabled == true else { return }
                guard (response as? HTTPURLResponse)?.statusCode == 200, let data,
                      let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let devices = body["devices"] as? [[String: Any]] else {
                    self.uploadError = "hubUnavailable"; return
                }
                let matches = devices.filter { $0["deviceId"] as? String == hub.deviceId }
                guard matches.count == 1, let remote = matches.first,
                      let remoteHostname = remote["hostname"] as? String,
                      Self.localHostAliases().contains(remoteHostname),
                      remote["agentRuntime"] as? String == "native-beta",
                      let stamp = remote["updatedAt"] as? String,
                      let cutoff = Self.date(stamp), cutoff <= Date().addingTimeInterval(60) else {
                    self.uploadError = "deviceNotMatched"; return
                }
                do {
                    let remoteData = try JSONSerialization.data(withJSONObject: remote, options: [.sortedKeys])
                    let atCutoff = try NativeSnapshot.make(events: self.latestEvents.filter { $0.timestamp <= cutoff },
                                                           deviceID: hub.deviceId, now: cutoff,
                                                           hostname: remoteHostname)
                    let handoff = try HubHandoff(address: hub.address, deviceID: hub.deviceId,
                                                  remote: remoteData, localAtRemoteUpdate: atCutoff.deviceRecord)
                    try Self.writeData(remoteData, to: self.directory.appendingPathComponent("hub-remote-before-handoff.json"))
                    try Self.writeData(handoff.saved(), to: self.directory.appendingPathComponent("hub-handoff.json"))
                    self.handoff = handoff
                    self.uploadError = nil
                    self.syncLocal()
                } catch { self.uploadError = "baselineSaveFailed" }
            }
        }.resume()
    }

    private func flushUpload() {
        guard let config, config.enabled, config.uploadEnabled == true, !uploading,
              let handoff, handoff.pendingUpload else { return }
        guard let url = Self.remoteURL(config, path: "api/ingest"),
              let payload = try? handoff.upload() else { uploadError = "invalidConfiguration"; return }
        uploading = true
        var request = URLRequest(url: url)
        request.httpMethod = "POST"; request.httpBody = payload; request.timeoutInterval = 30
        request.setValue("Bearer \(config.secret)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        http.dataTask(with: request) { [weak self] data, response, _ in
            guard let self else { return }
            self.queue.async {
                self.uploading = false
                guard self.config?.address == config.address, self.config?.deviceId == config.deviceId else { return }
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                guard code == 200, let data,
                      let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      value["ok"] as? Bool == true, value["deviceId"] as? String == config.deviceId else {
                    self.uploadError = code == 401 ? "unauthorized" : code == 429 ? "rateLimited" : "hubUnavailable"
                    return
                }
                self.uploadSuccess = Self.now(); self.uploadError = nil
                if var current = self.handoff, (try? current.upload()) == payload {
                    current.acknowledged()
                    do {
                        try Self.writeData(current.saved(), to: self.directory.appendingPathComponent("hub-handoff.json"))
                        self.handoff = current
                    } catch { self.uploadError = "baselineSaveFailed" }
                }
                self.fetchRemote(config)
                self.flushUpload()
            }
        }.resume()
    }

    private static func remoteURL(_ config: HubConfig, path: String) -> URL? {
        baseURL(config)?.appendingPathComponent(path)
    }

    private static func baseURL(_ config: HubConfig) -> URL? {
        guard let url = URL(string: config.address),
              url.scheme == "https" ||
                (ProcessInfo.processInfo.environment["TOKEN_MONITOR_BETA2_DIR"] != nil &&
                 url.scheme == "http" && url.host == "127.0.0.1"), url.host != nil,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else { return nil }
        return url
    }

    private static func date(_ stamp: String) -> Date? {
        let format = ISO8601DateFormatter(); format.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return format.date(from: stamp) ?? ISO8601DateFormatter().date(from: stamp)
    }

    private static func localHostAliases() -> Set<String> {
        var name = [CChar](repeating: 0, count: 256)
        let systemName = name.withUnsafeMutableBufferPointer { buffer -> String in
            guard let base = buffer.baseAddress, gethostname(base, buffer.count) == 0 else { return "" }
            return String(cString: base)
        }
        return [ProcessInfo.processInfo.hostName, systemName]
    }


    private func scope(_ hub: HubConfig) -> String {
        NativeQuotaObservation.hash(hub.address + "\n" + hub.deviceId + "\n" + hub.secret)
    }
    private func withLocalQuota(_ data: Data) -> Data {
        guard var value = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let latest = quotaState["latest"] as? [String: Any] else { return data }
        value["limits"] = ["providers": [latest]]
        return (try? JSONSerialization.data(withJSONObject: value)) ?? data
    }
    private func refreshQuota(_ hub: HubConfig) {
        guard !paused, hub.uploadEnabled == true, let handoff,
              handoff.address == hub.address, handoff.deviceID == hub.deviceId else { return }
        flushQuota(hub)
        guard !quotaCollecting, Date() >= quotaNextCheck else { return }
        if let previousScope = quotaState["scope"] as? String, previousScope != scope(hub),
           !(quotaState["pending"] as? [[String: Any]] ?? []).isEmpty {
            quotaError = "quotaDestinationChanged"; return
        }
        guard (quotaState["pending"] as? [[String: Any]] ?? []).count < 2016 else {
            quotaError = "quotaQueueFull"; return
        }
        quotaNextCheck = Date().addingTimeInterval(300)
        do {
            let env = ProcessInfo.processInfo.environment
            let root = env["TOKEN_MONITOR_BETA2_CODEX_ROOT"] ?? env["CODEX_HOME"]
                ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex").path
            // Test backends never consult real credentials unless their fixture root supplies them.
            guard env["TOKEN_MONITOR_BETA2_DIR"] == nil || env["TOKEN_MONITOR_BETA2_CODEX_ROOT"] != nil else { return }
            let identity = try NativeQuotaObservation.identity(auth: Data(contentsOf: URL(fileURLWithPath: root).appendingPathComponent("auth.json")))
            var request = URLRequest(url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!)
            request.timeoutInterval = 25; request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            request.setValue("Bearer \(identity.accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue(identity.accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
            request.setValue("TokenMonitor/0.7.1", forHTTPHeaderField: "User-Agent")
            if identity.fedramp { request.setValue("true", forHTTPHeaderField: "X-OpenAI-Fedramp") }
            let requestedAt = Date()
            quotaCollecting = true
            http.dataTask(with: request) { [weak self] data, response, _ in
                guard let self else { return }
                self.queue.async {
                    self.quotaCollecting = false
                    guard self.config.map({ self.scope($0) }) == self.scope(hub), !self.paused else { return }
                    guard let response = response as? HTTPURLResponse, response.statusCode == 200,
                          let data, data.count <= 1_048_576,
                          (Int(response.value(forHTTPHeaderField: "Age") ?? "0") ?? 0) == 0 else {
                        let code = (response as? HTTPURLResponse)?.statusCode
                        self.quotaError = code == 401 || code == 403 ? "unauthorized" : code == 429 ? "sourceRateLimited" : "quotaUnavailable"; return
                    }
                    do {
                        let provider = try NativeQuotaObservation.provider(payload: data, identity: identity, observedAt: requestedAt)
                        var next = self.quotaState
                        var pending = next["pending"] as? [[String: Any]] ?? []
                        let id = NativeQuotaObservation.hash(String(decoding: try JSONSerialization.data(withJSONObject: provider, options: [.sortedKeys]), as: UTF8.self))
                        pending.append(["id": id, "provider": provider])
                        next["scope"] = self.scope(hub); next["pending"] = pending; next["latest"] = provider
                        try Self.writeJSON(next, to: self.directory.appendingPathComponent("quota-outbox.json"))
                        self.quotaState = next; self.quotaError = nil
                        self.stats = self.withLocalQuota(self.stats)
                        self.flushQuota(hub)
                    } catch { self.quotaError = "quotaObservationSaveFailed" }
                }
            }.resume()
        } catch { quotaError = "quotaNotConfigured" }
    }
    private func flushQuota(_ hub: HubConfig) {
        guard !quotaUploading, !paused, hub.uploadEnabled == true,
              quotaState["scope"] as? String == scope(hub),
              let first = (quotaState["pending"] as? [[String: Any]])?.first,
              let provider = first["provider"] as? [String: Any],
              let handoff, handoff.address == hub.address, handoff.deviceID == hub.deviceId,
              let url = Self.remoteURL(hub, path: "api/ingest"),
              let existing = try? JSONSerialization.jsonObject(with: handoff.upload()) as? [String: Any] else { return }
        // limitsOnly preserves all usage/history. Send identity metadata, never the usage snapshot.
        var payload = existing.filter { ["deviceId", "hostname", "platform", "osName", "osVersion", "agentRuntime", "agentVersion", "updatedAt"].contains($0.key) }
        payload["limitsOnly"] = true; payload["limits"] = ["providers": [provider]]
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return }
        var request = URLRequest(url: url); request.httpMethod = "POST"; request.httpBody = body; request.timeoutInterval = 25
        request.setValue("Bearer \(hub.secret)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        quotaUploading = true
        http.dataTask(with: request) { [weak self] data, response, _ in
            guard let self else { return }
            self.queue.async {
                self.quotaUploading = false
                guard self.config.map({ self.scope($0) }) == self.scope(hub) else { return }
                guard (response as? HTTPURLResponse)?.statusCode == 200, let data,
                      let ack = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      ack["ok"] as? Bool == true, ack["deviceId"] as? String == hub.deviceId else {
                    self.quotaError = "quotaUploadFailed"; return
                }
                var next = self.quotaState
                var pending = next["pending"] as? [[String: Any]] ?? []
                guard pending.first?["id"] as? String == first["id"] as? String else { return }
                pending.removeFirst(); next["pending"] = pending
                do {
                    try Self.writeJSON(next, to: self.directory.appendingPathComponent("quota-outbox.json"))
                    self.quotaState = next; self.quotaError = nil
                    self.fetchRemote(hub); self.cycleNextCheck = .distantPast
                    self.flushQuota(hub)
                } catch { self.quotaError = "quotaObservationSaveFailed" }
            }
        }.resume()
    }
    private func fetchCycles(_ hub: HubConfig) {
        guard !cycleFetching, Date() >= cycleNextCheck,
              let url = Self.remoteURL(hub, path: "api/health") else { return }
        if cycleState["scope"] as? String != scope(hub) { cycleState = [:]; cycleCapability = false }
        cycleFetching = true; cycleNextCheck = Date().addingTimeInterval(300)
        var request = URLRequest(url: url); request.timeoutInterval = 15
        request.setValue("Bearer \(hub.secret)", forHTTPHeaderField: "Authorization")
        http.dataTask(with: request) { [weak self] data, response, _ in
            guard let self else { return }
            self.queue.async {
                guard self.config.map({ self.scope($0) }) == self.scope(hub) else { self.cycleFetching = false; return }
                guard (response as? HTTPURLResponse)?.statusCode == 200, let data,
                      let health = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { self.cycleFetching = false; return }
                guard health["quotaCycleVersion"] as? Int == 1 else {
                    self.cycleCapability = false; self.cycleFetching = false; return
                }
                self.cycleCapability = true
                self.fetchCyclePage(hub)
            }
        }.resume()
    }
    private func fetchCyclePage(_ hub: HubConfig) {
        guard let base = Self.remoteURL(hub, path: "api/quota/cycles"), var url = URLComponents(url: base, resolvingAgainstBaseURL: false) else { cycleFetching = false; return }
        var query = [URLQueryItem(name: "limit", value: "200")]
        if let cursor = cycleState["cursor"] as? String {
            query.append(URLQueryItem(name: "cursor", value: cursor))
            query.append(URLQueryItem(name: "to", value: cycleState["through"] as? String))
        }
        url.queryItems = query
        guard let target = url.url else { cycleFetching = false; return }
        var request = URLRequest(url: target); request.timeoutInterval = 15
        request.setValue("Bearer \(hub.secret)", forHTTPHeaderField: "Authorization")
        http.dataTask(with: request) { [weak self] data, response, _ in
            guard let self else { return }
            self.queue.async {
                guard self.config.map({ self.scope($0) }) == self.scope(hub) else { self.cycleFetching = false; return }
                guard (response as? HTTPURLResponse)?.statusCode == 200, let data, data.count <= 4_194_304,
                      let page = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      page["schemaVersion"] as? Int == 1, page["policyVersion"] as? Int == 1,
                      let events = page["events"] as? [[String: Any]], let through = page["snapshotThrough"] as? String else {
                    if (response as? HTTPURLResponse)?.statusCode == 404 { self.cycleCapability = false }
                    self.cycleFetching = false; return
                }
                var next = self.cycleState
                let accumulated = (next["cursor"] == nil ? [] : next["partial"] as? [[String: Any]] ?? []) + events
                next["scope"] = self.scope(hub); next["through"] = through
                if let cursor = page["nextCursor"] as? String {
                    guard cursor != next["cursor"] as? String, accumulated.count < 100_000 else { self.cycleFetching = false; return }
                    next["cursor"] = cursor; next["partial"] = accumulated
                } else {
                    next["events"] = accumulated; next["updatedAt"] = Self.now()
                    next.removeValue(forKey: "cursor"); next.removeValue(forKey: "partial")
                }
                do {
                    try Self.writeJSON(next, to: self.directory.appendingPathComponent("quota-cycles.json"))
                    self.cycleState = next
                    if next["cursor"] != nil { self.fetchCyclePage(hub) }
                    else { self.cycleFetching = false; self.fetchQuotaHistory(hub) }
                } catch { self.cycleFetching = false }
            }
        }.resume()
    }

    private func fetchQuotaHistory(_ hub: HubConfig) {
        guard !quotaHistoryFetching, let base = Self.remoteURL(hub, path: "api/quota/history") else { return }
        quotaHistoryFetching = true
        let scope = self.scope(hub)
        let old = quotaHistoryState["scope"] as? String == scope ? quotaHistoryState : [:]
        let previous = Self.date(old["through"] as? String ?? "")
        let earliest = (cycleState["events"] as? [[String: Any]] ?? [])
            .compactMap { Self.date($0["inferredStartAt"] as? String ?? "") }.min()
        let floor = Date().addingTimeInterval(-366 * 86_400)
        let from = max(floor, previous?.addingTimeInterval(-300) ?? earliest ?? floor)
        let through = Self.now()
        fetchQuotaHistoryPage(hub, base: base, from: from, through: through, cursor: nil,
                              accumulated: [], old: old)
    }

    private func fetchQuotaHistoryPage(_ hub: HubConfig, base: URL, from: Date, through: String,
                                       cursor: String?, accumulated: [[String: Any]], old: [String: Any]) {
        var parts = URLComponents(url: base, resolvingAgainstBaseURL: false)
        parts?.queryItems = [URLQueryItem(name: "limit", value: "200"),
                             URLQueryItem(name: "from", value: ISO8601DateFormatter().string(from: from)),
                             URLQueryItem(name: "to", value: through)]
        if let cursor { parts?.queryItems?.append(URLQueryItem(name: "cursor", value: cursor)) }
        guard let target = parts?.url else { quotaHistoryFetching = false; return }
        var request = URLRequest(url: target); request.timeoutInterval = 15
        request.setValue("Bearer \(hub.secret)", forHTTPHeaderField: "Authorization")
        http.dataTask(with: request) { [weak self] data, response, _ in
            guard let self else { return }
            self.queue.async {
                guard self.config.map({ self.scope($0) }) == self.scope(hub) else {
                    self.quotaHistoryFetching = false; return
                }
                guard (response as? HTTPURLResponse)?.statusCode == 200, let data,
                      data.count <= 4_194_304,
                      let page = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      page["schemaVersion"] as? Int == 1,
                      page["snapshotThrough"] as? String == through,
                      let rows = page["observations"] as? [[String: Any]],
                      accumulated.count + rows.count <= 50_000 else {
                    self.quotaHistoryFetching = false; return
                }
                let collected = accumulated + rows
                if let next = page["nextCursor"] as? String {
                    guard next != cursor else { self.quotaHistoryFetching = false; return }
                    self.fetchQuotaHistoryPage(hub, base: base, from: from, through: through,
                                               cursor: next, accumulated: collected, old: old)
                    return
                }
                let prior = old["observations"] as? [[String: Any]] ?? []
                var seen = Set<String>()
                let merged = (prior + collected).filter { row in
                    guard let id = row["id"] as? String, !seen.contains(id),
                          let received = Self.date(row["receivedAt"] as? String ?? ""),
                          received >= Date().addingTimeInterval(-366 * 86_400) else { return false }
                    seen.insert(id); return true
                }.suffix(50_000)
                let next: [String: Any] = ["scope": self.scope(hub), "through": through,
                                           "observations": Array(merged)]
                do {
                    try Self.writeJSON(next, to: self.directory.appendingPathComponent("quota-history.json"))
                    self.quotaHistoryState = next
                } catch { /* Retain the last verified history on disk and in memory. */ }
                self.quotaHistoryFetching = false
            }
        }.resume()
    }

    private func serve(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(connection, data: Data())
    }
    private func receive(_ connection: NWConnection, data: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] chunk, _, complete, error in
            guard let self else { connection.cancel(); return }
            var bytes = data
            if let chunk { bytes.append(chunk) }
            guard bytes.count <= 1_048_576, error == nil else { connection.cancel(); return }
            if let marker = bytes.range(of: Data("\r\n\r\n".utf8)) {
                let head = String(decoding: bytes[..<marker.lowerBound], as: UTF8.self)
                let lines = head.components(separatedBy: "\r\n")
                let length = lines.dropFirst().first(where: { $0.lowercased().hasPrefix("content-length:") })
                    .flatMap { Int($0.split(separator: ":", maxSplits: 1).last?.trimmingCharacters(in: .whitespaces) ?? "") } ?? 0
                guard length >= 0, length <= 65_536 else { self.respond(connection, 413, ["error": "payloadTooLarge"]); return }
                if bytes.count >= marker.upperBound + length {
                    self.handle(connection, lines: lines, body: bytes.subdata(in: marker.upperBound..<(marker.upperBound + length)))
                    return
                }
            }
            if complete { connection.cancel() } else { self.receive(connection, data: bytes) }
        }
    }
    private func handle(_ connection: NWConnection, lines: [String], body: Data) {
        guard let first = lines.first?.split(separator: " "), first.count >= 2 else {
            respond(connection, 400, ["error": "badRequest"]); return
        }
        let method = String(first[0]), path = String(first[1]).components(separatedBy: "?")[0]
        let auth = lines.dropFirst().first(where: { $0.lowercased().hasPrefix("authorization:") })?
            .split(separator: ":", maxSplits: 1).last?.trimmingCharacters(in: .whitespaces)
        let expected = Array("Bearer \(secret)".utf8), provided = Array((auth ?? "").utf8)
        var mismatch = expected.count ^ provided.count
        for i in expected.indices { mismatch |= Int(expected[i] ^ (i < provided.count ? provided[i] : 0)) }
        guard mismatch == 0 else { respond(connection, 401, ["error": "unauthorized"]); return }
        switch (method, path) {
        case ("GET", "/api/health"), ("GET", "/local/api/health"):
            respond(connection, 200, ["ok": true, "role": "hub", "runtime": "swift-native", "version": 1])
        case ("GET", "/api/beta/status"):
            respond(connection, 200, status())
        case ("GET", "/api/stats"):
            respondData(connection, 200, config?.enabled == true ? pricedRemote()?.stats ?? pricedLocal() : pricedLocal())
        case ("GET", "/local/api/stats"):
            respondData(connection, 200, pricedLocal())
        case ("GET", "/api/quota/cycles"):
            respond(connection, 200, ["schemaVersion": 1, "available": cycleCapability,
                    "events": cycleState["events"] ?? [], "updatedAt": cycleState["updatedAt"] ?? NSNull()])
        case ("GET", "/api/history"):
            respondData(connection, 200, config?.enabled == true ? remoteHistory ?? history : history)
        case ("GET", "/local/api/history"):
            respondData(connection, 200, history)
        case ("POST", "/api/beta/refresh"):
            // An explicit refresh must bypass the automatic quota/cache cadence.
            // In-flight guards still coalesce concurrent requests.
            quotaNextCheck = .distantPast; cycleNextCheck = .distantPast
            refresh(); respond(connection, 202, status())
        case ("POST", "/api/beta/pause"), ("POST", "/api/beta/resume"):
            paused = path.hasSuffix("pause")
            try? Self.writeJSON(["paused": paused, "deviceId": deviceID], to: directory.appendingPathComponent("backend-config.json"))
            if !paused { refresh() }
            respond(connection, 202, status())
        case ("POST", "/api/beta/restart"):
            respond(connection, 202, status()); queue.asyncAfter(deadline: .now() + 0.2) { exit(1) }
        case ("POST", "/api/beta/hub"):
            configure(connection, body: body)
        case ("GET", "/api/beta/conversion"), ("POST", "/api/beta/conversion"):
            if method == "POST", let command = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
                if command["action"] as? String == "configure", let id = command["choiceId"] as? String,
                   id.count <= 200 {
                    conversionChoiceID = id
                    try? Self.writeJSON(["choiceId": id], to: directory.appendingPathComponent("conversion-config.json"))
                }
                if command["action"] as? String == "refresh", let config, config.enabled { fetchRemote(config) }
            }
            respondData(connection, 200, currentRemoteConversion())
        case ("GET", "/local/api/beta/conversion"), ("POST", "/local/api/beta/conversion"):
            respondData(connection, 200, localConversion)
        default:
            respond(connection, 404, ["error": "not_found"])
        }
    }
    private func configure(_ connection: NWConnection, body: Data) {
        guard let value = try? JSONDecoder().decode(HubConfig.self, from: body) else {
            respond(connection, 400, ["error": "invalidConfiguration"]); return
        }
        if value.uploadEnabled == true && (!value.enabled || value.deviceId.isEmpty) {
            respond(connection, 400, ["error": "deviceNotMatched"]); return
        }
        if value.uploadEnabled == true, let handoff,
           (handoff.address != value.address || handoff.deviceID != value.deviceId) {
            respond(connection, 409, ["error": "existingBaselineRequiresExplicitReset"]); return
        }
        if value.enabled {
            guard let url = URLComponents(string: value.address),
                  url.scheme == "https" ||
                    (ProcessInfo.processInfo.environment["TOKEN_MONITOR_BETA2_DIR"] != nil &&
                     url.scheme == "http" && url.host == "127.0.0.1"), url.host != nil,
                  url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
                  !value.secret.isEmpty, !value.secret.contains("\n"), !value.secret.contains("\r") else {
                respond(connection, 400, ["error": "invalidConfiguration"]); return
            }
        }
        do {
            try Self.writeJSON(["enabled": value.enabled, "address": value.address,
                                "secret": value.secret, "deviceId": value.deviceId,
                                "uploadEnabled": value.uploadEnabled == true],
                               to: directory.appendingPathComponent("hub-config.json"))
            if config?.address != value.address || config?.deviceId != value.deviceId || config?.secret != value.secret {
                remoteStats = nil; remoteHistory = nil; remoteDevices = nil
                cycleState = [:]; cycleCapability = false; cycleNextCheck = .distantPast
                quotaHistoryState = [:]; quotaHistoryFetching = false
                quotaNextCheck = .distantPast
            }
            config = value
            if !value.enabled { remoteStats = nil; remoteHistory = nil; remoteDevices = nil; syncSuccess = nil; readError = nil; uploadError = nil }
            else { refresh(); syncLocal() }
            respond(connection, 200, syncStatus())
        } catch { respond(connection, 400, ["error": "credentialSaveFailed"]) }
    }
    private func syncStatus() -> [String: Any] {
        ["enabled": config?.enabled == true, "configured": config != nil,
         "uploadEnabled": config?.uploadEnabled == true,
         "address": config?.address ?? "", "deviceId": config?.deviceId ?? "",
         "lastSuccess": (config?.uploadEnabled == true ? uploadSuccess : syncSuccess) as Any? ?? NSNull(),
         "error": (config?.uploadEnabled == true ? uploadError ?? readError : readError) as Any? ?? NSNull(),
         "syncing": establishingHandoff || uploading]
    }
    // Display-only projection: syncLocal/upload continue using the original
    // NativeSnapshot and HubHandoff counters, so prices cannot backfill the ledger.
    private func pricedLocal() -> Data {
        if let localPricingCache { return localPricingCache }
        guard let root = (try? JSONSerialization.jsonObject(with: stats)) as? [String: Any],
              let devices = try? JSONSerialization.data(withJSONObject: ["devices": root["devices"] ?? []]) else { return stats }
        let value = (try? NativeModelPricing.enrich(stats: stats, devices: devices,
                            deviceID: deviceID, events: latestEvents).stats) ?? stats
        localPricingCache = value
        return value
    }
    private func pricedRemote() -> (stats: Data, devices: Data)? {
        guard let remoteStats else { return nil }
        guard let remoteDevices else { return (remoteStats, Data()) }
        if let remotePricingCache { return remotePricingCache }
        let value = (try? NativeModelPricing.enrich(stats: remoteStats, devices: remoteDevices,
                            deviceID: config?.deviceId ?? deviceID, events: latestEvents)) ?? (remoteStats, remoteDevices)
        remotePricingCache = value
        return value
    }
    private func currentRemoteConversion() -> Data {
        guard remoteDevices != nil, let priced = pricedRemote() else { return localConversion }
        let local = (try? JSONSerialization.jsonObject(with: localConversion)) as? [String: Any]
        let hourly = (local?["trend"] as? [String: Any])?["hourly"]
            .flatMap { try? JSONSerialization.data(withJSONObject: $0) }
        return (try? NativeQuotaConversion.make(stats: priced.stats, devices: priced.devices,
                                                deviceID: deviceID, hourly: hourly,
                                                selectedChoiceID: conversionChoiceID,
                                                cycleEvents: cycleState["events"] as? [[String: Any]] ?? [],
                                                cycleCapability: cycleCapability,
                                                observations: quotaHistoryState["observations"] as? [[String: Any]] ?? [])) ?? localConversion
    }
    private func status() -> [String: Any] {
        // Settings describe THIS collector, never capabilities of other Hub devices.
        let providerStatus = NativeQuotaObservation.settingsProviders(
            latest: quotaState["latest"] as? [String: Any], error: quotaError)
        return ["version": "0.7.1", "session": session, "pid": Int(getpid()), "paused": paused,
         "lastSuccess": lastSuccess as Any? ?? NSNull(), "failure": failure as Any? ?? NSNull(),
         "collecting": scanning, "sync": syncStatus(), "providers": providerStatus,
         "quota": ["collecting": quotaCollecting, "error": quotaError as Any? ?? NSNull(),
                   "pending": (quotaState["pending"] as? [[String: Any]] ?? []).count,
                   "updatedAt": (quotaState["latest"] as? [String: Any])?["updatedAt"] ?? NSNull()],
         "quotaCycleVersion": cycleCapability ? 1 : 0]
    }
    private func respond(_ connection: NWConnection, _ code: Int, _ value: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: value) else { connection.cancel(); return }
        respondData(connection, code, data)
    }
    private func respondData(_ connection: NWConnection, _ code: Int, _ data: Data) {
        let reason = [200: "OK", 202: "Accepted", 400: "Bad Request", 401: "Unauthorized", 404: "Not Found", 409: "Conflict",
                      413: "Payload Too Large", 503: "Service Unavailable"][code] ?? "Error"
        let header = "HTTP/1.1 \(code) \(reason)\r\nContent-Type: application/json\r\nContent-Length: \(data.count)\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(header.utf8) + data, completion: .contentProcessed { _ in connection.cancel() })
    }
    private static func now() -> String {
        let format = ISO8601DateFormatter(); format.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return format.string(from: Date())
    }
    private static func readJSON(_ url: URL) throws -> [String: Any]? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
    private static func writeJSON(_ value: [String: Any], to url: URL) throws {
        try writeData(JSONSerialization.data(withJSONObject: value), to: url)
    }
    private static func writeData(_ data: Data, to url: URL) throws {
        let temporary = url.deletingLastPathComponent().appendingPathComponent(UUID().uuidString + ".tmp")
        guard FileManager.default.createFile(atPath: temporary.path, contents: data, attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        guard rename(temporary.path, url.path) == 0 else {
            try? FileManager.default.removeItem(at: temporary)
            throw CocoaError(.fileWriteUnknown)
        }
    }
}
