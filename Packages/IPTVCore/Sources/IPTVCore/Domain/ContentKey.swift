import Foundation

public enum ContentKind: String {
    case movie
    case series
    case season
    case episode
    case live
}

/// `sourceID|kind|providerID` — the soft foreign key joining every local
/// engagement table (progress, favorites, downloads, ...) to provider-mirror
/// content, namespaced so two different servers/accounts can never collide.
public enum ContentKey {
    public static func make(sourceID: String, kind: ContentKind, providerID: String) -> String {
        "\(sourceID)|\(kind.rawValue)|\(providerID)"
    }
}
