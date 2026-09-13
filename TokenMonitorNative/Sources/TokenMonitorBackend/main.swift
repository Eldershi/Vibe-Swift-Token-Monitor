import Foundation
import Darwin
import Security

// launchd owns this PID; exec keeps the lock and supervision attached to Node.
umask(0o077)
var pathSize: UInt32 = 0
_ = _NSGetExecutablePath(nil, &pathSize)
var executableBytes = [CChar](repeating: 0, count: Int(pathSize))
guard _NSGetExecutablePath(&executableBytes, &pathSize) == 0 else { exit(1) }
let executable = URL(fileURLWithPath: String(cString: executableBytes)).resolvingSymlinksInPath()
let bundle = executable.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
let backend = bundle.appendingPathComponent("Contents/Resources/Backend")
let node = backend.appendingPathComponent("runtime/node").path
if CommandLine.arguments.contains("--smoke-test") {
    guard FileManager.default.isExecutableFile(atPath: node),
          FileManager.default.fileExists(atPath: backend.appendingPathComponent("main.cjs").path) else { exit(1) }
    print("Beta helper: bundled runtime OK"); exit(0)
}
let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    .appendingPathComponent("Token Monitor Native Beta/Backend", isDirectory: true)
let authorizeClaude = CommandLine.arguments.contains("--authorize-claude")
let claudeSecret = CommandLine.arguments.contains("--claude-secret")
if CommandLine.arguments.contains("--hub-secret") { exit(64) }
if claudeSecret || authorizeClaude {
    // Private stdout pipe to the bundled Node process, never the service log.
    guard CommandLine.arguments.count == 2 else { exit(1) }
    // This process performs a single query, so disabling UI cannot affect the app.
    guard SecKeychainSetUserInteractionAllowed(authorizeClaude) == errSecSuccess else { exit(1) }
    let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "Claude Code-credentials",
        kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne,
        kSecUseAuthenticationUI as String: authorizeClaude ? kSecUseAuthenticationUIAllow : kSecUseAuthenticationUIFail]
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    if status == errSecItemNotFound { exit(44) }
    guard status == errSecSuccess, let secret = item as? Data else { exit(1) }
    if !authorizeClaude { FileHandle.standardOutput.write(secret) }
    exit(0)
}
do {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                          attributes: [.posixPermissions: 0o700])
    let lock = open(directory.appendingPathComponent("service.lock").path, O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
    guard lock >= 0, flock(lock, LOCK_EX | LOCK_NB) == 0 else { exit(0) }
    _ = fcntl(lock, F_SETFD, 0)
    let log = directory.appendingPathComponent("backend.log")
    if let size = try? log.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 1_048_576 {
        let previous = directory.appendingPathComponent("backend.previous.log")
        try? FileManager.default.removeItem(at: previous)
        try? FileManager.default.moveItem(at: log, to: previous)
    }
    let output = open(log.path, O_CREAT | O_WRONLY | O_APPEND | O_NOFOLLOW, 0o600)
    if output >= 0 { dup2(output, STDOUT_FILENO); dup2(output, STDERR_FILENO); close(output) }
    // Do not inherit a shell's upstream collector configuration or runtime injection.
    for key in ProcessInfo.processInfo.environment.keys where key.hasPrefix("TOKEN_MONITOR_") || key.hasPrefix("TOKSCALE_") || key.hasPrefix("NODE_") {
        unsetenv(key)
    }
    setenv("NODE_USE_SYSTEM_CA", "1", 1)
    setenv("TOKEN_MONITOR_BETA_DIR", directory.path, 1)
    setenv("TOKEN_MONITOR_SHARED_DIR", directory.path, 1)
    setenv("TOKSCALE_CONFIG_DIR", directory.appendingPathComponent("tokscale").path, 1)
    setenv("PATH", "/usr/bin:/bin:/usr/sbin:/sbin", 1)
    _ = chdir(backend.path)
    let args = [node, backend.appendingPathComponent("main.cjs").path]
    let argv = args.map { strdup($0) } + [nil]
    argv.withUnsafeBufferPointer { _ = execv(node, $0.baseAddress!) }
    fputs("Beta helper could not execute bundled runtime (errno \(errno)).\n", stderr)
    exit(1)
} catch {
    fputs("Beta helper could not prepare its data directory.\n", stderr)
    exit(1)
}
