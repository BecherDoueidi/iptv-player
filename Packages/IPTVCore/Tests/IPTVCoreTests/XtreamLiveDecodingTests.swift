import XCTest
@testable import IPTVCore

final class XtreamLiveDecodingTests: XCTestCase {
    private func decode<T: Decodable>(_ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    func testDecodesLiveStreamsWithMixedNumericTypes() throws {
        // `stream_id` as a number on one entry and a string on the next is normal
        // across panel forks — both must survive.
        let json = """
        [
          {"num": 1, "name": "BBC One", "stream_id": 1234, "stream_icon": "http://x/y.png",
           "epg_channel_id": "bbc1.uk", "category_id": "5"},
          {"num": "2", "name": "ITV", "stream_id": "9999", "stream_icon": "",
           "epg_channel_id": "", "category_id": 5}
        ]
        """
        let dtos: [XtreamLiveStreamDTO] = try decode(json)
        let channels = XtreamMapper.makeLiveChannels(from: dtos)

        XCTAssertEqual(channels.count, 2)
        XCTAssertEqual(channels[0].id, "1234")
        XCTAssertEqual(channels[0].number, 1)
        XCTAssertEqual(channels[0].epgChannelID, "bbc1.uk")
        XCTAssertEqual(channels[1].id, "9999")
        XCTAssertEqual(channels[1].number, 2)
        XCTAssertEqual(channels[1].categoryID, "5")
        // An empty epg_channel_id means "no EPG mapping", not a channel called "".
        XCTAssertNil(channels[1].epgChannelID)
    }

    func testSkipsEntriesMissingIdentityFields() throws {
        let json = """
        [{"name": "No ID Channel"}, {"stream_id": 7, "name": "Fine"}]
        """
        let dtos: [XtreamLiveStreamDTO] = try decode(json)
        XCTAssertEqual(XtreamMapper.makeLiveChannels(from: dtos).map(\.id), ["7"])
    }

    func testDecodesBase64EPGTitlesAndEpochTimestamps() throws {
        // "News at Ten" / "The headlines." base64-encoded, as panels send them.
        let json = """
        {"epg_listings": [
          {"id": "2", "title": "TmV3cyBhdCBUZW4=", "description": "VGhlIGhlYWRsaW5lcy4=",
           "start_timestamp": "1757000000", "stop_timestamp": 1757003600},
          {"id": "1", "title": "RWFybGllcg==", "start_timestamp": 1756996400, "stop_timestamp": 1757000000}
        ]}
        """
        let response: XtreamShortEPGResponseDTO = try decode(json)
        let entries = XtreamMapper.makeEPGEntries(from: response)

        // Sorted by start time, so the earlier programme comes first regardless of
        // the order the panel listed them in.
        XCTAssertEqual(entries.map(\.title), ["Earlier", "News at Ten"])
        XCTAssertEqual(entries[1].description, "The headlines.")
        XCTAssertEqual(entries[1].startsAt, Date(timeIntervalSince1970: 1_757_000_000))
        XCTAssertEqual(entries[1].endsAt, Date(timeIntervalSince1970: 1_757_003_600))
    }

    func testTreatsNonBase64EPGTitlesAsPlainText() throws {
        let json = """
        {"epg_listings": [{"id": "1", "title": "Live Football", "start": "2026-09-05 20:00:00", "end": "2026-09-05 22:00:00"}]}
        """
        let response: XtreamShortEPGResponseDTO = try decode(json)
        let entries = XtreamMapper.makeEPGEntries(from: response)

        XCTAssertEqual(entries.first?.title, "Live Football")
        XCTAssertNotNil(entries.first?.startsAt)
    }

    func testMissingEPGListingsDecodesAsEmptyRatherThanThrowing() throws {
        let response: XtreamShortEPGResponseDTO = try decode("{}")
        XCTAssertTrue(XtreamMapper.makeEPGEntries(from: response).isEmpty)
    }

    func testIsOnAirBracketsTheCurrentTime() {
        let start = Date(timeIntervalSince1970: 1_000)
        let entry = EPGEntry(id: "1", title: "Show", description: nil, startsAt: start, endsAt: start.addingTimeInterval(600))

        XCTAssertTrue(entry.isOnAir(at: start))
        XCTAssertTrue(entry.isOnAir(at: start.addingTimeInterval(599)))
        XCTAssertFalse(entry.isOnAir(at: start.addingTimeInterval(600)))
        XCTAssertFalse(entry.isOnAir(at: start.addingTimeInterval(-1)))
    }
}
