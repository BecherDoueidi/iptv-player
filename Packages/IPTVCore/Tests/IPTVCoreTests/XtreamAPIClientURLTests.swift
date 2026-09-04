import XCTest
@testable import IPTVCore

final class XtreamAPIClientURLTests: XCTestCase {
    func testPlayerAPIURLIncludesCredentialsAsQueryItems() throws {
        let credentials = XtreamCredentials(
            serverURL: URL(string: "http://example.com:8080")!,
            username: "alice",
            password: "s3cret"
        )

        let url = try XtreamAPIClient.playerAPIURL(credentials: credentials)
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)

        XCTAssertEqual(components?.path, "/player_api.php")
        XCTAssertEqual(components?.host, "example.com")
        XCTAssertEqual(components?.port, 8080)

        let queryItems = components?.queryItems ?? []
        XCTAssertTrue(queryItems.contains(URLQueryItem(name: "username", value: "alice")))
        XCTAssertTrue(queryItems.contains(URLQueryItem(name: "password", value: "s3cret")))
    }
}
