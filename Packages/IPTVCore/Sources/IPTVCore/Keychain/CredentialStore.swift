import Foundation

public protocol CredentialStore {
    func save(_ credentials: XtreamCredentials) throws
    func loadCredentials() throws -> XtreamCredentials?
    func clear() throws
}
