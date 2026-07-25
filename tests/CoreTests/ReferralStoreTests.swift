import SwiftData
import XCTest
@testable import JobhuntCore

/// Store-level behaviour for referral outreach (TASK-644 review). These pin the properties the
/// `recordReferralAttempt` comments claim but that nothing asserted: idempotent upsert, exactly one
/// timeline event per milestone, N/A-marker exclusivity, date clamping, and event cleanup on delete.
final class ReferralStoreTests: XCTestCase {
    private func makeStore() throws -> BackgroundStore {
        try BackgroundStore(modelContainer: ModelContainerFactory.inMemory())
    }

    @discardableResult
    private func seedJob(_ store: BackgroundStore, id: String = "job-1") async throws -> String {
        try await store.insert(Job(id: id, company: "Acme", title: "TPM", status: .applied))
        return id
    }

    private func attempts(_ store: BackgroundStore) async throws -> [ReferralAttempt] {
        try await store.fetch(FetchDescriptor<ReferralAttempt>())
    }

    private func referralEvents(_ store: BackgroundStore, jobID: String) async throws -> [String] {
        try await store.fetch(FetchDescriptor<JobEvent>())
            .filter { $0.eventType == "referral" && $0.job?.id == jobID }
            .sorted { $0.occurredAt < $1.occurredAt }
            .compactMap(\.note)
    }

    private func input(
        id: String = "att-1", jobID: String = "job-1", name: String = "Jane",
        identifier: String? = nil, outcome: ReferralOutcome = .requested,
        requestedAt: Date = Date(timeIntervalSince1970: 1_000_000),
        respondedAt: Date? = nil, submittedAt: Date? = nil, declinedAt: Date? = nil
    ) -> ReferralAttemptInput {
        ReferralAttemptInput(
            id: id, jobID: jobID, recipientName: name, recipientIdentifier: identifier,
            requestedAt: requestedAt, respondedAt: respondedAt, submittedAt: submittedAt,
            declinedAt: declinedAt, outcome: outcome.rawValue
        )
    }

    // MARK: - Upsert & event logging

    func testReSavingSameIDUpsertsOneRowAndLogsOneEvent() async throws {
        let store = try makeStore()
        try await seedJob(store)
        try await store.recordReferralAttempt(input())
        try await store.recordReferralAttempt(input(name: "Jane Doe"))

        let attempts = try await attempts(store)
        XCTAssertEqual(attempts.count, 1, "a stable id must upsert, not duplicate")
        XCTAssertEqual(attempts.first?.recipientName, "Jane Doe")
        let events = try await referralEvents(store, jobID: "job-1")
        XCTAssertEqual(events, ["Referral requested — Jane"], "the request must be logged exactly once")
    }

    /// Review #3: a brand-new attempt recorded as *already* submitted logged both "requested" and
    /// "submitted", counting one outreach twice in Today's recap.
    func testNewAttemptRecordedAsSubmittedLogsOnlyTheMilestone() async throws {
        let store = try makeStore()
        try await seedJob(store)
        try await store.recordReferralAttempt(
            input(outcome: .submitted, submittedAt: Date(timeIntervalSince1970: 2_000_000))
        )
        let events = try await referralEvents(store, jobID: "job-1")
        XCTAssertEqual(events, ["Referral submitted — Jane"])
    }

    func testAdvancingToSubmittedLogsTheMilestoneOnce() async throws {
        let store = try makeStore()
        try await seedJob(store)
        try await store.recordReferralAttempt(input())
        try await store.recordReferralAttempt(
            input(outcome: .submitted, submittedAt: Date(timeIntervalSince1970: 2_000_000))
        )
        let events = try await referralEvents(store, jobID: "job-1")
        XCTAssertEqual(events, ["Referral requested — Jane", "Referral submitted — Jane"])
    }

    /// Review #4: reverting a request and advancing it again re-logged the milestone, inflating the
    /// Referrals count for a single outreach.
    func testRevertingAndReAdvancingDoesNotReLogSubmitted() async throws {
        let store = try makeStore()
        try await seedJob(store)
        let submitted = Date(timeIntervalSince1970: 2_000_000)
        try await store.recordReferralAttempt(input())
        try await store.recordReferralAttempt(input(outcome: .submitted, submittedAt: submitted))
        try await store.recordReferralAttempt(input(outcome: .requested)) // revert
        try await store.recordReferralAttempt(input(outcome: .submitted, submittedAt: submitted)) // re-advance

        let events = try await referralEvents(store, jobID: "job-1")
        XCTAssertEqual(events.count(where: { $0 == "Referral submitted — Jane" }), 1)
    }

    func testMarkerNeverLogsAnEvent() async throws {
        let store = try makeStore()
        try await seedJob(store)
        try await store.setReferralNotApplicable(jobID: "job-1", true)
        let events = try await referralEvents(store, jobID: "job-1")
        XCTAssertTrue(events.isEmpty)
    }

    // MARK: - Deletion

    /// Review #4: deleting an attempt left its timeline events behind, so a mistaken outreach kept
    /// counting toward the recap with no way to remove it.
    func testDeletingAttemptRemovesItsTimelineEvents() async throws {
        let store = try makeStore()
        try await seedJob(store)
        try await store.recordReferralAttempt(
            input(outcome: .submitted, submittedAt: Date(timeIntervalSince1970: 2_000_000))
        )
        try await store.deleteReferralAttempt(id: "att-1")

        let remaining = try await attempts(store)
        let events = try await referralEvents(store, jobID: "job-1")
        XCTAssertTrue(remaining.isEmpty)
        XCTAssertTrue(events.isEmpty)
    }

    func testDeletingUnknownAttemptIsANoOp() async throws {
        let store = try makeStore()
        try await seedJob(store)
        try await store.recordReferralAttempt(input())
        try await store.deleteReferralAttempt(id: "nope")
        let remaining = try await attempts(store)
        XCTAssertEqual(remaining.count, 1)
    }

    // MARK: - N/A marker exclusivity (review #2)

    func testRecordingRealOutreachClearsTheNotApplicableMarker() async throws {
        let store = try makeStore()
        try await seedJob(store)
        try await store.setReferralNotApplicable(jobID: "job-1", true)
        try await store.recordReferralAttempt(input())

        let attempts = try await attempts(store)
        XCTAssertEqual(attempts.count, 1)
        XCTAssertEqual(attempts.first?.outcome, ReferralOutcome.requested.rawValue)
    }

    func testMarkingNotApplicableIsIgnoredWhenRealOutreachExists() async throws {
        let store = try makeStore()
        try await seedJob(store)
        try await store.recordReferralAttempt(input())
        try await store.setReferralNotApplicable(jobID: "job-1", true)

        let all = try await attempts(store)
        let outcomes = all.map(\.outcome)
        XCTAssertEqual(outcomes, [ReferralOutcome.requested.rawValue])
    }

    // MARK: - Validation (review #1)

    func testMilestoneDatesAreClampedIntoChronologicalOrder() async throws {
        let store = try makeStore()
        try await seedJob(store)
        let requested = Date(timeIntervalSince1970: 5_000_000)
        // Responded/submitted earlier than the ask — an inverted timeline corrupts follow-up staleness.
        try await store.recordReferralAttempt(input(
            outcome: .submitted, requestedAt: requested,
            respondedAt: Date(timeIntervalSince1970: 1_000_000),
            submittedAt: Date(timeIntervalSince1970: 2_000_000)
        ))
        let all = try await attempts(store)
        let attempt = try XCTUnwrap(all.first)
        XCTAssertEqual(attempt.requestedAt, requested)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(attempt.respondedAt), attempt.requestedAt)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(attempt.submittedAt), try XCTUnwrap(attempt.respondedAt))
    }

    func testRecipientNameIsTrimmed() async throws {
        let store = try makeStore()
        try await seedJob(store)
        try await store.recordReferralAttempt(input(name: "  Jane  "))
        let saved = try await attempts(store)
        XCTAssertEqual(saved.first?.recipientName, "Jane")
    }

    /// Review #7: a user-facing write against a deleted job silently persisted an orphan attempt plus
    /// an unlinked timeline event.
    func testRecordingAgainstAMissingJobThrows() async throws {
        let store = try makeStore()
        do {
            try await store.recordReferralAttempt(input(jobID: "ghost"))
            XCTFail("expected a notFound error")
        } catch {}
        let none = try await attempts(store)
        XCTAssertTrue(none.isEmpty)
    }

    // MARK: - Orphan cleanup (review #12)

    func testPruneOrphanReferralAttemptsRemovesOnlyJobless() async throws {
        let store = try makeStore()
        try await seedJob(store)
        try await store.recordReferralAttempt(input())
        // An attempt whose job is gone (deleted before cascade existed).
        try await store.insert(
            ReferralAttempt(id: "orphan", jobID: "gone", recipientName: "Ghost", outcome: "requested")
        )
        let deleted = try await store.pruneOrphanReferralAttempts()
        XCTAssertEqual(deleted, 1)
        let kept = try await attempts(store)
        XCTAssertEqual(kept.map(\.id), ["att-1"])
    }

    func testDeletingAJobRemovesItsReferralAttempts() async throws {
        let store = try makeStore()
        try await seedJob(store)
        try await store.recordReferralAttempt(input())
        try await store.setReferralNotApplicable(jobID: "job-2", true) // unrelated job's marker survives
        try await store.deleteReferralAttempts(jobID: "job-1")
        let kept = try await attempts(store)
        XCTAssertEqual(kept.map(\.jobID), ["job-2"])
    }
}
