import Foundation
import CryptoKit

// Explicit provisioning only. Builds never create or replace a signing identity.
guard CommandLine.arguments.count == 3 else { fatalError("Usage: update-signing-key.swift PRIVATE_FILE PUBLIC_FILE") }
let privateURL = URL(fileURLWithPath: CommandLine.arguments[1])
let publicURL = URL(fileURLWithPath: CommandLine.arguments[2])
let manager = FileManager.default
let identity: Curve25519.Signing.PrivateKey
if manager.fileExists(atPath: privateURL.path) {
    let encoded = try String(contentsOf: privateURL, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
    guard let data = Data(base64Encoded: encoded) else { fatalError("Invalid signing key") }
    identity = try Curve25519.Signing.PrivateKey(rawRepresentation: data)
} else {
    guard !manager.fileExists(atPath: publicURL.path) else { fatalError("Public key already exists; restore the original private key instead of rotating it") }
    try manager.createDirectory(at: privateURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    identity = Curve25519.Signing.PrivateKey()
    guard manager.createFile(atPath: privateURL.path, contents: Data(identity.rawRepresentation.base64EncodedString().utf8), attributes: [.posixPermissions: 0o600]) else { fatalError("Cannot save signing key") }
}
let encoded = identity.publicKey.rawRepresentation.base64EncodedString() + "\n"
if manager.fileExists(atPath: publicURL.path) {
    guard try String(contentsOf: publicURL, encoding: .utf8) == encoded else { fatalError("Signing key does not match the pinned public key") }
} else { try encoded.write(to: publicURL, atomically: true, encoding: .utf8) }
print("Update signing identity ready; private key was not printed.")
