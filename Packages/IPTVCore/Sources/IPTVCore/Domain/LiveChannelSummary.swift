import Foundation

/// One entry from Xtream's live channel list (`get_live_streams`).
public struct LiveChannelSummary: Identifiable, Equatable, Hashable {
    public let id: String
    public let categoryID: String?
    public let name: String
    public let logoURL: URL?
    /// Channel number as the panel orders them. Not unique and often absent, so it's
    /// a display/sort hint only — never an identity.
    public let number: Int?
    /// Present when the panel has EPG data mapped for this channel.
    public let epgChannelID: String?

    public init(
        id: String,
        categoryID: String?,
        name: String,
        logoURL: URL?,
        number: Int?,
        epgChannelID: String?
    ) {
        self.id = id
        self.categoryID = categoryID
        self.name = name
        self.logoURL = logoURL
        self.number = number
        self.epgChannelID = epgChannelID
    }
}
