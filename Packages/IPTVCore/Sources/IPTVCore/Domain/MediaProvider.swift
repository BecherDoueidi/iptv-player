import Foundation

/// Provider-agnostic surface the rest of the app talks to. Concrete Xtream-specific
/// behavior (URL conventions, quirky JSON) lives entirely behind `XtreamProvider` —
/// nothing outside `XtreamProvider/` should ever need to know it's Xtream underneath.
public protocol MediaProvider {
    func authenticate(credentials: XtreamCredentials) async throws -> AccountInfo
}
