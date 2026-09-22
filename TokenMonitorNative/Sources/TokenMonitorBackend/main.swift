import Foundation
import Network
import Security
import Darwin
import NativeBackendCore

umask(0o077)
let args = CommandLine.arguments
if args.contains("--smoke-test") { print("Token Monitor helper: native Swift runtime OK"); exit(0) }
if args.contains("--hub-secret") { exit(64) }
let directory = ProcessInfo.processInfo.environment["TOKEN_MONITOR_BETA2_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) }
    ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Token Monitor Native Beta 2/Backend", isDirectory: true)
do {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                            attributes: [.posixPermissions: 0o700])
    let lock = open(directory.appendingPathComponent("service.lock").path, O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
    guard lock >= 0, flock(lock, LOCK_EX | LOCK_NB) == 0 else { exit(0) }
    _ = fcntl(lock, F_SETFD, 0)
    let service = try NativeService(directory: directory)
    try service.start()
    dispatchMain()
} catch {
    fputs("Native backend could not start: \(error)\n", stderr)
    exit(1)
}
