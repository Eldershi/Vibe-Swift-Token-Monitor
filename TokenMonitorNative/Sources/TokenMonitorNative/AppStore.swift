import SwiftUI
import MonitorCore

@MainActor @Observable final class AppStore {
    static let shared = AppStore()
    var preferences = RuntimePreferences()
    var stats: Stats? { didSet { snapshotRevision += 1; refreshTemporalBoundary() } }
    var history: History? { didSet { historyPointsCache.removeAll(); expandedActivityCache.removeAll() } }
    var health: Health?
    var status = "尚未连接"
    var error: String?
    var historyError: String?
    var online = false
    var receivedAt: Date?
    @ObservationIgnored var now = Date() {
        didSet {
            let day = Calendar.current.startOfDay(for: now)
            if day != historyDay { historyDay = day }
            if now >= nextStatusBoundary || now < statusClock { refreshTemporalBoundary() }
        }
    }
    private(set) var statusClock = Date()
    private(set) var historyDay = Calendar.current.startOfDay(for: Date())
    var historyPresentationID = UUID()
    private var snapshotRevision = 0
    @ObservationIgnored private var nextStatusBoundary = Date.distantPast
    @ObservationIgnored private var preferenceSaveTask: Task<Void, Never>?
    @ObservationIgnored private var credentialTask: Task<Void, Never>?
    @ObservationIgnored private var savingConnection = false
    @ObservationIgnored private var persistenceRevision: UInt64 = 0
    private func nextPersistenceRevision() -> UInt64 { persistenceRevision += 1; return persistenceRevision }
    @ObservationIgnored private let writer = PersistenceWriter()

    var historyBusy = false
    var needsSetup = false
    var preferencesError: String?
    private var connectionTask: Task<Void, Never>?
    private var ticker: Task<Void, Never>?
    private var historyTask: Task<Void, Never>?
    private var cacheTask: Task<Void, Never>?
    private var client: HubClient?
    private var sessionID = UUID()
    private var historyWanted = false
    private var loadedHistoryRevision: String?
    private let file = PreferencesFile(url: Identity.directory.appendingPathComponent("settings.json"))
    private var canSavePreferences = true
    private var ephemeral = false
    private let makeClient: (HubConnection) -> HubClient
    private let pause: (Double) async throws -> Void
    private struct Cached: Codable, Sendable { let address: String; let stats: Stats; let receivedAt: Date; let history: History?; let historyRevision: String? }

    init(ephemeral override: Bool? = nil, makeClient: @escaping (HubConnection) -> HubClient = { HubClient(connection: $0) }, pause: @escaping (Double) async throws -> Void = { try await Task.sleep(for: .seconds($0)) }) {
        self.makeClient = makeClient; self.pause = pause
        ephemeral = override ?? (ProcessInfo.processInfo.arguments.contains("--smoke-test") || ProcessInfo.processInfo.arguments.contains("--preview-fixture") || ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("--beta-") }))
        preferences.selectionChanged = { [weak self] in self?.preparePresentation() }
        if ephemeral { return }
        do { preferences = RuntimePreferences(try file.load()) }
        catch { preferencesError = error.localizedDescription; canSavePreferences = false }
        preferences.selectionChanged = { [weak self] in self?.preparePresentation() }
        if let data = try? Data(contentsOf: Identity.directory.appendingPathComponent("cache.json")),
           let cache = try? JSONDecoder().decode(Cached.self, from: data), (Identity.isBeta || cache.address == preferences.hubAddress) {
            stats = cache.stats; receivedAt = cache.receivedAt; history = cache.history; loadedHistoryRevision = cache.historyRevision
            status = "缓存数据 · 等待连接"
        }
    }
    private struct HistoryPointsKey: Hashable {
        let tool: String
        let kind: Int
        let day: Date
        let calendar: Calendar
        let minimumWeeks: Int
    }
    @ObservationIgnored private var historyPointsCache: [HistoryPointsKey: [TrendPoint]] = [:]
    @ObservationIgnored private var expandedActivityCache: [HistoryPointsKey: [TrendPoint]] = [:]
    @ObservationIgnored private(set) var historyProjectionComputations = 0
    /// Resize and the one-second ticker reuse prepared points until history/tool/day changes.
    func historyPoints(monthly: Bool = false, activity: Bool = false, minimumWeeks: Int = 16) -> [TrendPoint] {
        guard let history else { return [] }
        let calendar = Calendar.current
        let key = HistoryPointsKey(tool: preferences.tool, kind: activity ? 2 : (monthly ? 1 : 0),
                                   day: historyDay, calendar: calendar, minimumWeeks: activity ? minimumWeeks : 0)
        if activity && minimumWeeks > 16 {
            let base = historyPoints(activity: true)
            guard minimumWeeks > (base.count + 6) / 7 else { return base }
            if let points = expandedActivityCache[key] { return points }
            let points = HistoryGeometry.fillingWeeks(base, minimumWeeks: minimumWeeks)
            if expandedActivityCache.count >= 8 { expandedActivityCache.removeAll(keepingCapacity: true) }
            expandedActivityCache[key] = points
            return points
        }
        if let points = historyPointsCache[key] { return points }
        historyProjectionComputations += 1
        let points = activity ? HistoryGeometry.fillingWeeks(history.allActivityPoints(tool: key.tool, now: historyDay), minimumWeeks: minimumWeeks)
                              : history.allPoints(monthly: monthly, tool: key.tool, now: historyDay)
        // Bound retention even when the process spans many days or tools.
        if historyPointsCache.count >= 12 { historyPointsCache.removeAll() }
        historyPointsCache[key] = points
        return points
    }
    private struct PresentationKey: Equatable {
        let revision: Int
        let date: Date
        var tool = ""
        var period = Period.month
        var cost = false
    }
    @ObservationIgnored private var toolsCache: (PresentationKey, [String])?
    @ObservationIgnored private var quotaCache: (PresentationKey, [QuotaProvider])?
    @ObservationIgnored private var devicesCache: (PresentationKey, [Device])?
    @ObservationIgnored private var modelsCache: (PresentationKey, [ModelRow])?
    @ObservationIgnored private(set) var presentationComputations = 0
    private var presentationKey: PresentationKey {
        PresentationKey(revision: snapshotRevision, date: online ? statusClock : receivedAt ?? statusClock)
    }
    func preparePresentation() {
        _ = tools; _ = quotaProviders; _ = devices; _ = modelRows
    }
    /// Only publish a new status clock when a displayed expiry/day boundary is crossed.
    private func refreshTemporalBoundary() {
        statusClock = now
        var boundaries = [Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now))!]
        var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(secondsFromGMT: 0)!
        boundaries.append(utc.date(byAdding: .day, value: 1, to: utc.startOfDay(for: now))!)
        let threshold = stats?.staleAfterMs ?? 600_000
        for device in stats?.devices ?? [] {
            if threshold > 0, let date = device.reportDate {
                boundaries.append(date.addingTimeInterval(max(threshold, (device.syncUploadIntervalMs ?? 0) * 2) / 1000 + 0.001))
            }
            for period in [Period.today, .month] {
                if let end = DateCodec.parse(device.periodWindows?[period.rawValue]?.endsAt) { boundaries.append(end) }
            }
        }
        for provider in stats?.limits?.providers ?? [] {
            if let date = DateCodec.parse(provider.updatedAt) { boundaries.append(date.addingTimeInterval(threshold / 1000 + 0.001)) }
            boundaries += provider.windows.compactMap { DateCodec.parse($0.resetsAt) }
        }
        nextStatusBoundary = boundaries.filter { $0 > now }.min() ?? now.addingTimeInterval(60)
    }
    var quotaProviders: [QuotaProvider] {
        var key = presentationKey; key.tool = preferences.tool
        if let cached = quotaCache, cached.0 == key { return cached.1 }
        let available = Set(tools)
        let value = (stats?.limits?.providers ?? []).filter {
            available.contains($0.provider) && (key.tool.isEmpty || $0.provider == key.tool)
                && !$0.windows.isEmpty && ["ok", "rateLimited"].contains($0.status)
                && !$0.isStale(now: key.date, threshold: stats?.staleAfterMs ?? 600_000)
        }
        quotaCache = (key, value); presentationComputations += 1
        return value
    }
    var usage: Usage? { stats?.periods[preferences.period.rawValue] }
    var tools: [String] {
        let key = presentationKey
        if let cached = toolsCache, cached.0 == key { return cached.1 }
        guard let stats else { return [] }
        let candidates = Set(stats.periods.values.flatMap { Array(($0.clients ?? [:]).keys) })
        let value = stats.devices.isEmpty ? candidates.sorted() : candidates.filter { tool in
            stats.devices.contains { $0.hasUsableData(for: tool, at: key.date, threshold: stats.staleAfterMs ?? 600_000) }
        }.sorted()
        toolsCache = (key, value); presentationComputations += 1
        return value
    }
    func reconcileToolSelection() {
        guard stats != nil, !preferences.tool.isEmpty, !tools.contains(preferences.tool) else { return }
        preferences.tool = tools.contains("codex") ? "codex" : tools.first ?? ""
        savePreferences()
    }
    var selectedToolTitle: String { preferences.tool.isEmpty ? "全部工具" : preferences.tool == "codex" ? "Codex" : preferences.tool }
    var selectedTokens: Double? { usage?.tokens(tool: preferences.tool) }
    var selectedCost: Double? { usage?.cost(tool: preferences.tool) }
    var todayTokens: Double? { stats?.periods["today"]?.tokens(tool: preferences.tool) }
    var devices: [Device] {
        let key = PresentationKey(revision: snapshotRevision, date: .distantPast, tool: preferences.tool)
        if let cached = devicesCache, cached.0 == key { return cached.1 }
        let value = (stats?.devices ?? []).filter { key.tool.isEmpty || $0.trackedClients?.contains(key.tool) == true || $0.periods["allTime"]?.clients?[key.tool] != nil }.sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
        devicesCache = (key, value); presentationComputations += 1
        return value
    }
    var modelRows: [ModelRow] {
        var key = presentationKey; key.tool = preferences.tool; key.period = preferences.period; key.cost = preferences.modelSortByCost
        if let cached = modelsCache, cached.0 == key { return cached.1 }
        let allowedNames = Set(tools.flatMap { Array((usage?.clientModels?[$0] ?? [:]).keys) })
        let value = (usage?.modelRows(tool: key.tool) ?? []).filter {
            !key.tool.isEmpty || usage?.clientModels == nil || allowedNames.contains($0.name)
        }.sorted {
            if key.cost { return ($0.cost ?? -1) == ($1.cost ?? -1) ? $0.name < $1.name : ($0.cost ?? -1) > ($1.cost ?? -1) }
            return $0.tokens == $1.tokens ? $0.name < $1.name : $0.tokens > $1.tokens
        }
        modelsCache = (key, value); presentationComputations += 1
        return value
    }
    func savePreferences() {
        guard !ephemeral, canSavePreferences, !savingConnection else { return }
        preferenceSaveTask?.cancel()
        let value = preferences.snapshot, revision = nextPersistenceRevision()
        preferenceSaveTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(150))
                guard let self, !Task.isCancelled else { return }
                try await self.writer.savePreferences(value, to: self.file.url, revision: revision)
            } catch is CancellationError { }
              catch { self?.preferencesError = error.localizedDescription }
        }
    }
    func flushPersistence() async {
        preferenceSaveTask?.cancel(); cacheTask?.cancel()
        guard !ephemeral else { return }
        if canSavePreferences {
            do { try await writer.savePreferences(preferences.snapshot, to: file.url, revision: nextPersistenceRevision()) }
            catch { preferencesError = error.localizedDescription }
        }
        await writeCache()
    }
    func saveForTermination() -> Task<Void, Never> {
        preferenceSaveTask?.cancel(); cacheTask?.cancel(); ticker?.cancel()
        let value = preferences.snapshot, preferenceURL = file.url, revision = nextPersistenceRevision()
        let cacheURL = Identity.directory.appendingPathComponent("cache.json")
        let cached = stats.flatMap { snapshot in receivedAt.map {
            Cached(address: value.hubAddress, stats: snapshot, receivedAt: $0, history: history, historyRevision: loadedHistoryRevision)
        } }
        let save = !ephemeral, savePreferences = canSavePreferences, writer = writer
        return Task.detached {
            guard save else { return }
            do {
                if savePreferences { try await writer.savePreferences(value, to: preferenceURL, revision: revision) }
                if let cached { try await writer.saveCache(cached, to: cacheURL, revision: revision) }
            } catch { fputs("Token Monitor: final persistence failed: \(error.localizedDescription)\n", stderr) }
        }
    }
    func start() {
        guard ticker == nil else { return }
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, !Task.isCancelled else { return }
                self.now = Date()
            }
        }
        if ephemeral { return }
        if Identity.isBeta {
            let backend = BetaBackend.shared
            backend.connected = { [weak self] connection in
                guard let self else { return }
                self.needsSetup = false
                if self.preferences.hubAddress != connection.baseURL.absoluteString { self.stats = nil; self.history = nil; self.loadedHistoryRevision = nil; self.historyPresentationID = UUID() }
                self.preferences.hubAddress = connection.baseURL.absoluteString
                self.connect(connection)
            }
            backend.disconnected = { [weak self] in
                self?.stopConnection(); self?.online = false; self?.status = BetaBackend.shared.enabled ? "独立后台暂不可用 · 保留缓存" : "后台已停用 · 保留缓存"
            }
            status = backend.enabled ? "等待独立后台…" : "后台已停用 · 保留缓存"; backend.start(); return
        }
        guard preferences.connected else { needsSetup = true; return }
        let address = preferences.hubAddress
        let generation = sessionID
        status = "正在读取已保存的连接…"
        credentialTask = Task { [weak self] in
            do {
                let secret = try await Task.detached(priority: .userInitiated) { try Keychain.load(address: address) }.value
                guard let self, !Task.isCancelled, self.sessionID == generation, self.preferences.hubAddress == address else { return }
                guard let secret else { self.needsSetup = true; self.status = "请重新填写共享密钥"; return }
                self.connect(try HubConnection(address: address, secret: secret))
            } catch { self?.error = error.localizedDescription; self?.needsSetup = true }
        }
    }
    func testConnection(address: String, secret: String) async throws -> (HubConnection, Health, Stats) {
        let connection = try HubConnection(address: address, secret: secret)
        let probe = HubClient(connection: connection)
        defer { probe.cancel() }
        let health = try await probe.health()
        let stats = try await probe.stats()
        return (connection, health, stats)
    }
    func saveConnection(_ result: (HubConnection, Health, Stats)) async throws {
        guard canSavePreferences else { throw HubError.incompatible("请先修复设置文件，避免覆盖较新版本配置") }
        savingConnection = true; preferenceSaveTask?.cancel()
        defer { savingConnection = false; savePreferences() }
        let (connection, health, snapshot) = result
        try await Task.detached(priority: .userInitiated) { try Keychain.save(connection.secret, address: connection.baseURL.absoluteString) }.value
        let changedHub = preferences.hubAddress != connection.baseURL.absoluteString
        var proposed = preferences.snapshot
        proposed.hubAddress = connection.baseURL.absoluteString; proposed.connected = true
        preferenceSaveTask?.cancel()
        if !ephemeral {
            guard try await writer.savePreferences(proposed, to: file.url, revision: nextPersistenceRevision()) else { throw CancellationError() }
        }
        preferences.hubAddress = proposed.hubAddress; preferences.connected = true
        savePreferences()
        if changedHub { stats = nil; history = nil; receivedAt = nil; loadedHistoryRevision = nil }
        self.health = health; needsSetup = false
        connect(connection); accept(snapshot)
    }
    func connect(_ connection: HubConnection) {
        stopConnection()
        let id = sessionID
        let client = makeClient(connection); self.client = client
        online = false; status = "正在连接…"; error = nil
        connectionTask = Task { [weak self] in
            var delay: Double = 1
            while !Task.isCancelled {
                guard let self, self.sessionID == id else { return }
                do {
                    let health = try await client.health()
                    let first = try await client.stats()
                    guard !Task.isCancelled, self.sessionID == id else { return }
                    self.health = health; self.accept(first)
                    let streamStarted = Date()
                    do {
                        for try await snapshot in client.stream() {
                            guard !Task.isCancelled, self.sessionID == id else { return }
                            self.accept(snapshot)
                            if Date().timeIntervalSince(streamStarted) > 60 { delay = 1 }
                        }
                        throw HubError.disconnected
                    } catch HubError.unsupportedStream {
                        self.status = "已连接 · 每 30 秒刷新"
                        // Re-probe SSE every five minutes so a backend upgrade can restore live mode.
                        for _ in 0..<10 {
                            try await self.pause(30)
                            let snapshot = try await client.stats()
                            guard !Task.isCancelled, self.sessionID == id else { return }
                            self.accept(snapshot); self.status = "已连接 · 每 30 秒刷新"
                        }
                    }
                } catch {
                    guard !Task.isCancelled, self.sessionID == id else { return }
                    self.online = false
                    self.error = error.localizedDescription
                    if let error = error as? HubError {
                        if error == .unauthorized { self.status = "密钥需要检查"; return }
                        if case .incompatible = error { self.status = "数据格式需要检查"; return }
                    }
                    self.status = "离线 · 将自动重连"
                    do { try await self.pause(delay) } catch { return }
                    delay = min(delay * 2, 30)
                }
            }
        }
    }
    func accept(_ snapshot: Stats) {
        stats = snapshot; now = Date(); receivedAt = now
        online = true; error = nil; status = "已连接 · 实时同步"
        reconcileToolSelection()
        preparePresentation()
        if historyWanted && (history == nil || loadedHistoryRevision != snapshot.historyRevision) { loadHistory() }
        applyBetaSyncStatus(); scheduleCache()
    }
    func applyBetaSyncStatus() {
        guard Identity.isBeta, !ephemeral, !BetaBackend.shared.localOnly, BetaBackend.shared.snapshot?.sync?.enabled == true else { return }
        if let stamp = BetaBackend.shared.snapshot?.sync?.lastSuccess, let date = DateCodec.parse(stamp) { receivedAt = date }
        if BetaBackend.shared.snapshot?.sync?.error != nil { online = false; status = BetaBackend.shared.syncMessage }
        else if BetaBackend.shared.snapshot?.sync?.lastSuccess != nil { online = true; status = "已连接 · Hub 多设备同步" }
    }
    func refresh() {
        if Identity.isBeta && !ephemeral { Task { await BetaBackend.shared.command("refresh") }; BetaBackend.shared.reconnect(); return }
        if let client { connect(client.connection) }
        else { needsSetup = true }
    }
    func sleep() { stopConnection(); online = false; status = "已暂停 · 等待唤醒" }
    func wake() {
        if Identity.isBeta && !ephemeral { BetaBackend.shared.reconnect(); return }
        if let client { connect(client.connection) }
        else if preferences.connected { ticker?.cancel(); ticker = nil; start() }
    }
    func stopConnection() {
        sessionID = UUID(); credentialTask?.cancel(); connectionTask?.cancel(); client?.cancel(); historyTask?.cancel(); historyBusy = false
    }
    func loadHistory() {
        historyWanted = true
        guard !historyBusy, let client else { return }
        if history != nil && loadedHistoryRevision == stats?.historyRevision && historyError == nil { return }
        let id = sessionID, revision = stats?.historyRevision
        historyBusy = true; historyError = nil
        historyTask = Task { [weak self] in
            do {
                let history = try await client.history()
                guard let self, !Task.isCancelled, self.sessionID == id else { return }
                self.history = history; self.loadedHistoryRevision = revision; self.historyBusy = false; self.scheduleCache()
            } catch {
                guard let self, !Task.isCancelled, self.sessionID == id else { return }
                self.historyBusy = false; self.historyError = error.localizedDescription
            }
        }
    }
    private func scheduleCache() {
        guard !ephemeral, cacheTask == nil else { return }
        cacheTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard let self, !Task.isCancelled else { return }
            await self.writeCache(); self.cacheTask = nil
        }
    }
    func writeCache() async {
        guard !ephemeral, let stats, let receivedAt else { return }
        let cached = Cached(address: preferences.hubAddress, stats: stats, receivedAt: receivedAt, history: history, historyRevision: loadedHistoryRevision)
        do {
            try await writer.saveCache(cached, to: Identity.directory.appendingPathComponent("cache.json"), revision: nextPersistenceRevision())
        } catch { /* Cache failure never blocks live data. Preferences errors are surfaced separately. */ }
    }
    func preview(statsURL: URL, historyURL: URL?) throws {
        accept(try Stats.decode(Data(contentsOf: statsURL)))
        if let historyURL { history = try History.decode(Data(contentsOf: historyURL)) }
        status = "界面验证 · 示例数据"; online = false
    }
}
