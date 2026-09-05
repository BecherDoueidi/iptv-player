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

    func testLiveStreamURLUsesLiveConventionAndTransportStreamExtension() {
        let url = XtreamURLBuilder.liveStreamURL(credentials: credentials, channelID: "303")
        XCTAssertEqual(url?.absoluteString, "http://example.com:8080/live/alice/s3cret/303.ts")
    }

    func testMissingContainerExtensionFallsBackToMP4() {
        let url = XtreamURLBuilder.movieStreamURL(credentials: credentials, movieID: "101", containerExtension: nil)
        XCTAssertEqual(url?.absoluteString, "http://example.com:8080/movie/alice/s3cret/101.mp4")
    }

    func testSpecialCharactersInCredentialsAreEscapedNotLeftRaw() {
        // A "/" left un-escaped in the password would corrupt the path structure
        // (extra segment boundary); "+" and "@" are also realistic for
        // panel-generated passwords and must not break the URL.
        let credentials = XtreamCredentials(
            serverURL: URL(string: "http://example.com:8080")!,
            username: "user@name",
            password: "p+ss/word"
        )
        let url = XtreamURLBuilder.movieStreamURL(credentials: credentials, movieID: "101", containerExtension: "mp4")

        XCTAssertNotNil(url)
        // Check the *encoded* path (not `.path`, which decodes it back) — exactly 4
        // segments (movie, user, pass, 101.mp4). A raw, unescaped "/" in the password
        // would have produced 5 by splitting the password into two segments.
        let encodedPath = url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.percentEncodedPath }
        let pathSegments = encodedPath?.split(separator: "/").map(String.init) ?? []
        XCTAssertEqual(pathSegments.count, 4)
        XCTAssertEqual(pathSegments[0], "movie")
    }
}
