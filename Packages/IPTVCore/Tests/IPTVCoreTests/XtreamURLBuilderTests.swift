import XCTest
@testable import IPTVCore

final class XtreamURLBuilderTests: XCTestCase {
    private let credentials = XtreamCredentials(
        serverURL: URL(string: "http://example.com:8080")!,
        username: "alice",
        password: "s3cret"
    )

    func testMovieStreamURLUsesMovieConventionAndContainerExtension() {
        let url = XtreamURLBuilder.movieStreamURL(credentials: credentials, movieID: "101", containerExtension: "mkv")
        XCTAssertEqual(url?.absoluteString, "http://example.com:8080/movie/alice/s3cret/101.mkv")
    }

    func testEpisodeStreamURLUsesSeriesConvention() {
        let url = XtreamURLBuilder.episodeStreamURL(credentials: credentials, episodeID: "202", containerExtension: "mp4")
        XCTAssertEqual(url?.absoluteString, "http://example.com:8080/series/alice/s3cret/202.mp4")
    }

    func testMissingContainerExtensionFallsBackToMP4() {
        let url = XtreamURLBuilder.movieStreamURL(credentials: credentials, movieID: "101", containerExtension: nil)
        XCTAssertEqual(url?.absoluteString, "http://example.com:8080/movie/alice/s3cret/101.mp4")
    }
}
