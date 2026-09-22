import Foundation
import CoreFoundation

import CryptoKit

/// Wire compatibility with the existing Codex collector, without a bundled CLI/runtime.
public enum NativeQuotaObservation {
    public struct Identity {
        public let accessToken: String
        public let accountID: String
        public let accountKey: String
        public let fedramp: Bool
    }
    public static func identity(auth: Data) throws -> Identity {
        let auth = try object(auth)
        let tokens = auth["tokens"] as? [String: Any] ?? auth
        let claims = jwt(text(tokens["id_token"] ?? tokens["idToken"] ?? auth["id_token"]))
        let nested = claims["https://api.openai.com/auth"] as? [String: Any]
            ?? claims["https://api.openai.com/profile"] as? [String: Any] ?? [:]
        let account = auth["account"] as? [String: Any] ?? [:]
        let email = text(claims["email"] ?? nested["email"] ?? account["email"] ?? auth["email"]).lowercased()
        let claimedID = text(claims["chatgpt_account_id"] ?? nested["chatgpt_account_id"]).lowercased()
        let id = text(tokens["account_id"] ?? tokens["accountId"] ?? auth["account_id"] ?? auth["accountId"] ?? claimedID).lowercased()
        let token = text(tokens["access_token"] ?? tokens["accessToken"] ?? auth["access_token"])
        guard !token.isEmpty, !id.isEmpty || !email.isEmpty else { throw ObservationError.invalidIdentity }
        let seed = !email.isEmpty && !id.isEmpty ? email + "\0" + id : id.isEmpty ? email : id
        return Identity(accessToken: token, accountID: id,
                        accountKey: "sha256:" + hash("codex\0" + seed + "\0"),
                        fedramp: id == claimedID && (nested["chatgpt_account_is_fedramp"] as? Bool ?? claims["chatgpt_account_is_fedramp"] as? Bool ?? false))
    }
    public static func provider(payload: Data, identity: Identity, observedAt: Date) throws -> [String: Any] {
        let payload = try object(payload)
        var windows: [[String: Any]] = []
        func append(_ limit: [String: Any], id: String, label: String, additional: Bool) {
            for key in ["primary", "secondary"] {
                guard let window = (limit[key + "_window"] ?? limit[key + "Window"]) as? [String: Any],
                      let seconds = number(window["limit_window_seconds"] ?? window["limitWindowSeconds"]),
                      let used = number(window["used_percent"] ?? window["usedPercent"]), (0...100).contains(used),
                      let reset = number(window["reset_at"] ?? window["resetAt"]),
                      seconds > 0, seconds <= 366 * 86400, reset > 0, reset < 253402300800 else { continue }
                let kind = seconds == 30 * 86400 ? "billing" : seconds >= 7 * 86400 ? "weekly" : seconds >= 86400 ? "daily" : "session"
                windows.append(["kind": kind, "limitId": id, "label": label, "additional": additional,
                    "usedPercent": used, "remainingPercent": 100 - used, "percent": 100 - used,
                    "windowMinutes": seconds / 60, "resetsAt": iso(Date(timeIntervalSince1970: reset))])
            }
        }
        if let limit = (payload["rate_limit"] ?? payload["rateLimit"]) as? [String: Any] {
            append(limit, id: "codex", label: "Codex", additional: false)
        }
        for item in (payload["additional_rate_limits"] ?? payload["additionalRateLimits"]) as? [[String: Any]] ?? [] {
            let id = text(item["metered_feature"] ?? item["meteredFeature"])
            guard !id.isEmpty, id != "codex",
                  let limit = (item["rate_limit"] ?? item["rateLimit"]) as? [String: Any] else { continue }
            append(limit, id: id, label: text(item["limit_name"] ?? item["limitName"]), additional: true)
        }
        guard !windows.isEmpty else { throw ObservationError.invalidPayload }
        let plan = text(payload["plan_type"] ?? payload["planType"])
        return ["provider": "codex", "status": "ok", "source": "oauth", "accountKey": identity.accountKey,
                "updatedAt": iso(observedAt), "checkedAt": iso(observedAt), "windows": windows,
                "planLabel": plan.contains("@") ? "" : plan]
    }
    public static func settingsProviders(latest: [String: Any]?, error: String?) -> [[String: String]] {
        guard latest != nil || error != nil else { return [] }
        let status: String
        switch error {
        case nil: status = "ok"
        case "quotaNotConfigured": status = "notConfigured"
        case "unauthorized": status = "unauthorized"
        case "sourceRateLimited": status = "sourceRateLimited"
        default: status = "unavailable"
        }
        return [["provider": "codex", "status": status]]
    }
    public static func iso(_ date: Date) -> String {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: date)
    }
    public static func hash(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    private static func text(_ value: Any?) -> String { (value as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
    private static func number(_ value: Any?) -> Double? {
        guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue.isFinite else { return nil }
        return n.doubleValue
    }
    private static func object(_ data: Data) throws -> [String: Any] {
        guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ObservationError.invalidPayload }
        return value
    }
    private static func jwt(_ token: String) -> [String: Any] {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2 else { return [:] }
        var value = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        value += String(repeating: "=", count: (4 - value.count % 4) % 4)
        guard let data = Data(base64Encoded: value) else { return [:] }
        return (try? object(data)) ?? [:]
    }
    public enum ObservationError: Error { case invalidIdentity, invalidPayload }
}
