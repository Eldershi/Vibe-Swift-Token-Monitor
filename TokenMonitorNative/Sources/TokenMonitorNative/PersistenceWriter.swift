import Foundation
import MonitorCore

/// File encoding and writes run off the main actor. Revisions reject obsolete queued writes.
actor PersistenceWriter {
    private var preferenceRevisions: [URL: UInt64] = [:]
    @discardableResult func savePreferences(_ value: Preferences, to url: URL, revision: UInt64 = 0) throws -> Bool {
        guard revision >= preferenceRevisions[url, default: 0] else { return false }
        try PreferencesFile(url: url).save(value)
        preferenceRevisions[url] = revision
        return true
    }
    private var cacheRevisions: [URL: UInt64] = [:]
    func saveCache<T: Encodable & Sendable>(_ value: T, to url: URL, revision: UInt64 = 0) throws {
        guard revision >= cacheRevisions[url, default: 0] else { return }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(value).write(to: url, options: .atomic)
        cacheRevisions[url] = revision
    }
}
