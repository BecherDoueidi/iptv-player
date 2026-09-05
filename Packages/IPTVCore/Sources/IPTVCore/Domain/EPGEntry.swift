import Foundation

/// One programme from a channel's short EPG (`get_short_epg`).
public struct EPGEntry: Identifiable, Equatable, Hashable {
    public let id: String
    public let title: String
    public let description: String?
    public let startsAt: Date?
    public let endsAt: Date?

    public init(id: String, title: String, description: String?, startsAt: Date?, endsAt: Date?) {
        self.id = id
        self.title = title
        self.description = description
        self.startsAt = startsAt
        self.endsAt = endsAt
    }

    public func isOnAir(at date: Date = .now) -> Bool {
        guard let startsAt, let endsAt else { return false }
        return startsAt <= date && date < endsAt
    }
}
