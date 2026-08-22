import SwiftData
import XCTest
@testable import JobhuntCore

/// The boundary property the extraction has to preserve (TASK-686).
///
/// Milestone rules moved out of `BackgroundStore`, but the *transaction* deliberately did not: these
/// functions write into the caller's context and never save. That's what keeps a milestone record and
/// the timeline event mirroring it atomic with each other — and with whatever else the caller is
/// writing. A second `@ModelActor` with its own context would have broken exactly that, against a
/// SQLite store that permits one writer.
///
/// Behaviour is covered end-to-end through the store in `MilestoneStoreTests` / `ReferralStoreTests`;
/// this covers what only the boundary can be asked.
final class MilestonePersistenceTests: XCTestCase {
    private let day = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeContainer() throws -> ModelContainer {
        try ModelContainerFactory.inMemory()
    }

    private func seededJob(in context: ModelContext) -> Job {
        let job = Job(jobNumber: 1, title: "Engineer")
        context.insert(job)
        try? context.save()
        return job
    }

    /// Nothing reaches the store until the caller saves — so a milestone write can be part of a larger
    /// transaction rather than committing a fragment of one.
    func testWritesAreLeftUncommittedForTheCallerToSave() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let job = seededJob(in: context)

        _ = try MilestonePersistence.recordInterview(
            InterviewInput(id: "i1", jobID: job.id, scheduledAt: day, kind: InterviewKind.screen.rawValue),
            in: context
        )

        let observer = ModelContext(container)
        XCTAssertTrue(
            try observer.fetch(FetchDescriptor<InterviewRecord>()).isEmpty,
            "the write must not have committed itself"
        )

        try context.save()
        XCTAssertEqual(try ModelContext(container).fetch(FetchDescriptor<InterviewRecord>()).count, 1)
    }

    /// The record and the event that mirrors it land in the same save. Committing one without the other
    /// is what leaves the Timeline showing outreach that no longer exists.
    func testARecordAndItsTimelineEventCommitTogether() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let job = seededJob(in: context)

        _ = try MilestonePersistence.recordOffer(
            OfferInput(id: "o1", jobID: job.id, offeredAt: day, title: "Staff", baseSalary: 200_000),
            in: context
        )
        try context.save()

        let observer = ModelContext(container)
        XCTAssertEqual(try observer.fetch(FetchDescriptor<OfferRecord>()).count, 1)
        let events = try observer.fetch(FetchDescriptor<JobEvent>()).filter { $0.eventType == "offer" }
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.id, "offer-o1", "derived from the record, so a re-save can't duplicate it")
    }

    /// A write against a job that's gone throws before inserting anything, so there is no half-written
    /// milestone for the caller to have to unwind.
    func testAWriteAgainstAMissingJobLeavesNothingToRollBack() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        XCTAssertThrowsError(
            try MilestonePersistence.recordReferralAttempt(
                ReferralAttemptInput(jobID: "ghost", recipientName: "Ada", requestedAt: day, outcome: "requested"),
                in: context
            )
        )
        XCTAssertTrue(try context.fetch(FetchDescriptor<ReferralAttempt>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<JobEvent>()).isEmpty)
    }

    /// Deletes report whether they found anything, so the caller can skip a save that would write
    /// nothing — the reason these return Bool rather than Void.
    func testDeletingSomethingAbsentReportsNoWork() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        XCTAssertFalse(try MilestonePersistence.deleteInterview(id: "nope", in: context))
        XCTAssertFalse(try MilestonePersistence.deleteOffer(id: "nope", in: context))
        XCTAssertFalse(try MilestonePersistence.deleteReferralAttempt(id: "nope", in: context))
        XCTAssertFalse(try MilestonePersistence.deleteMilestones(jobID: "nope", in: context))
    }
}
