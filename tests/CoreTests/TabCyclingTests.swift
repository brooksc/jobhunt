import XCTest
@testable import JobhuntCore

/// TASK-499: the pure index math behind job-detail ⌃Tab / ⌃⇧Tab cycling.
final class TabCyclingTests: XCTestCase {
    func testForwardAdvancesAndWraps() {
        XCTAssertEqual(TabCycling.next(count: 5, from: 0, forward: true), 1)
        XCTAssertEqual(TabCycling.next(count: 5, from: 3, forward: true), 4)
        XCTAssertEqual(TabCycling.next(count: 5, from: 4, forward: true), 0, "wraps past the end")
    }

    func testBackwardRetreatsAndWraps() {
        XCTAssertEqual(TabCycling.next(count: 5, from: 4, forward: false), 3)
        XCTAssertEqual(TabCycling.next(count: 5, from: 1, forward: false), 0)
        XCTAssertEqual(TabCycling.next(count: 5, from: 0, forward: false), 4, "wraps before the start")
    }

    func testHandlesEdgeCounts() {
        XCTAssertEqual(TabCycling.next(count: 0, from: 0, forward: true), 0, "empty set is a no-op")
        XCTAssertEqual(TabCycling.next(count: 1, from: 0, forward: true), 0, "single tab stays put")
        XCTAssertEqual(TabCycling.next(count: 1, from: 0, forward: false), 0)
    }

    func testClampsOutOfRangeIndex() {
        // A stale index (e.g. a tab that became hidden) is clamped before cycling.
        XCTAssertEqual(TabCycling.next(count: 3, from: 9, forward: true), 0)
        // clamp(-2) → 0, then step backward with wraparound → 2.
        XCTAssertEqual(TabCycling.next(count: 3, from: -2, forward: false), 2)
    }
}
