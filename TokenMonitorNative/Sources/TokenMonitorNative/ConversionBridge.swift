import Foundation
import MonitorCore

/// Uses the new bundle's converter when a resident older backend has no endpoint.
/// A bounded child process shares the conversion ledger and exits after each call.
enum ConversionBridge {
    static func request(_ body: Data?, directory: URL, resources: URL) async throws -> Data {
        try await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = resources.appendingPathComponent("Backend/runtime/node")
            process.arguments = [resources.appendingPathComponent("Backend/conversion/bridge.cjs").path, directory.path]
            process.environment = ["HOME": NSHomeDirectory(), "PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "NODE_USE_SYSTEM_CA": "1"]
            let input = Pipe(), output = Pipe()
            process.standardInput = input; process.standardOutput = output; process.standardError = FileHandle.nullDevice
            try process.run()
            input.fileHandleForWriting.write(body ?? Data()); try? input.fileHandleForWriting.close()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0, data.count <= 16_777_216 else { throw HubError.disconnected }
            return data
        }.value
    }
}
