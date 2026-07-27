import Foundation
import XCTest
@testable import JobhuntCore

/// LinkedIn availability checks are capped per run (TASK-643 pacing). This pins that successive runs
/// COVER the library rather than resampling it — the failure that let job #132 sit undetected.
final class LinkedInRotationTests: XCTestCase {
    private func ids(_ count: Int) -> [String] {
        (0 ..< count).map { String(format: "job-%03d", $0) }
    }

    private func slice(_ specs: [String], offset: Int) -> [String] {
        AvailabilityChecker.linkedInSlice(specs, offset: offset, id: { $0 })
    }

    func testSliceIsCappedAtThePerRunLimit() {
        let result = slice(ids(101), offset: 0)
        XCTAssertEqual(result.count, AvailabilityChecker.maxLinkedInPerRun)
    }

    func testSmallLibrariesAreCheckedEntirely() {
        let all = ids(5)
        XCTAssertEqual(Set(slice(all, offset: 0)), Set(all))
        XCTAssertEqual(Set(slice(all, offset: 999)), Set(all), "offset is irrelevant below the cap")
    }

    /// The core property: consecutive runs return disjoint windows, so nothing is re-checked while
    /// something else waits.
    func testConsecutiveRunsDoNotOverlap() {
        let all = ids(101)
        let cap = AvailabilityChecker.maxLinkedInPerRun
        let first = slice(all, offset: 0)
        let second = slice(all, offset: cap)
        XCTAssertTrue(Set(first).isDisjoint(with: Set(second)), "a run must not repeat the previous window")
    }

    /// Every posting is visited within ceil(count / cap) runs — the guarantee random shuffling lacked.
    func testFullCoverageWithinOneRotation() {
        let all = ids(101)
        let cap = AvailabilityChecker.maxLinkedInPerRun
        let runs = Int(ceil(Double(all.count) / Double(cap)))
        var seen = Set<String>()
        for run in 0 ..< runs {
            seen.formUnion(slice(all, offset: run * cap))
        }
        XCTAssertEqual(seen.count, all.count, "every LinkedIn posting must be checked within \(runs) runs")
    }

    func testRotationWrapsPastTheEnd() {
        let all = ids(20)
        let cap = AvailabilityChecker.maxLinkedInPerRun // 12
        let wrapped = slice(all, offset: cap) // 12..19 then 0..3
        XCTAssertEqual(wrapped.count, cap)
        XCTAssertTrue(wrapped.contains(all[19]), "should reach the tail")
        XCTAssertTrue(wrapped.contains(all[0]), "and wrap around to the start")
    }

    /// The cursor increments forever; it must keep working once it exceeds the library size, and
    /// tolerate a negative value rather than trapping.
    func testLargeAndNegativeOffsetsAreSafe() {
        let all = ids(30)
        XCTAssertEqual(slice(all, offset: 100_000).count, AvailabilityChecker.maxLinkedInPerRun)
        XCTAssertEqual(slice(all, offset: -7).count, AvailabilityChecker.maxLinkedInPerRun)
    }

    func testEmptyLibraryIsHandled() {
        XCTAssertTrue(slice([], offset: 3).isEmpty)
    }

    /// Ordering must not depend on the input order, or the "next" window would drift unpredictably
    /// as jobs are added and removed.
    func testWindowIsStableRegardlessOfInputOrder() {
        let all = ids(40)
        XCTAssertEqual(slice(all, offset: 5), slice(all.reversed(), offset: 5))
    }
}
