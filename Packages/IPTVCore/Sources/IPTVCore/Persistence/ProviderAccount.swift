import Foundation
import SwiftData

@Model
public class ProviderAccount {
    @Attribute(.unique) public var sourceID: String
    public var serverURLString: String
    public var username: String
    public var accountStatus: String?
    public var isTrial: Bool?
    public var expiresAt: Date?
    public var lastSuccessfulSyncAt: Date?
    public var createdAt: Date

    public init(
        sourceID: String,
        serverURLString: String,
        username: String,
        accountStatus: String? = nil,
        isTrial: Bool? = nil,
        expiresAt: Date? = nil,
        lastSuccessfulSyncAt: Date? = nil,
        createdAt: Date = .now
    ) {
        self.sourceID = sourceID
        self.serverURLString = serverURLString
        self.username = username
        self.accountStatus = accountStatus
        self.isTrial = isTrial
        self.expiresAt = expiresAt
        self.lastSuccessfulSyncAt = lastSuccessfulSyncAt
        self.createdAt = createdAt
    }
}
