import XCTest
@testable import IPTVCore

final class KeychainCredentialStoreTests: XCTestCase {
    private func makeStore() -> KeychainCredentialStore {
        // A dedicated service/account per test run avoids clashing with any real
        // credentials a developer might have stored under the app's default keys.
        KeychainCredentialStore(
            service: "com.personal.iptvplayer.tests",
            account: "xtream-credentials-test"
        )
    }

    override func tearDownWithError() throws {
        try makeStore().clear()
    }

    func testSaveThenLoadRoundTripsCredentials() throws {
        let store = makeStore()
        let credentials = XtreamCredentials(
            serverURL: URL(string: "http://example.com:8080")!,
            username: "alice",
            password: "s3cret"
        )

        try store.save(credentials)
        let loaded = try store.loadCredentials()

        XCTAssertEqual(loaded, credentials)
    }

    func testLoadReturnsNilWhenNothingStored() throws {
        let store = makeStore()
        try store.clear()

        XCTAssertNil(try store.loadCredentials())
    }

    func testClearRemovesStoredCredentials() throws {
        let store = makeStore()
        try store.save(XtreamCredentials(
            serverURL: URL(string: "http://example.com")!,
            username: "alice",
            password: "s3cret"
        ))

        try store.clear()

        XCTAssertNil(try store.loadCredentials())
    }
}
