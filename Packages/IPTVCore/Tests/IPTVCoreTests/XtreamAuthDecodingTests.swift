import XCTest
@testable import IPTVCore

final class XtreamAuthDecodingTests: XCTestCase {
    func testWellFormedResponseDecodesAndMapsToAuthenticatedAccount() throws {
        let json = """
        {
          "user_info": {
            "username": "testuser",
            "message": "",
            "auth": 1,
            "status": "Active",
            "exp_date": "1893456000",
            "is_trial": "0",
            "active_cons": "0",
            "max_connections": "1"
          }
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(XtreamAuthResponseDTO.self, from: json)
        let account = XtreamMapper.makeAccountInfo(from: response)

        XCTAssertTrue(account.isAuthenticated)
        XCTAssertEqual(account.status, "Active")
        XCTAssertEqual(account.isTrial, false)
        XCTAssertEqual(account.maxConnections, 1)
        XCTAssertEqual(account.expiresAt, Date(timeIntervalSince1970: 1_893_456_000))
    }

    func testQuirkyNumericTypesStillDecode() throws {
        // Some panels send numbers/bools as real JSON types instead of strings, and
        // exp_date as null for unlimited accounts. Must not crash or fail to decode.
        let json = """
        {
          "user_info": {
            "username": "testuser",
            "auth": 1,
            "status": "Active",
            "exp_date": null,
            "is_trial": false,
            "active_cons": 0,
            "max_connections": 1
          }
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(XtreamAuthResponseDTO.self, from: json)
        let account = XtreamMapper.makeAccountInfo(from: response)

        XCTAssertTrue(account.isAuthenticated)
        XCTAssertNil(account.expiresAt)
        XCTAssertEqual(account.isTrial, false)
        XCTAssertEqual(account.maxConnections, 1)
    }

    func testInvalidCredentialsAreNotAuthenticated() throws {
        let json = """
        {
          "user_info": {
            "auth": 0,
            "status": "Expired",
            "message": "Invalid username or password"
          }
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(XtreamAuthResponseDTO.self, from: json)
        let account = XtreamMapper.makeAccountInfo(from: response)

        XCTAssertFalse(account.isAuthenticated)
        XCTAssertEqual(account.message, "Invalid username or password")
    }

    func testMissingUserInfoIsTreatedAsUnauthenticated() throws {
        let json = "{}".data(using: .utf8)!

        let response = try JSONDecoder().decode(XtreamAuthResponseDTO.self, from: json)
        let account = XtreamMapper.makeAccountInfo(from: response)

        XCTAssertFalse(account.isAuthenticated)
    }

    func testGarbageResponseThrowsRatherThanCrashing() {
        let garbage = "<html><body>502 Bad Gateway</body></html>".data(using: .utf8)!

        XCTAssertThrowsError(try JSONDecoder().decode(XtreamAuthResponseDTO.self, from: garbage))
    }
}
