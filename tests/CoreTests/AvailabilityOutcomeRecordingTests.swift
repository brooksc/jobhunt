import SwiftData
import XCTest
@testable import JobhuntCore

/// Nothing was recorded about a check, so every run started from zero and no two runs could be
/// compared. That is why a check over an unchanged archive could report seven gone postings and then
/// four with nothing to explain the difference (TASK-674).
final class AvailabilityOutcomeRecordingTests: XCTestCase {
    private func gone(_ id: String, reason: String = "no longer listed") -> GoneJobResult {
        GoneJobResult(
            jobID: id, jobNumber: nil, company: nil, title: id,
            url: URL(string: "https://jobs.test/\(id)")!, reason: reason
        )
    }

    private func unverified(_ id: String, _ reason: UnverifiedReason) -> UnverifiedJobResult {
        UnverifiedJobResult(
            jobID: id, jobNumber: nil, company: nil, title: id,
            url: URL(string: "https://jobs.test/\(id)")!, reason: reason, detail: "d"
        )
    }

    /// A run reports what it confirmed, not only what it found wrong — that is what makes two runs
    /// comparable, and what lets a row say when it was last checked.
    func testSweepReportsEveryConclusionIncludingAlive() {
        let sweep = AvailabilitySweep(
            gone: [gone("a")],
            unverified: [unverified("b", .rateLimited)],
            checkedCount: 2,
            alive: ["c"]
        )
        let byID = Dictionary(uniqueKeysWithValues: sweep.outcomes.map { ($0.jobID, $0.verdict) })
        XCTAssertEqual(byID["a"], .gone)
        XCTAssertEqual(byID["c"], .alive)
        XCTAssertEqual(
            byID["b"], .unverified,
            "'couldn't check' must be recorded — it is not the same as 'fine'"
        )
        XCTAssertEqual(sweep.outcomes.count, 3)
    }

    func testOutcomesCarryTheReasonThatMakesAVerdictJudgeable() {
        let sweep = AvailabilitySweep(gone: [gone("a", reason: "greenhouse posting gh:1 no longer listed")])
        XCTAssertEqual(sweep.outcomes.first?.detail, "greenhouse posting gh:1 no longer listed")
    }

    func testRecordingPersistsVerdictAndTimestamp() async throws {
        let container = try ModelContainerFactory.inMemory()
        let store = BackgroundStore(modelContainer: container)
        let alive = Job(jobNumber: 1, title: "Alive")
        let dead = Job(jobNumber: 2, title: "Dead")
        try await store.insert(alive)
        try await store.insert(dead)

        let checkedAt = Date(timeIntervalSince1970: 1_000_000)
        let written = try await store.recordAvailabilityOutcomes([
            AvailabilityOutcome(jobID: alive.id, verdict: .alive, detail: nil),
            AvailabilityOutcome(jobID: dead.id, verdict: .gone, detail: "no longer listed")
        ], checkedAt: checkedAt)
        XCTAssertEqual(written, 2)

        let jobs = try await store.fetch(FetchDescriptor<Job>())
        let aliveRow = try XCTUnwrap(jobs.first { $0.jobNumber == 1 })
        let deadRow = try XCTUnwrap(jobs.first { $0.jobNumber == 2 })
        XCTAssertEqual(aliveRow.availabilityVerdict, "alive")
        XCTAssertEqual(aliveRow.availabilityCheckedAt, checkedAt)
        XCTAssertEqual(deadRow.availabilityVerdict, "gone")
        XCTAssertEqual(deadRow.availabilityDetail, "no longer listed")
    }

    /// A check is something that happened to the posting elsewhere, not an edit — bumping updatedAt
    /// would reorder every recently-checked job in a list sorted by last change.
    func testRecordingDoesNotCountAsAnEdit() async throws {
        let container = try ModelContainerFactory.inMemory()
        let store = BackgroundStore(modelContainer: container)
        let job = Job(jobNumber: 1, title: "T")
        try await store.insert(job)
        let beforeRows = try await store.fetch(FetchDescriptor<Job>())
        let before = try XCTUnwrap(beforeRows.first).updatedAt

        _ = try await store.recordAvailabilityOutcomes(
            [AvailabilityOutcome(jobID: job.id, verdict: .alive, detail: nil)]
        )
        let afterRows = try await store.fetch(FetchDescriptor<Job>())
        let after = try XCTUnwrap(afterRows.first).updatedAt
        XCTAssertEqual(before, after, "a check must not read as a user edit")
    }

    /// An outcome for a job that no longer exists is skipped, not fatal.
    func testUnknownJobIDsAreIgnored() async throws {
        let container = try ModelContainerFactory.inMemory()
        let store = BackgroundStore(modelContainer: container)
        let written = try await store.recordAvailabilityOutcomes(
            [AvailabilityOutcome(jobID: "does-not-exist", verdict: .gone, detail: nil)]
        )
        XCTAssertEqual(written, 0)
    }

    /// Existing rows have never been checked, and must open with nil rather than a fabricated verdict
    /// — the additive-migration guarantee.
    func testNeverCheckedJobsHaveNoVerdict() async throws {
        let container = try ModelContainerFactory.inMemory()
        let store = BackgroundStore(modelContainer: container)
        let job = Job(jobNumber: 1, title: "T")
        try await store.insert(job)
        let rows = try await store.fetch(FetchDescriptor<Job>())
        let fetched = try XCTUnwrap(rows.first)
        XCTAssertNil(fetched.availabilityCheckedAt)
        XCTAssertNil(fetched.availabilityVerdict)
    }
}
