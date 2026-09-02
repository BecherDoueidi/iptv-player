import XCTest
@testable import IPTVCore

final class PipelineStatusTests: XCTestCase {
    func testMessageIsNotEmpty() {
        XCTAssertFalse(PipelineStatus.message.isEmpty)
    }
}
