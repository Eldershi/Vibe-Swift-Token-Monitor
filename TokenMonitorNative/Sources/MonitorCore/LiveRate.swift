import Foundation

/// Matched-counter deltas, per-device, matching v0.56.0 tokenRatePresentation.js.
/// Counts are model-busy-time sums, never elapsed network/watcher wall time.
public struct LiveRateTracker {
    private struct Counters { var tokens: Double; var output: Double; var duration: Double }
    public struct Sample { public var speed: Double; public var burn: Double; public var at: Date; public var idle: Bool }
    private var baselines: [String: Counters] = [:]
    private var samples: [String: Sample] = [:]
    private var last: Sample?
    public init() {}
    public mutating func reset() { baselines = [:]; samples = [:]; last = nil }
    public mutating func observe(_ stats: Stats, now: Date = Date()) {
        let active = stats.devices.filter { !$0.isStale(at: now, threshold: stats.staleAfterMs ?? 600_000) && !$0.periodExpired(.today, at: now) }
        let ids = Set(active.map(\.id))
        if samples.keys.contains(where: { !ids.contains($0) }) { last = nil }
        baselines = baselines.filter { ids.contains($0.key) }
        samples = samples.filter { ids.contains($0.key) }
        for device in active {
            guard let p = device.periods["today"], p.capabilities?["throughput"] != false,
                  let t = p.timedTokens, let o = p.timedOutputTokens, let d = p.timedDurationMs,
                  t >= 0, o >= 0, d >= 0 else {
                baselines[device.id] = nil
                if samples.removeValue(forKey: device.id) != nil { last = nil }
                continue
            }
            let current = Counters(tokens: t, output: o, duration: d)
            defer { baselines[device.id] = current }
            guard let old = baselines[device.id] else { continue }
            let dt = t - old.tokens, dout = o - old.output, dd = d - old.duration
            if dt < 0 || dout < 0 || dd < 0 { samples[device.id] = nil; last = nil; continue }
            guard dd > 0 else { continue }
            samples[device.id] = Sample(speed: min(1e12, dout * 1000 / dd), burn: min(1e12, dt * 60000 / dd), at: now, idle: false)
        }
    }
    public mutating func sample(now: Date = Date()) -> Sample? {
        let active = samples.values.filter { now.timeIntervalSince($0.at) < 8 }
        if !active.isEmpty {
            let result = Sample(speed: min(1e12, active.reduce(0) { $0 + $1.speed }), burn: min(1e12, active.reduce(0) { $0 + $1.burn }), at: active.map(\.at).max()!, idle: false)
            last = result; return result
        }
        guard var retained = last, now.timeIntervalSince(retained.at) < 180 else { return nil }
        retained.idle = true; return retained
    }
}
