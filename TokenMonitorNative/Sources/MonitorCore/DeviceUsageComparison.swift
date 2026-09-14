import Foundation

public enum DeviceUsageComparison {
    public static func fractions(devices: [Device], tool: String, period: Period, now: Date) -> [String: Double] {
        let values = devices.compactMap { device -> (String, Double)? in
            guard !device.periodExpired(period, at: now),
                  let value = device.periods[period.rawValue]?.tokens(tool: tool),
                  value.isFinite, value >= 0 else { return nil }
            return (device.id, value)
        }
        let maximum = values.map(\.1).max() ?? 0
        return Dictionary(uniqueKeysWithValues: values.map { ($0.0, maximum > 0 ? $0.1 / maximum : 0) })
    }
}
