import Foundation

public struct XtreamCredentials: Codable, Equatable {
    public let serverURL: URL
    public let username: String
    public let password: String

    public init(serverURL: URL, username: String, password: String) {
        self.serverURL = serverURL
        self.username = username
        self.password = password
    }
}
