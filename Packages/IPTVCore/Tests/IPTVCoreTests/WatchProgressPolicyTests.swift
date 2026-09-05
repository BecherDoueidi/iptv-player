import XCTest
@testable import IPTVCore

final class WatchProgressPolicyTests: XCTestCase {
    func testBelowThresholdIsNotCompleted() {
        XCTAssertFalse(WatchProgressPolicy.isCompleted(positionSeconds: 60, durationSeconds: 100))
    }

    func testAtOrAboveThresholdIsCompleted() {
        XCTAssertTrue(WatchProgressPolicy.isCompleted(positionSeconds: 92, durationSeconds: 100))
        XCTAssertTrue(WatchProgressPolicy.isCompleted(positionSeconds: 100, durationSeconds: 100))
    }

    func testZeroDurationIsNeverCompleted() {
        // Duration not yet known (e.g. still buffering) shouldn't be treated as done.
        XCTAssertFalse(WatchProgressPolicy.isCompleted(positionSeconds: 5, durationSeconds: 0))
    }
}
