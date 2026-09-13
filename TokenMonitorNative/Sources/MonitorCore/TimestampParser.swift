import Foundation

/// One bounded, synchronized cache for all report/expiry timestamps, including invalid values.
/// Formatters are never shared without the lock: Foundation formatters are mutable objects.
final class TimestampParser: @unchecked Sendable {
    static let shared = TimestampParser()
    private enum Entry { case valid(Date), invalid }
    private let lock = NSLock()
    private let fractional = ISO8601DateFormatter()
    private let integral = ISO8601DateFormatter()
    private var cache: [String: Entry] = [:]
    private let capacity: Int
    private var missCount = 0
    var misses: Int { lock.lock(); defer { lock.unlock() }; return missCount }
    init(capacity: Int = 512) {
        self.capacity = max(1, capacity)
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        integral.formatOptions = [.withInternetDateTime]
    }
    func parse(_ value: String) -> Date? {
        lock.lock(); defer { lock.unlock() }
        if let hit = cache[value] {
            if case .valid(let date) = hit { return date }
            return nil
        }
        missCount += 1
        let date = fractional.date(from: value) ?? integral.date(from: value)
        if cache.count >= capacity { cache.removeAll(keepingCapacity: true) }
        cache[value] = date.map(Entry.valid) ?? .invalid
        return date
    }
    var cachedCount: Int { lock.lock(); defer { lock.unlock() }; return cache.count }
}
