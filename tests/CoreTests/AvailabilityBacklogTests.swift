import Foundation
import XCTest
@testable import JobhuntCore

/// A sweep deliberately doesn't answer everything — LinkedIn goes twelve per run, and a throttled
/// board yields "don't know" — so postings are routinely left in an unknown state. The backlog is
/// what lets a background pass finish the job and report once at the end.
final class AvailabilityBacklogTests: XCTestCase {
    private func gone(_ id: String) -> GoneJobResult {
        GoneJobResult(
            jobID: id, jobNumber: nil, company: nil, title: id,
            url: URL(string: "https://jobs.test/\(id)")!, reason: "no longer listed"
        )
    }

    private func unverified(_ id: String, _ reason: UnverifiedReason) -> UnverifiedJobResult {
        UnverifiedJobResult(
            jobID: id, jobNumber: nil, company: nil, title: id,
            url: URL(string: "https://jobs.test/\(id)")!, reason: reason, detail: "d"
        )
    }

    func testStartsDrainedAndSilent() {
        let backlog = AvailabilityBacklog()
        XCTAssertTrue(backlog.isDrained)
        XCTAssertFalse(backlog.hasFindings)
    }

    /// Deferred LinkedIn postings and transient failures are what a later pass can actually resolve.
    func testRetryableOutcomesBecomePending() {
        var backlog = AvailabilityBacklog()
        backlog.absorb(AvailabilitySweep(
            gone: [gone("a")],
            unverified: [
                unverified("b", .notCheckedThisRun),
                unverified("c", .rateLimited),
                unverified("d", .unreachable)
            ],
            checkedCount: 1
        ))
        XCTAssertEqual(backlog.pendingJobIDs, ["b", "c", "d"])
        XCTAssertEqual(backlog.gone.map(\.jobID), ["a"])
        XCTAssertFalse(backlog.isDrained)
    }

    /// A bot-challenge page and a client-rendered shell answer identically in twenty minutes, and a
    /// job with no URL can never be checked — retrying any of them is noise against a rate limit.
    func testUnretryableOutcomesAreNotQueued() {
        var backlog = AvailabilityBacklog()
        backlog.absorb(AvailabilitySweep(
            gone: [],
            unverified: [
                unverified("b", .botChallenge),
                unverified("c", .unreadablePage),
                unverified("d", .noURL)
            ],
            checkedCount: 0
        ))
        XCTAssertTrue(backlog.isDrained, "nothing here gets a different answer by asking again")
    }

    /// The pending set is replaced, not appended to — otherwise every pass grows it and the drain
    /// never finishes.
    func testPendingSetIsReplacedByEachPass() {
        var backlog = AvailabilityBacklog()
        backlog.absorb(AvailabilitySweep(
            gone: [], unverified: [unverified("b", .notCheckedThisRun), unverified("c", .rateLimited)]
        ))
        // Second pass answers b and defers only c.
        backlog.absorb(AvailabilitySweep(
            gone: [gone("b")], unverified: [unverified("c", .rateLimited)]
        ))
        XCTAssertEqual(backlog.pendingJobIDs, ["c"])
        XCTAssertEqual(backlog.gone.map(\.jobID), ["b"])
    }

    /// Findings accumulate across passes, which is the whole point — the user gets one report at the
    /// end covering everything the drain turned up.
    func testFindingsAccumulateAcrossPassesWithoutDuplicates() {
        var backlog = AvailabilityBacklog()
        backlog.absorb(AvailabilitySweep(gone: [gone("a")], unverified: [unverified("b", .rateLimited)]))
        backlog.absorb(AvailabilitySweep(gone: [gone("b")], unverified: []))
        // A pass that re-reports an already-known one must not double it.
        backlog.absorb(AvailabilitySweep(gone: [gone("a"), gone("b")], unverified: []))

        XCTAssertEqual(backlog.gone.map(\.jobID), ["a", "b"])
        XCTAssertTrue(backlog.isDrained)
        XCTAssertTrue(backlog.hasFindings)
    }

    /// A drain that finds nothing must stay silent rather than announcing zero.
    func testDrainWithNoFindingsHasNothingToReport() {
        var backlog = AvailabilityBacklog()
        backlog.absorb(AvailabilitySweep(gone: [], unverified: [unverified("b", .notCheckedThisRun)]))
        backlog.absorb(AvailabilitySweep(gone: [], unverified: []))
        XCTAssertTrue(backlog.isDrained)
        XCTAssertFalse(backlog.hasFindings)
    }

    /// Batches are small on purpose: the point is to be gentler than the sweep that got throttled.
    func testNextBatchIsBounded() {
        var backlog = AvailabilityBacklog()
        let pending = (0 ..< 30).map { unverified("j\($0)", .notCheckedThisRun) }
        backlog.absorb(AvailabilitySweep(gone: [], unverified: pending))

        XCTAssertEqual(backlog.nextBatch(limit: 5), ["j0", "j1", "j2", "j3", "j4"])
        XCTAssertEqual(backlog.nextBatch(limit: 0).count, 1, "a zero limit must still make progress")
        XCTAssertEqual(backlog.nextBatch(limit: 100).count, 30)
    }

    /// Once reported, findings clear so the next drain reports only what it newly finds.
    func testFindingsClearAfterReporting() {
        var backlog = AvailabilityBacklog()
        backlog.absorb(AvailabilitySweep(gone: [gone("a")], unverified: []))
        backlog.clearFindings()
        XCTAssertFalse(backlog.hasFindings)
    }
}
