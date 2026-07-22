import XCTest
@testable import JobhuntCore

/// TASK-463: adaptive runtime concurrency state machine.
final class AdaptiveConcurrencyTests: XCTestCase {
    func testStartsAtCeiling() {
        XCTAssertEqual(AdaptiveConcurrency(ceiling: 3).effective, 3)
    }

    // TASK-609: start at a conservative floor below a raised ceiling and probe upward.
    func testStartsAtFloorBelowCeiling() {
        XCTAssertEqual(AdaptiveConcurrency(ceiling: 8).effective, 3, "default floor is 3, not the ceiling")
        XCTAssertEqual(AdaptiveConcurrency(ceiling: 8, floor: 2).effective, 2)
    }

    func testFloorClampedToCeiling() {
        // A floor above the ceiling can't exceed it (e.g. LM Studio ceiling 1).
        XCTAssertEqual(AdaptiveConcurrency(ceiling: 1).effective, 1)
    }

    func testProbesUpFromFloorToCeilingOnSustainedSuccess() {
        var a = AdaptiveConcurrency(ceiling: 8, floor: 3, promoteAfter: 2)
        XCTAssertEqual(a.effective, 3)
        // Each 2 successes steps up one, until the ceiling.
        for expected in 4 ... 8 {
            a.onSuccess(); a.onSuccess()
            XCTAssertEqual(a.effective, expected)
        }
        // Further successes never exceed the ceiling.
        for _ in 0 ..< 10 {
            a.onSuccess()
        }
        XCTAssertEqual(a.effective, 8)
    }

    func testRateLimitDropsToOne() {
        var a = AdaptiveConcurrency(ceiling: 5)
        a.onRateLimit()
        XCTAssertEqual(a.effective, 1)
    }

    func testPromotesAfterKConsecutiveSuccesses() {
        var a = AdaptiveConcurrency(ceiling: 3, promoteAfter: 10)
        a.onRateLimit()
        XCTAssertEqual(a.effective, 1)
        // 9 successes: not yet promoted.
        for _ in 0 ..< 9 {
            a.onSuccess()
        }
        XCTAssertEqual(a.effective, 1)
        // 10th success: step up one.
        a.onSuccess()
        XCTAssertEqual(a.effective, 2)
        // Another 10 → up to ceiling.
        for _ in 0 ..< 10 {
            a.onSuccess()
        }
        XCTAssertEqual(a.effective, 3)
    }

    func testNeverExceedsCeiling() {
        var a = AdaptiveConcurrency(ceiling: 2, promoteAfter: 1)
        for _ in 0 ..< 50 {
            a.onSuccess()
        }
        XCTAssertEqual(a.effective, 2)
    }

    func testFailureResetsPromotionStreakButNotConcurrency() {
        var a = AdaptiveConcurrency(ceiling: 3, promoteAfter: 3)
        a.onRateLimit() // → 1
        a.onSuccess(); a.onSuccess() // 2 in a row
        a.onFailure() // streak reset, still at 1
        XCTAssertEqual(a.effective, 1)
        a.onSuccess(); a.onSuccess() // only 2 again, not yet 3
        XCTAssertEqual(a.effective, 1)
        a.onSuccess() // now 3 in a row → promote
        XCTAssertEqual(a.effective, 2)
    }

    func testNoRateLimit_staysAtCeiling() {
        // AC#5: with no 429, effective never changes from the ceiling.
        var a = AdaptiveConcurrency(ceiling: 3)
        for _ in 0 ..< 100 {
            a.onSuccess()
        }
        XCTAssertEqual(a.effective, 3)
    }

    func testRateLimitAfterRecoveryDropsAgain() {
        var a = AdaptiveConcurrency(ceiling: 4, promoteAfter: 2)
        a.onRateLimit()
        for _ in 0 ..< 2 {
            a.onSuccess()
        } // → 2
        XCTAssertEqual(a.effective, 2)
        a.onRateLimit() // back to 1
        XCTAssertEqual(a.effective, 1)
    }

    func testCeilingClampedToAtLeastOne() {
        XCTAssertEqual(AdaptiveConcurrency(ceiling: 0).effective, 1)
    }
}
