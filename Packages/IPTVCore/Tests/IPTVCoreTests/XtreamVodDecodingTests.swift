import XCTest
@testable import IPTVCore

final class XtreamVodDecodingTests: XCTestCase {
    func testCategoriesDecodeWithStringID() throws {
        let json = """
        [{"category_id": "5", "category_name": "Action"}]
        """.data(using: .utf8)!

        let dtos = try JSONDecoder().decode([XtreamCategoryDTO].self, from: json)
        let categories = XtreamMapper.makeCategories(from: dtos)

        XCTAssertEqual(categories, [Category(id: "5", name: "Action")])
    }

    func testCategoriesDecodeWithIntegerID() throws {
        // Some panels send category_id as a real JSON number instead of a string.
        let json = """
        [{"category_id": 5, "category_name": "Action"}]
        """.data(using: .utf8)!

        let dtos = try JSONDecoder().decode([XtreamCategoryDTO].self, from: json)
        let categories = XtreamMapper.makeCategories(from: dtos)

        XCTAssertEqual(categories, [Category(id: "5", name: "Action")])
    }

    func testMovieSummariesDecodeAndToleratesMissingOptionalFields() throws {
        let json = """
        [
          {
            "stream_id": 101,
            "name": "Example Movie",
            "stream_icon": "http://example.com/poster.jpg",
            "rating": "8.5",
            "category_id": "5",
            "container_extension": "mkv",
            "added": "1893456000"
          },
          {
            "stream_id": "102",
            "name": "No Extras Movie"
          }
        ]
        """.data(using: .utf8)!

        let dtos = try JSONDecoder().decode([XtreamVodStreamDTO].self, from: json)
        let movies = XtreamMapper.makeMovieSummaries(from: dtos)

        XCTAssertEqual(movies.count, 2)
        XCTAssertEqual(movies[0].id, "101")
        XCTAssertEqual(movies[0].rating, 8.5)
        XCTAssertEqual(movies[0].posterURL, URL(string: "http://example.com/poster.jpg"))
        XCTAssertEqual(movies[0].addedAt, Date(timeIntervalSince1970: 1_893_456_000))

        XCTAssertEqual(movies[1].id, "102")
        XCTAssertNil(movies[1].posterURL)
        XCTAssertNil(movies[1].rating)
    }

    func testMovieSummaryWithoutIDOrNameIsDropped() throws {
        let json = """
        [{"stream_icon": "http://example.com/poster.jpg"}]
        """.data(using: .utf8)!

        let dtos = try JSONDecoder().decode([XtreamVodStreamDTO].self, from: json)
        let movies = XtreamMapper.makeMovieSummaries(from: dtos)

        XCTAssertTrue(movies.isEmpty)
    }

    func testMovieDetailDecodesFullMetadata() throws {
        let json = """
        {
          "info": {
            "plot": "A thrilling example.",
            "genre": "Action, Thriller",
            "releasedate": "2024-01-01",
            "duration_secs": 7200,
            "backdrop_path": ["http://example.com/backdrop.jpg"],
            "rating": "7.9"
          }
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(XtreamVodInfoResponseDTO.self, from: json)
        let detail = XtreamMapper.makeMovieDetail(id: "101", from: response)

        XCTAssertEqual(detail.plot, "A thrilling example.")
        XCTAssertEqual(detail.durationSeconds, 7200)
        XCTAssertEqual(detail.backdropURL, URL(string: "http://example.com/backdrop.jpg"))
        XCTAssertEqual(detail.rating, 7.9)
    }

    func testMovieDetailMissingInfoProducesEmptyDetail() throws {
        let json = "{}".data(using: .utf8)!

        let response = try JSONDecoder().decode(XtreamVodInfoResponseDTO.self, from: json)
        let detail = XtreamMapper.makeMovieDetail(id: "101", from: response)

        XCTAssertNil(detail.plot)
        XCTAssertNil(detail.backdropURL)
    }
}
