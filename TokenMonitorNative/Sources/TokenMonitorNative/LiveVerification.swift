import Foundation
import MonitorCore

/// Opt-in local acceptance check. Prints only check results, never credentials or raw responses.
enum LiveVerification {
    @MainActor static func run() async -> Int32 {
        do {
            let connection: HubConnection
            if Identity.isBeta {
                let endpoint = try BetaEndpoint.load(from: Identity.directory.appendingPathComponent("Backend/endpoint.json"))
                connection = try endpoint.connection()
            } else {
                let prefs = try PreferencesFile(url:Identity.directory.appendingPathComponent("settings.json")).load()
                guard let secret = try Keychain.load(address:prefs.hubAddress) else { throw HubError.invalidSecret }
                connection = try HubConnection(address:prefs.hubAddress,secret:secret)
            }
            let client = HubClient(connection:connection)
            defer { client.cancel() }
            _ = try await client.health()
            let data = try await client.data("api/stats")
            let stats = try Stats.decode(data)
            let raw = try JSONSerialization.jsonObject(with:data) as! [String:Any]
            let periods = raw["periods"] as! [String:[String:Any]]
            var checks = 0
            for period in Period.allCases {
                let usage = stats.periods[period.rawValue]!, source = periods[period.rawValue]!
                for tool in [""] + stats.tools {
                    let tokens = tool.isEmpty ? (source["totalTokens"] as? NSNumber)?.doubleValue : (source["clients"] as? [String:NSNumber])?[tool]?.doubleValue
                    let cost = tool.isEmpty ? (source["costUsd"] as? NSNumber)?.doubleValue : (source["clientCosts"] as? [String:NSNumber])?[tool]?.doubleValue
                    guard usage.tokens(tool:tool) == tokens, usage.cost(tool:tool) == cost else { throw HubError.incompatible("同快照合计对照") }
                    let models = tool.isEmpty ? source["models"] as? [String:NSNumber] : (source["clientModels"] as? [String:[String:NSNumber]])?[tool]
                    let costs = tool.isEmpty ? source["modelCosts"] as? [String:NSNumber] : (source["clientModelCosts"] as? [String:[String:NSNumber]])?[tool]
                    let rows = usage.modelRows(tool:tool)
                    guard rows.count == (models?.count ?? 0), rows.allSatisfy({ $0.tokens == models?[$0.name]?.doubleValue && $0.cost == costs?[$0.name]?.doubleValue }) else { throw HubError.incompatible("同快照模型对照") }
                    checks += 1
                }
            }
            let rawDevices = raw["devices"] as! [[String:Any]]
            for (index, device) in stats.devices.enumerated() {
                guard device.id == rawDevices[index]["deviceId"] as? String else { throw HubError.incompatible("设备身份对照") }
                let periods = rawDevices[index]["periods"] as! [String:[String:Any]]
                for period in Period.allCases {
                    guard device.periods[period.rawValue]?.totalTokens == (periods[period.rawValue]?["totalTokens"] as? NSNumber)?.doubleValue else { throw HubError.incompatible("设备分项对照") }
                }
            }
            if let rawLimits = raw["limits"] as? [String:Any], let providers = rawLimits["providers"] as? [[String:Any]] {
                guard let parsed = stats.limits, parsed.providers.count == providers.count else { throw HubError.incompatible("额度提供方对照") }
                for (p, source) in zip(parsed.providers, providers) {
                    let windows = source["windows"] as? [[String:Any]] ?? []
                    guard p.provider == source["provider"] as? String, p.windows.count == windows.count else { throw HubError.incompatible("额度窗口对照") }
                    for (window, rawWindow) in zip(p.windows, windows) {
                        guard window.remainingPercent == (rawWindow["remainingPercent"] as? NSNumber)?.doubleValue, window.remaining == (rawWindow["remaining"] as? NSNumber)?.doubleValue else { throw HubError.incompatible("额度值对照") }
                    }
                }
                print("PASS: quota provider/window counts and remaining values match the same raw snapshot")
            }
            _ = try await client.history()
            try await withThrowingTaskGroup(of:Void.self) { group in
                group.addTask { for try await _ in client.stream() { return }; throw HubError.disconnected }
                group.addTask { try await Task.sleep(for:.seconds(15)); throw HubError.disconnected }
                _ = try await group.next(); group.cancelAll()
            }
            print("PASS: health, \(checks) period/tool totals and model breakdowns, \(stats.devices.count) device(s), history, authenticated SSE snapshot")
            return 0
        } catch { fputs("FAIL: \(error.localizedDescription)\n",stderr); return 1 }
    }
}
