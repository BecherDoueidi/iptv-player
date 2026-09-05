import Foundation

/// One entry from `get_live_streams`.
struct XtreamLiveStreamDTO: Decodable {
    let streamID: String?
    let name: String?
    let streamIcon: String?
    let categoryID: String?
    let number: Int?
    let epgChannelID: String?

    enum CodingKeys: String, CodingKey {
        case streamID = "stream_id"
        case name
        case streamIcon = "stream_icon"
        case categoryID = "category_id"
        case number = "num"
        case epgChannelID = "epg_channel_id"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        streamID = XtreamLenientDecoding.string(container, .streamID)
        name = try? container.decode(String.self, forKey: .name)
        streamIcon = try? container.decode(String.self, forKey: .streamIcon)
        categoryID = XtreamLenientDecoding.string(container, .categoryID)
        number = XtreamLenientDecoding.int(container, .number)
        epgChannelID = XtreamLenientDecoding.string(container, .epgChannelID)
    }
}

struct XtreamShortEPGResponseDTO: Decodable {
    let listings: [XtreamEPGListingDTO]

    enum CodingKeys: String, CodingKey {
        case epgListings = "epg_listings"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        listings = (try? container.decode([XtreamEPGListingDTO].self, forKey: .epgListings)) ?? []
    }
}

/// EPG titles and descriptions come back base64-encoded, and the timestamps arrive
/// either as a unix epoch (`start_timestamp`) or a formatted local string (`start`).
struct XtreamEPGListingDTO: Decodable {
    let id: String?
    let title: String?
    let description: String?
    let startsAt: Date?
    let endsAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case description
        case startTimestamp = "start_timestamp"
        case stopTimestamp = "stop_timestamp"
        case start
        case end
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = XtreamLenientDecoding.string(container, .id)
        title = XtreamLenientDecoding.string(container, .title).map(Self.decodeBase64IfNeeded)
        description = XtreamLenientDecoding.string(container, .description).map(Self.decodeBase64IfNeeded)
        startsAt = Self.date(container, timestampKey: .startTimestamp, textKey: .start)
        endsAt = Self.date(container, timestampKey: .stopTimestamp, textKey: .end)
    }

    /// Panels are inconsistent about whether these fields are encoded at all, so a
    /// value that doesn't decode to valid UTF-8 is treated as already-plain text.
    private static func decodeBase64IfNeeded(_ value: String) -> String {
        guard let data = Data(base64Encoded: value),
              let decoded = String(data: data, encoding: .utf8),
              !decoded.isEmpty
        else {
            return value
        }
        return decoded
    }

    private static let textFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private static func date(
        _ container: KeyedDecodingContainer<CodingKeys>,
        timestampKey: CodingKeys,
        textKey: CodingKeys
    ) -> Date? {
        if let epoch = XtreamLenientDecoding.double(container, timestampKey), epoch > 0 {
            return Date(timeIntervalSince1970: epoch)
        }
        guard let text = XtreamLenientDecoding.string(container, textKey) else { return nil }
        return textFormatter.date(from: text)
    }
}
