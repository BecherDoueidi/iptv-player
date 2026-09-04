import XCTest
@testable import IPTVCore

final class SourceIDTests: XCTestCase {
    func testSameInputsProduceSameID() {
        let url = URL(string: "http://example.com:8080")!
        let first = SourceID.make(serverURL: url, username: "alice")
        let second = SourceID.make(serverURL: url, username: "alice")
        XCTAssertEqual(first, second)
    }

    func testDifferentUsernamesProduceDifferentIDs() {
        let url = URL(string: "http://example.com:8080")!
        let alice = SourceID.make(serverURL: url, username: "alice")
        let bob = SourceID.make(serverURL: url, username: "bob")
        XCTAssertNotEqual(alice, bob)
    }

    func testDifferentHostsProduceDifferentIDs() {
        let a = SourceID.make(serverURL: URL(string: "http://a.example.com:8080")!, username: "alice")
        let b = SourceID.make(serverURL: URL(string: "http://b.example.com:8080")!, username: "alice")
        XCTAssertNotEqual(a, b)
    }
}
