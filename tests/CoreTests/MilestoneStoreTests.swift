import SwiftData
import XCTest
@testable import JobhuntCore

/// Structured interview + offer tracking (TASK-501): upsert semantics, the single mirrored timeline
/// event per record, deadline clamping, and cascade on job delete.
final class MilestoneStoreTests: XCTestCase {
    private func makeStore() throws -> BackgroundStore {
        try BackgroundStore(modelContainer: ModelContainerFactory.inMemory())
    }

    private func seedJob(_ store: BackgroundStore, id: String = "job-1") async throws {
        try await store.insert(Job(id: id, company: "Acme", title: "TPM", status: .interview))
    }

    private func events(_ store: BackgroundStore, type: String) async throws -> [String] {
        try await store.fetch(FetchDescriptor<JobEvent>())
            .filter { $0.eventType == type }
            .compactMap(\.note)
    }

    private let day = Date(timeIntervalSince1970: 1_000_000)

    // MARK: - Interviews

    func testRecordingInterviewCreatesRecordAndOneTimelineEvent() async throws {
        let store = try makeStore()
        try await seedJob(store)
        try await store.recordInterview(InterviewInput(
            id: "int-1", jobID: "job-1", scheduledAt: day,
            kind: InterviewKind.technical.rawValue, interviewer: "Dana"
        ))
        let records = try await store.fetch(FetchDescriptor<InterviewRecord>())
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.interviewer, "Dana")
        let notes = try await events(store, type: "interview")
        XCTAssertEqual(notes, ["Technical — Dana"])
    }

    /// Editing a round must correct the existing timeline entry, not append a second one.
    func testEditingInterviewUpdatesTheSameTimelineEvent() async throws {
        let store = try makeStore()
        try await seedJob(store)
        try await store.recordInterview(InterviewInput(
            id: "int-1", jobID: "job-1", scheduledAt: day, kind: InterviewKind.screen.rawValue, interviewer: "Dana"
        ))
        try await store.recordInterview(InterviewInput(
            id: "int-1", jobID: "job-1", scheduledAt: day, kind: InterviewKind.onsite.rawValue, interviewer: "Sam"
        ))
        let records = try await store.fetch(FetchDescriptor<InterviewRecord>())
        XCTAssertEqual(records.count, 1)
        let notes = try await events(store, type: "interview")
        XCTAssertEqual(notes, ["Onsite — Sam"])
    }

    func testMultipleInterviewRoundsCoexist() async throws {
        let store = try makeStore()
        try await seedJob(store)
        for (index, kind) in [InterviewKind.screen, .technical, .onsite].enumerated() {
            try await store.recordInterview(InterviewInput(
                id: "int-\(index)", jobID: "job-1",
                scheduledAt: day.addingTimeInterval(Double(index) * 86400), kind: kind.rawValue
            ))
        }
        let records = try await store.fetch(FetchDescriptor<InterviewRecord>())
        XCTAssertEqual(records.count, 3)
        let notes = try await events(store, type: "interview")
        XCTAssertEqual(notes.count, 3)
    }

    func testDeletingInterviewRemovesItsTimelineEvent() async throws {
        let store = try makeStore()
        try await seedJob(store)
        try await store.recordInterview(InterviewInput(
            id: "int-1", jobID: "job-1", scheduledAt: day, kind: InterviewKind.screen.rawValue
        ))
        try await store.deleteInterview(id: "int-1")
        let records = try await store.fetch(FetchDescriptor<InterviewRecord>())
        let notes = try await events(store, type: "interview")
        XCTAssertTrue(records.isEmpty)
        XCTAssertTrue(notes.isEmpty)
    }

    // MARK: - Offers

    func testRecordingOfferStoresStructuredFields() async throws {
        let store = try makeStore()
        try await seedJob(store)
        try await store.recordOffer(OfferInput(
            id: "off-1", jobID: "job-1", offeredAt: day, title: "Staff TPM",
            baseSalary: 210_000, additionalComp: "RSUs", decisionBy: day.addingTimeInterval(5 * 86400)
        ))
        let offers = try await store.fetch(FetchDescriptor<OfferRecord>())
        let offer = try XCTUnwrap(offers.first)
        XCTAssertEqual(offer.title, "Staff TPM")
        XCTAssertEqual(offer.baseSalary, 210_000)
        XCTAssertEqual(offer.additionalComp, "RSUs")
        let notes = try await events(store, type: "offer")
        XCTAssertEqual(notes.count, 1)
    }

    /// A job holds at most one offer — re-recording updates rather than accumulating.
    func testSecondOfferUpsertsRatherThanDuplicating() async throws {
        let store = try makeStore()
        try await seedJob(store)
        try await store.recordOffer(OfferInput(id: "off-1", jobID: "job-1", offeredAt: day, baseSalary: 200_000))
        try await store.recordOffer(OfferInput(id: "off-2", jobID: "job-1", offeredAt: day, baseSalary: 215_000))
        let offers = try await store.fetch(FetchDescriptor<OfferRecord>())
        XCTAssertEqual(offers.count, 1)
        XCTAssertEqual(offers.first?.baseSalary, 215_000)
    }

    func testDecisionDeadlineIsClampedToTheOfferDate() async throws {
        let store = try makeStore()
        try await seedJob(store)
        // A deadline before the offer exists is nonsense.
        try await store.recordOffer(OfferInput(
            id: "off-1", jobID: "job-1", offeredAt: day, decisionBy: day.addingTimeInterval(-5 * 86400)
        ))
        let offers = try await store.fetch(FetchDescriptor<OfferRecord>())
        let offer = try XCTUnwrap(offers.first)
        XCTAssertEqual(offer.decisionBy, day)
    }

    // MARK: - Guards & cascade

    func testRecordingAgainstAMissingJobThrows() async throws {
        let store = try makeStore()
        do {
            try await store.recordInterview(InterviewInput(
                id: "int-1", jobID: "ghost", scheduledAt: day, kind: InterviewKind.screen.rawValue
            ))
            XCTFail("expected a notFound error")
        } catch {}
        let records = try await store.fetch(FetchDescriptor<InterviewRecord>())
        XCTAssertTrue(records.isEmpty)
    }

    func testDeletingAJobRemovesItsMilestonesAndEvents() async throws {
        let store = try makeStore()
        try await seedJob(store)
        try await store.recordInterview(InterviewInput(
            id: "int-1", jobID: "job-1", scheduledAt: day, kind: InterviewKind.screen.rawValue
        ))
        try await store.recordOffer(OfferInput(id: "off-1", jobID: "job-1", offeredAt: day))
        try await store.deleteMilestones(jobID: "job-1")

        let interviews = try await store.fetch(FetchDescriptor<InterviewRecord>())
        let offers = try await store.fetch(FetchDescriptor<OfferRecord>())
        let interviewNotes = try await events(store, type: "interview")
        let offerNotes = try await events(store, type: "offer")
        XCTAssertTrue(interviews.isEmpty)
        XCTAssertTrue(offers.isEmpty)
        XCTAssertTrue(interviewNotes.isEmpty, "cascade must take the timeline events too")
        XCTAssertTrue(offerNotes.isEmpty)
    }

    /// Milestone events must not inflate the daily recap — the status transition to Interview/Offer is
    /// what counts there, so these carry no recap category.
    func testMilestoneEventsAreNotCountedInTheRecap() {
        for type in ["interview", "offer"] {
            let event = DashboardMetrics.RecapEvent(
                eventType: type, note: "x", occurredAt: day, jobID: "job-1",
                jobNumber: nil, company: nil, title: nil
            )
            XCTAssertNil(DashboardMetrics.category(for: event), type)
        }
    }
}
