import XCTest
@testable import IPTVCore

final class XtreamSeriesDecodingTests: XCTestCase {
    func testSeriesSummariesDecodeFullMetadataUpFront() throws {
        let json = """
        [
          {
            "series_id": 55,
            "name": "Example Show",
            "cover": "http://example.com/cover.jpg",
            "backdrop_path": ["http://example.com/backdrop.jpg"],
            "plot": "An example plot.",
            "genre": "Drama",
            "rating": "8.2",
            "category_id": "9"
          }
        ]
        """.data(using: .utf8)!

        let dtos = try JSONDecoder().decode([XtreamSeriesDTO].self, from: json)
        let seriesList = XtreamMapper.makeSeriesSummaries(from: dtos)

        XCTAssertEqual(seriesList.count, 1)
        XCTAssertEqual(seriesList[0].id, "55")
        XCTAssertEqual(seriesList[0].plot, "An example plot.")
        XCTAssertEqual(seriesList[0].rating, 8.2)
        XCTAssertEqual(seriesList[0].backdropURL, URL(string: "http://example.com/backdrop.jpg"))
    }

    func testSeriesInfoGroupsEpisodesBySeasonAndSortsThem() throws {
        let json = """
        {
          "episodes": {
            "1": [
              {"id": "201", "episode_num": 2, "title": "Ep 2", "container_extension": "mkv", "season": 1},
              {"id": "200", "episode_num": 1, "title": "Ep 1", "container_extension": "mkv", "season": 1}
            ],
            "2": [
              {"id": "300", "episode_num": "1", "title": "S2 Ep 1", "container_extension": "mp4"}
            ]
          }
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(XtreamSeriesInfoResponseDTO.self, from: json)
        let detail = XtreamMapper.makeSeriesDetail(id: "55", from: response)

        XCTAssertEqual(detail.seasons.map(\.seasonNumber), [1, 2])
        XCTAssertEqual(detail.seasons[0].episodes.map(\.episodeNumber), [1, 2])
        XCTAssertEqual(detail.seasons[0].episodes[0].title, "Ep 1")
        // Season 2's episode has no "season" field — falls back to the dict key.
        XCTAssertEqual(detail.seasons[1].episodes[0].seasonNumber, 2)
    }

    func testSeriesInfoToleratesEpisodesSentAsEmptyArrayInsteadOfObject() throws {
        // Observed quirk: some panels send "episodes": [] rather than {} when a
        // series has no episodes yet.
        let json = """
        {"episodes": []}
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(XtreamSeriesInfoResponseDTO.self, from: json)
        let detail = XtreamMapper.makeSeriesDetail(id: "55", from: response)

        XCTAssertTrue(detail.seasons.isEmpty)
    }
}
