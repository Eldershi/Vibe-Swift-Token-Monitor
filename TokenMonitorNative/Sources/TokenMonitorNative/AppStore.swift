import SwiftUI
import MonitorCore
import NativeBackendCore

@MainActor @Observable final class AppStore {
    static let shared = AppStore()
    var preferences = RuntimePreferences()
    var stats: Stats? { didSet {
        if QuotaPresentation.topology(oldValue?.limits?.providers ?? []) != QuotaPresentation.topology(stats?.limits?.providers ?? []) {
            detailQuotaSelection = nil
        }
        snapshotRevision += 1; refreshTemporalBoundary()
    } }
    var history: History? { didSet { historyPointsCache.removeAll(); expandedActivityCache.removeAll() } }
    var health: Health?
    var status = L10n.text("尚未连接")
    var error: String?
    var historyError: String?
    var conversionSnapshot: ConversionSnapshot?
    var rollingHourlyTrend: ConversionSnapshot.HourlyTrend?
    var hourlyTrendError: String?
    var trendEmptyMessage: String {
        if preferences.period == .today, let hourlyTrendError { return hourlyTrendError }
        return L10n.text("此范围尚无历史数据")
    }
    var conversionError: String?
    var conversionBusy = false
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

    var activityExpansion = ActivityExpansion()
    var historyBusy = false
    var needsSetup = false
    var preferencesError: String?
    private var connectionTask: Task<Void, Never>?
    private var ticker: Task<Void, Never>?
    private var historyTask: Task<Void, Never>?
    private var cacheTask: Task<Void, Never>?
    private var conversionTask: Task<Void, Never>?
    private var lastConversionRefresh = Date.distantPast
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
        ephemeral = override ?? (Identity.isReadOnlyPreview || ProcessInfo.processInfo.arguments.contains("--verify-period-animation") || ProcessInfo.processInfo.arguments.contains("--smoke-test") || ProcessInfo.processInfo.arguments.contains("--verify-localization") || ProcessInfo.processInfo.arguments.contains("--preview-fixture") || ProcessInfo.processInfo.arguments.contains("--preview-live-quota") || ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("--beta-") }))
        preferences.selectionChanged = { [weak self] in self?.preparePresentation() }
        if ephemeral { return }
        do { preferences = RuntimePreferences(try file.load()) }
        catch { preferencesError = error.localizedDescription; canSavePreferences = false }
        preferences.selectionChanged = { [weak self] in self?.preparePresentation() }
        if let data = try? Data(contentsOf: Identity.directory.appendingPathComponent("cache.json")),
           let cache = try? JSONDecoder().decode(Cached.self, from: data), (Identity.isBeta || cache.address == preferences.hubAddress) {
            stats = cache.stats; receivedAt = cache.receivedAt; history = cache.history; loadedHistoryRevision = cache.historyRevision
            status = L10n.text("缓存数据 等待连接")
        }
    }
    private struct HistoryPointsKey: Hashable {
        let kind: Int
        let day: Date
        let calendar: Calendar
        let minimumWeeks: Int
    }
    @ObservationIgnored private var historyPointsCache: [HistoryPointsKey: [TrendPoint]] = [:]
    @ObservationIgnored private var expandedActivityCache: [HistoryPointsKey: [TrendPoint]] = [:]
    @ObservationIgnored var overviewTrendAnimation = BarAnimationMemory()
    @ObservationIgnored var detailTrendAnimation = BarAnimationMemory()
    @ObservationIgnored private(set) var historyProjectionComputations = 0
    /// Reuse prepared points until history, tool, or calendar day changes.
    func historyPoints(monthly: Bool = false, activity: Bool = false, minimumWeeks: Int = 16) -> [TrendPoint] {
        guard let history else { return [] }
        let calendar = Calendar.current
        let key = HistoryPointsKey(kind: activity ? 2 : (monthly ? 1 : 0),
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
        let points = activity ? HistoryGeometry.fillingWeeks(history.allActivityPoints(tool: "codex", now: historyDay), minimumWeeks: minimumWeeks)
                              : history.allPoints(monthly: monthly, tool: "codex", now: historyDay)
        // Bound retention even when the process spans many days.
        if historyPointsCache.count >= 12 { historyPointsCache.removeAll() }
        historyPointsCache[key] = points
        return points
    }
    var trendGranularity: TrendGranularity {
        switch preferences.period { case .today: .hour; case .month: .day; case .allTime: .month }
    }
    func trendPoints() -> [TrendPoint] {
        if preferences.period == .today {
            guard let hourly = rollingHourlyTrend ?? conversionSnapshot?.trend?.hourly,
                  hourly.isRolling24 else { return [] }
            return hourly.points.compactMap { point in
                guard let date = DateCodec.parse(point.start) else { return nil }
                return TrendPoint(date: date, tokens: point.tokens, cost: nil)
            }
        }
        guard let history else { return [] }
        if preferences.period == .allTime { return history.points(monthly: true, tool: "codex", now: historyDay, count: 24) }
        return history.points(monthly: false, tool: "codex", now: historyDay, count: 30)
    }
    private struct PresentationKey: Equatable {
        let revision: Int
        let date: Date
        var period = Period.month
        var cost = false
    }
    @ObservationIgnored private var codexDataCache: (PresentationKey, Bool)?
    @ObservationIgnored private var quotaCache: (PresentationKey, [QuotaProvider])?
    @ObservationIgnored private var devicesCache: (PresentationKey, [Device])?
    @ObservationIgnored private var modelsCache: (PresentationKey, [ModelRow])?
    @ObservationIgnored private(set) var presentationComputations = 0
    private var presentationKey: PresentationKey {
        PresentationKey(revision: snapshotRevision, date: online ? statusClock : receivedAt ?? statusClock)
    }
    func preparePresentation() {
        _ = hasCodexData; _ = quotaProviders; _ = devices; _ = modelRows
        let ids = modelDistribution.items.map(\.id) + deviceDistribution.items.map(\.id)
        var style = preferences.chartStyle
        var next = style.slots
        for scope in ["model:", "device:"] {
            style.slots = next
            next = style.resolvedSlots(ids.filter { $0.hasPrefix(scope) })
        }
        if next != preferences.chartStyle.slots { preferences.chartStyle.slots = next; savePreferences() }
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
    var availableQuotaProviders: [QuotaProvider] {
        let key = presentationKey
        if let cached = quotaCache, cached.0 == key { return cached.1 }
        let value = quotaReports.filter {
            $0.windows.contains(where: \.hasReportedQuota) && ["ok", "rateLimited"].contains($0.status)
                && !$0.isStale(now: key.date, threshold: stats?.staleAfterMs ?? 600_000)
        }
        quotaCache = (key, value); presentationComputations += 1
        return value
    }
    var quotaProviders: [QuotaProvider] {
        availableQuotaProviders
    }
    var quotaChoices: [QuotaChoice] { QuotaSelection.choices(in: availableQuotaProviders) }
    var homeQuotaIDs: Set<String> {
        QuotaSelection.effectiveIDs(selection: preferences.homeQuotaSelection, choices: quotaChoices)
    }
    var homeQuotaProviders: [QuotaProvider] {
        QuotaSelection.filtered(availableQuotaProviders, ids: homeQuotaIDs)
    }
    var usage: Usage? { stats?.periods[preferences.period.rawValue] }
    var hasCodexData: Bool {
        let key = presentationKey
        if let cached = codexDataCache, cached.0 == key { return cached.1 }
        guard let stats else { return false }
        let value = stats.devices.isEmpty
            ? stats.periods.values.contains { $0.clients?["codex"] != nil }
            : stats.devices.contains { $0.hasUsableData(for: "codex", at: key.date, threshold: stats.staleAfterMs ?? 600_000) }
        codexDataCache = (key, value); presentationComputations += 1
        return value
    }
    var selectedTokens: Double? { usage?.tokens(tool: "codex") }
    var selectedCost: Double? { usage?.cost(tool: "codex") }
    var todayTokens: Double? { stats?.periods["today"]?.tokens(tool: "codex") }
    var devices: [Device] {
        let key = PresentationKey(revision: snapshotRevision, date: .distantPast)
        if let cached = devicesCache, cached.0 == key { return cached.1 }
        let value = (stats?.devices ?? []).filter { $0.trackedClients?.contains("codex") == true || $0.periods["allTime"]?.clients?["codex"] != nil }.sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
        devicesCache = (key, value); presentationComputations += 1
        return value
    }
    var deviceUsageFractions: [String: Double] {
        DeviceUsageComparison.fractions(devices: devices, tool: "codex", period: preferences.period, now: statusClock)
    }
    var modelRows: [ModelRow] {
        var key = presentationKey; key.period = preferences.period; key.cost = preferences.modelSortByCost
        if let cached = modelsCache, cached.0 == key { return cached.1 }
        let value = (usage?.modelRows(tool: "codex") ?? []).sorted {
            if key.cost { return ($0.cost ?? -1) == ($1.cost ?? -1) ? $0.name < $1.name : ($0.cost ?? -1) > ($1.cost ?? -1) }
            return $0.tokens == $1.tokens ? $0.name < $1.name : $0.tokens > $1.tokens
        }
        modelsCache = (key, value); presentationComputations += 1
        return value
    }
    var detailQuotaSelection: (source: String, id: String)?
    var quotaReports: [QuotaProvider] {
        let deviceReports = (stats?.devices ?? []).flatMap { device in
            (device.limits?.providers ?? []).filter { $0.provider == "codex" }.map { report in var copy = report; copy.sourceDeviceId = device.id; return copy }
        }
        return QuotaNaming.reports((deviceReports.isEmpty ? stats?.limits?.providers ?? [] : deviceReports).filter { $0.provider == "codex" })
    }
    var quotaThreshold: Double { stats?.staleAfterMs ?? 600_000 }
    var menuQuotaReportIndex: Int? {
        QuotaPresentation.defaultReport(quotaReports, now: statusClock, threshold: quotaThreshold)
    }
    @ObservationIgnored private var modelDistributionCache: (PresentationKey, Distribution)?
    @ObservationIgnored private var deviceDistributionCache: (PresentationKey, Distribution)?
    var modelDistribution: Distribution {
        var key = presentationKey; key.period = preferences.period; key.cost = preferences.modelSortByCost
        if let cached = modelDistributionCache, cached.0 == key { return cached.1 }
        let value = Distribution(modelRows.compactMap { row in
            guard let amount = key.cost ? row.cost : row.tokens else { return nil }
            return DistributionItem(id: "model:" + row.name, name: row.name, value: amount)
        }, otherID: "aggregate:other:model")
        modelDistributionCache = (key, value); return value
    }
    var deviceDistribution: Distribution {
        let key = PresentationKey(revision: snapshotRevision, date: statusClock, period: preferences.period)
        if let cached = deviceDistributionCache, cached.0 == key { return cached.1 }
        let value = Distribution(devices.compactMap { device in
            guard !device.periodExpired(preferences.period, at: statusClock),
                  let amount = device.periods[preferences.period.rawValue]?.tokens(tool: "codex") else { return nil }
            return DistributionItem(id: "device:" + device.id, name: device.id, value: amount)
        }, otherID: "aggregate:other:device")
        deviceDistributionCache = (key, value); return value
    }
    func conversionRequest(_ body: [String: Any]? = nil) async throws -> Data {
        if ephemeral {
            let args = ProcessInfo.processInfo.arguments
            if args.contains("--preview-fixture"), let i = args.firstIndex(of: "--preview-conversion"), args.count > i + 1 {
                return try Data(contentsOf: URL(fileURLWithPath: args[i + 1]))
            }
            throw HubError.disconnected
        }
        guard let client else { throw HubError.disconnected }
        let payload = try body.map { try JSONSerialization.data(withJSONObject: $0) }
        return try await client.send("api/beta/conversion", body: payload)
    }
    func ensureConversionLoaded() async {
        guard Identity.isBeta else { return }
        if ephemeral {
            let args = ProcessInfo.processInfo.arguments
            guard args.contains("--preview-fixture"), args.contains("--preview-conversion") else { return }
            if conversionSnapshot == nil { await updateConversion(["action": "cached"] ) }
            return
        }
        if conversionSnapshot == nil { await updateConversion(["action": "cached"], refreshAfter: false) }
        refreshConversion()
    }
    func updateConversion(_ body: [String: Any]? = nil, refreshAfter: Bool = false) async {
        guard !conversionBusy else { return }
        conversionBusy = true
        defer { conversionBusy = false }
        do {
            let data = try await conversionRequest(body)
            let decoded = try JSONDecoder().decode(ConversionSnapshot.self, from: data)
            conversionSnapshot = decoded
            if let hourly = decoded.trend?.hourly, hourly.isRolling24 {
                rollingHourlyTrend = hourly
            } else { rollingHourlyTrend = nil }
            conversionError = nil
            if body?["action"] as? String == "refresh" { lastConversionRefresh = Date() }
        } catch {
            if conversionSnapshot == nil { conversionError = L10n.text("暂时无法读取换算数据") }
        }
        if refreshAfter { refreshConversion() }
    }
    func refreshConversion(force: Bool = false) {
        guard Identity.isBeta, !ephemeral, conversionTask == nil,
              force || Date().timeIntervalSince(lastConversionRefresh) >= 60 else { return }
        conversionTask = Task { [weak self] in
            guard let self else { return }
            await self.updateConversion(["action": "refresh"])
            self.conversionTask = nil
        }
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
                self?.stopConnection(); self?.online = false; self?.status = BetaBackend.shared.enabled ? L10n.text("独立后台暂不可用 保留缓存") : L10n.text("后台已停用 保留缓存")
            }
            status = backend.enabled ? L10n.text("等待独立后台…") : L10n.text("后台已停用 保留缓存"); backend.start(); return
        }
        guard preferences.connected else { needsSetup = true; return }
        let address = preferences.hubAddress
        let generation = sessionID
        status = L10n.text("正在读取已保存的连接…")
        credentialTask = Task { [weak self] in
            do {
                let secret = try await Task.detached(priority: .userInitiated) { try Keychain.load(address: address) }.value
                guard let self, !Task.isCancelled, self.sessionID == generation, self.preferences.hubAddress == address else { return }
                guard let secret else { self.needsSetup = true; self.status = L10n.text("请重新填写共享密钥"); return }
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
        guard canSavePreferences else { throw HubError.incompatible(L10n.text("请先修复设置文件，避免覆盖较新版本配置")) }
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
        online = false; status = L10n.text("正在连接…"); error = nil
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
                        self.status = L10n.text("已连接 每 30 秒刷新")
                        // Re-probe SSE every five minutes so a backend upgrade can restore live mode.
                        for _ in 0..<10 {
                            try await self.pause(30)
                            let snapshot = try await client.stats()
                            guard !Task.isCancelled, self.sessionID == id else { return }
                            self.accept(snapshot); self.status = L10n.text("已连接 每 30 秒刷新")
                        }
                    }
                } catch {
                    guard !Task.isCancelled, self.sessionID == id else { return }
                    self.online = false
                    self.error = error.localizedDescription
                    if let error = error as? HubError {
                        if error == .unauthorized { self.status = L10n.text("密钥需要检查"); return }
                        if case .incompatible = error { self.status = L10n.text("数据格式需要检查"); return }
                    }
                    self.status = L10n.text("离线 将自动重连")
                    do { try await self.pause(delay) } catch { return }
                    delay = min(delay * 2, 30)
                }
            }
        }
    }
    func accept(_ snapshot: Stats) {
        stats = snapshot; now = Date(); receivedAt = now
        online = true; error = nil; status = L10n.text("已连接 实时同步")
        preparePresentation()
        if historyWanted && (history == nil || loadedHistoryRevision != snapshot.historyRevision) { loadHistory() }
        applyBetaSyncStatus(); scheduleCache()
        if Identity.isBeta { Task { await ensureConversionLoaded() } }
    }
    func applyBetaSyncStatus() {
        guard Identity.isBeta, !ephemeral, !BetaBackend.shared.localOnly, BetaBackend.shared.snapshot?.sync?.enabled == true else { return }
        if let stamp = BetaBackend.shared.snapshot?.sync?.lastSuccess, let date = DateCodec.parse(stamp) { receivedAt = date }
        if BetaBackend.shared.snapshot?.sync?.error != nil { online = false; status = BetaBackend.shared.syncMessage }
        else if BetaBackend.shared.snapshot?.sync?.lastSuccess != nil {
            online = true
            status = Identity.isNativeBeta2 && BetaBackend.shared.snapshot?.sync?.uploadEnabled != true
                ? L10n.text("已连接 Hub 只读") : L10n.text("已连接 Hub 多设备同步")
        }
    }
    func refresh() {
        if Identity.isReadOnlyPreview { Task { await previewLiveQuota() }; return }
        if Identity.isBeta && !ephemeral { Task { await BetaBackend.shared.command("refresh") }; refreshConversion(force: true); BetaBackend.shared.reconnect(); return }
        if let client { connect(client.connection) }
        else { needsSetup = true }
    }
    func sleep() { stopConnection(); online = false; status = L10n.text("已暂停 等待唤醒") }
    func wake() {
        if Identity.isBeta && !ephemeral { BetaBackend.shared.reconnect(); return }
        if let client { connect(client.connection) }
        else if preferences.connected { ticker?.cancel(); ticker = nil; start() }
    }
    func stopConnection() {
        sessionID = UUID(); credentialTask?.cancel(); connectionTask?.cancel(); client?.cancel(); historyTask?.cancel(); conversionTask?.cancel(); conversionTask = nil; historyBusy = false; conversionBusy = false
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
        status = L10n.text("界面验证 示例数据"); online = false
    }
    func previewLiveQuota() async {
        guard ephemeral, Identity.isReadOnlyPreview || ProcessInfo.processInfo.arguments.contains("--preview-live-quota") else { return }
        status = L10n.text("正在读取只读预览…")
        do {
            let url = Identity.directory.appendingPathComponent("Backend/hub-config.json")
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            guard (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid(),
                  (attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600,
                  let config = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any],
                  config["enabled"] as? Bool == true,
                  let address = config["address"] as? String, address.hasPrefix("https://"),
                  let secret = config["secret"] as? String,
                  let deviceID = config["deviceId"] as? String else { throw HubError.disconnected }
            let client = try HubClient(connection: HubConnection(address: address, secret: secret))
            defer { client.cancel() }
            var statsData = try await client.data("api/stats")
            let historyData = try await client.data("api/history")
            var devicesData = try await client.data("api/devices")
            // Local logs only supply prices when their model totals exactly match
            // this Hub device at its report timestamp. No statistics are written back.
            let eventsForPricing: [NativeUsageEvent] = (try? await Task.detached(priority: .utility) {
                let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
                return try CodexScanner.scan(root: root.appendingPathComponent("sessions"))
                    + CodexScanner.scan(root: root.appendingPathComponent("archived_sessions"))
            }.value) ?? []
            let priced = try NativeModelPricing.enrich(stats: statsData, devices: devicesData,
                                                       deviceID: deviceID, events: eventsForPricing)
            statsData = priced.stats; devicesData = priced.devices
            let through = ISO8601DateFormatter().string(from: Date())
            var events: [[String: Any]] = [], cursor: String?
            repeat {
                var query = [URLQueryItem(name: "limit", value: "200"), URLQueryItem(name: "to", value: through)]
                if let cursor { query.append(URLQueryItem(name: "cursor", value: cursor)) }
                let page = try JSONSerialization.jsonObject(with: await client.data("api/quota/cycles", query: query)) as? [String: Any] ?? [:]
                guard page["schemaVersion"] as? Int == 1, let rows = page["events"] as? [[String: Any]],
                      events.count + rows.count <= 20_000 else { throw HubError.disconnected }
                events += rows; cursor = page["nextCursor"] as? String
            } while cursor != nil
            let earliest = events.compactMap { DateCodec.parse($0["inferredStartAt"] as? String) }.min()
            let from = ISO8601DateFormatter().string(from: max(Date().addingTimeInterval(-366 * 86_400), earliest ?? Date()))
            var observations: [[String: Any]] = []
            repeat {
                var query = [URLQueryItem(name: "limit", value: "200"), URLQueryItem(name: "from", value: from),
                             URLQueryItem(name: "to", value: through)]
                if let cursor { query.append(URLQueryItem(name: "cursor", value: cursor)) }
                let page = try JSONSerialization.jsonObject(with: await client.data("api/quota/history", query: query)) as? [String: Any] ?? [:]
                guard page["schemaVersion"] as? Int == 1, let rows = page["observations"] as? [[String: Any]],
                      observations.count + rows.count <= 50_000 else { throw HubError.disconnected }
                observations += rows; cursor = page["nextCursor"] as? String
            } while cursor != nil
            let conversionData = try NativeQuotaConversion.make(stats: statsData, devices: devicesData,
                deviceID: deviceID, hourly: nil, cycleEvents: events, cycleCapability: true,
                observations: observations)
            stats = try Stats.decode(statsData)
            history = try History.decode(historyData)
            conversionSnapshot = try JSONDecoder().decode(ConversionSnapshot.self, from: conversionData)
            now = Date(); receivedAt = now; online = false; needsSetup = false
            status = L10n.text("只读预览")
            preparePresentation()
            await refreshPreviewHourlyTrend()
        } catch {
            online = false; conversionError = L10n.text("只读预览无法连接 Hub")
            status = conversionError ?? L10n.text("只读预览无法连接 Hub")
        }
    }

    /// The Hub retains daily history; rolling hours come from the existing local
    /// collector. A GET reads its in-memory snapshot without refreshing or starting it.
    func refreshPreviewHourlyTrend(endpointURL: URL? = nil) async {
        guard ephemeral else { return }
        do {
            let endpoint = try BetaEndpoint.load(from: endpointURL
                ?? Identity.directory.appendingPathComponent("Backend/endpoint.json"))
            let local = makeClient(try endpoint.connection())
            defer { local.cancel() }
            let data = try await local.data("local/api/beta/conversion")
            let snapshot = try JSONDecoder().decode(ConversionSnapshot.self, from: data)
            guard let hourly = snapshot.trend?.hourly, hourly.isRolling24 else {
                throw HubError.disconnected
            }
            rollingHourlyTrend = hourly
            hourlyTrendError = nil
        } catch {
            rollingHourlyTrend = nil
            hourlyTrendError = L10n.text("小时趋势读取失败，请确认本机后台正在运行后刷新")
        }
    }
}
