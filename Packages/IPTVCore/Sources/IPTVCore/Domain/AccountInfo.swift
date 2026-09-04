import Foundation

public struct AccountInfo: Equatable {
    public let isAuthenticated: Bool
    public let status: String?
    public let isTrial: Bool?
    public let expiresAt: Date?
    public let activeConnections: Int?
    public let maxConnections: Int?
    public let message: String?

    public init(
        isAuthenticated: Bool,
        status: String? = nil,
        isTrial: Bool? = nil,
        expiresAt: Date? = nil,
        activeConnections: Int? = nil,
        maxConnections: Int? = nil,
        message: String? = nil
    ) {
        self.isAuthenticated = isAuthenticated
        self.status = status
        self.isTrial = isTrial
        self.expiresAt = expiresAt
        self.activeConnections = activeConnections
        self.maxConnections = maxConnections
        self.message = message
    }
}
