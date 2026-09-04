import Foundation
import CryptoKit

/// Namespaces provider-issued content IDs so two different servers/accounts can never
/// collide in local storage — Xtream content IDs are only unique within one panel's
/// own database. Used as the prefix of every `contentKey` from later phases onward.
public enum SourceID {
    public static func make(serverURL: URL, username: String) -> String {
        let host = (serverURL.host ?? "").lowercased()
        let port = serverURL.port.map(String.init) ?? ""
        let raw = "\(host):\(port)|\(username)"
        let digest = SHA256.hash(data: Data(raw.utf8))
        return digest.map { String(format: "%02x", $0) }.joined().prefix(16).description
    }
}
