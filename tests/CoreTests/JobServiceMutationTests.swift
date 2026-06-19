import SwiftData
import XCTest
@testable import JobhuntCore

// MARK: - Test scaffolding (file-private; mirrors JobServiceTests)

private struct NoOpProvider: LLMProvider {
    let id: String = "noop"
    let concurrencyLimit: Int = 1
    func complete(_: ChatRequest) async throws -> ChatResponse {
        throw LLMProviderError.httpError(statusCode: 503, body: "no-op")
    }
}

private func makeStore(_ container: ModelContainer) -> BackgroundStore {
    BackgroundStore(modelContainer: container)
}

private func makeQueue(_ container: ModelContainer) -> QueueActor {
    QueueActor(
        store: makeStore(container),
        isPaused: { true },
        onSetPaused: { _ in },
        readExtractionSettings: {
            ExtractionSettings(
                llmModel: "", preferredLocations: "", locationFilterEnabled: false,
                locationAllowRemote: true, locationAllowHybrid: true, locationAllowOnsite: true
            )
        },
        providerFactory: { NoOpProvider() }
    )
}

/// Covers the previously-untested write/mutation use cases: follow-up actions, contacts,
/// notes, rating, read-state, cover-letter deletion, data-quality review, timeline events,
/// and site review scheduling. Each test mutates then re-fetches to verify persistence.
final class JobServiceMutationTests: XCTestCase {
    private func makeService() throws -> (JobService, BackgroundStore) {
        let container = try ModelContainerFactory.inMemory()
        let store = makeStore(container)
        return (JobService(store: store, queue: makeQueue(container)), store)
    }

    private func seedJob(_ store: BackgroundStore, unread: Bool = false) async throws -> String {
        let job = Job(company: "Acme", title: "Engineer")
        job.unread = unread
        try await store.insert(job)
        return job.id
    }

    private func firstJob(_ store: BackgroundStore) async throws -> Job {
        try await fetchFirst(store, Job.self)
    }

    /// Fetches the first row of a type — keeps `await` out of `XCTUnwrap`'s autoclosure
    /// (autoclosures don't support concurrency).
    private func fetchFirst<T: PersistentModel>(_ store: BackgroundStore, _: T.Type) async throws -> T {
        let rows = try await store.fetch(FetchDescriptor<T>())
        return try XCTUnwrap(rows.first)
    }

    // MARK: - Follow-up actions

    func testCreateAction_persistsActionLinkedToJob() async throws {
        let (svc, store) = try makeService()
        let jobID = try await seedJob(store)
        let due = Date(timeIntervalSinceNow: 86_400)

        try await svc.createAction(jobID: jobID, text: "Follow up with recruiter", dueAt: due)

        let actions = try await store.fetch(FetchDescriptor<JobAction>())
        XCTAssertEqual(actions.count, 1)
        XCTAssertEqual(actions.first?.note, "Follow up with recruiter")
        XCTAssertEqual(actions.first?.job?.id, jobID)
        XCTAssertNil(actions.first?.completedAt)
    }

    func testCompleteAction_setsCompletedAt() async throws {
        let (svc, store) = try makeService()
        let jobID = try await seedJob(store)
        try await svc.createAction(jobID: jobID, text: "Prep for interview", dueAt: nil)
        let actionID = try await fetchFirst(store, JobAction.self).id

        try await svc.completeAction(actionID: actionID)

        let actions = try await store.fetch(FetchDescriptor<JobAction>())
        XCTAssertNotNil(try XCTUnwrap(actions.first).completedAt)
    }

    func testSnoozeAction_setsSnoozedUntil() async throws {
        let (svc, store) = try makeService()
        let jobID = try await seedJob(store)
        try await svc.createAction(jobID: jobID, text: "Send thank-you note", dueAt: nil)
        let actionID = try await fetchFirst(store, JobAction.self).id
        let until = Date(timeIntervalSinceNow: 3 * 86_400)

        try await svc.snoozeAction(actionID: actionID, until: until)

        let action = try await fetchFirst(store, JobAction.self)
        XCTAssertEqual(action.snoozedUntil?.timeIntervalSince1970 ?? 0, until.timeIntervalSince1970, accuracy: 1)
    }

    // MARK: - Contacts

    func testCreateContact_persistsContact() async throws {
        let (svc, store) = try makeService()
        let jobID = try await seedJob(store)

        try await svc.createContact(jobID: jobID, name: "Dana Lee", email: "dana@acme.com", role: "Recruiter")

        let contacts = try await store.fetch(FetchDescriptor<Contact>())
        XCTAssertEqual(contacts.count, 1)
        XCTAssertEqual(contacts.first?.name, "Dana Lee")
        XCTAssertEqual(contacts.first?.email, "dana@acme.com")
        XCTAssertEqual(contacts.first?.role, "Recruiter")
        XCTAssertEqual(contacts.first?.job?.id, jobID)
    }

    func testUpdateContact_updatesFields() async throws {
        let (svc, store) = try makeService()
        let jobID = try await seedJob(store)
        try await svc.createContact(jobID: jobID, name: "Dana Lee", email: nil, role: nil)
        let contactID = try await fetchFirst(store, Contact.self).id

        try await svc.updateContact(contactID: contactID, name: "Dana Park", email: "dana@x.com", role: "Hiring Manager")

        let contact = try await fetchFirst(store, Contact.self)
        XCTAssertEqual(contact.name, "Dana Park")
        XCTAssertEqual(contact.email, "dana@x.com")
        XCTAssertEqual(contact.role, "Hiring Manager")
    }

    func testDeleteContact_removesContact() async throws {
        let (svc, store) = try makeService()
        let jobID = try await seedJob(store)
        try await svc.createContact(jobID: jobID, name: "Temp", email: nil, role: nil)
        let contactID = try await fetchFirst(store, Contact.self).id

        try await svc.deleteContact(contactID: contactID)

        let remaining = try await store.fetch(FetchDescriptor<Contact>())
        XCTAssertEqual(remaining.count, 0)
    }

    // MARK: - Notes, rating, read-state

    func testAddNote_createsNoteEvent() async throws {
        let (svc, store) = try makeService()
        let jobID = try await seedJob(store)

        try await svc.addNote("Spoke with hiring manager — strong fit", to: jobID)

        let notes = try await store.fetch(FetchDescriptor<JobEvent>()).filter { $0.eventType == "note" }
        XCTAssertEqual(notes.count, 1)
        XCTAssertEqual(notes.first?.note, "Spoke with hiring manager — strong fit")
        XCTAssertEqual(notes.first?.job?.id, jobID)
    }

    func testRestoreNote_reinsertsWithPreservedTimestamps() async throws {
        let (svc, store) = try makeService()
        let jobID = try await seedJob(store)
        let occurred = Date(timeIntervalSince1970: 1_700_000_000)
        let created = Date(timeIntervalSince1970: 1_700_000_500)

        // Simulate the undo path: a note was deleted, and we re-insert it.
        try await svc.restoreNote(jobID: jobID, text: "Recovered note", occurredAt: occurred, createdAt: created)

        let notes = try await store.fetch(FetchDescriptor<JobEvent>()).filter { $0.eventType == "note" }
        XCTAssertEqual(notes.count, 1)
        let note = try XCTUnwrap(notes.first)
        XCTAssertEqual(note.note, "Recovered note")
        XCTAssertEqual(note.job?.id, jobID)
        XCTAssertEqual(note.occurredAt.timeIntervalSince1970, occurred.timeIntervalSince1970, accuracy: 1)
        XCTAssertEqual(note.createdAt.timeIntervalSince1970, created.timeIntervalSince1970, accuracy: 1)
    }

    func testSetRating_persistsAndClears() async throws {
        let (svc, store) = try makeService()
        let jobID = try await seedJob(store)

        try await svc.setRating(4, for: jobID)
        var job = try await firstJob(store)
        XCTAssertEqual(job.rating, 4)

        try await svc.setRating(nil, for: jobID)
        job = try await firstJob(store)
        XCTAssertNil(job.rating)
    }

    func testMarkOpened_setsLastOpenedAndClearsUnread() async throws {
        let (svc, store) = try makeService()
        let jobID = try await seedJob(store, unread: true)

        try await svc.markOpened(jobID: jobID)

        let job = try await firstJob(store)
        XCTAssertNotNil(job.lastOpenedAt)
        XCTAssertFalse(job.unread)
    }

    func testMarkRead_clearsUnread() async throws {
        let (svc, store) = try makeService()
        let jobID = try await seedJob(store, unread: true)

        try await svc.markRead(jobID: jobID)

        let job = try await firstJob(store)
        XCTAssertFalse(job.unread)
    }

    // MARK: - Timeline events

    func testSetStatus_writesStatusEvent() async throws {
        let (svc, store) = try makeService()
        let jobID = try await seedJob(store)

        try await svc.setStatus(.applied, for: jobID)

        let job = try await firstJob(store)
        XCTAssertEqual(job.status, .applied)
        let statusEvents = try await store.fetch(FetchDescriptor<JobEvent>()).filter { $0.eventType == "status" }
        XCTAssertEqual(statusEvents.count, 1)
        XCTAssertEqual(statusEvents.first?.job?.id, jobID)
    }

    // MARK: - Cover letters

    func testDeleteCoverLetter_removesIt() async throws {
        let (svc, store) = try makeService()
        _ = try await seedJob(store)
        let job = try await firstJob(store)
        let letter = CoverLetter(content: "Dear hiring team, …")
        letter.job = job
        try await store.insert(letter)
        let letterID = try await fetchFirst(store, CoverLetter.self).id

        try await svc.deleteCoverLetter(id: letterID)

        let remaining = try await store.fetch(FetchDescriptor<CoverLetter>())
        XCTAssertEqual(remaining.count, 0)
    }

    // MARK: - Data quality review

    func testMarkDataQualityReviewed_createsThenUpdatesInPlace() async throws {
        let (svc, store) = try makeService()
        let jobID = try await seedJob(store)

        try await svc.markDataQualityReviewed(jobID: jobID, notes: "Looks good")
        var reviews = try await store.fetch(FetchDescriptor<DataQualityReview>())
        XCTAssertEqual(reviews.count, 1)
        XCTAssertEqual(reviews.first?.note, "Looks good")

        // Second call updates the existing review rather than creating a second.
        try await svc.markDataQualityReviewed(jobID: jobID, notes: "Re-checked, still good")
        reviews = try await store.fetch(FetchDescriptor<DataQualityReview>())
        XCTAssertEqual(reviews.count, 1)
        XCTAssertEqual(reviews.first?.note, "Re-checked, still good")

        try await svc.clearDataQualityReview(jobID: jobID)
        let after = try await store.fetch(FetchDescriptor<DataQualityReview>())
        XCTAssertEqual(after.count, 0)
    }

    // MARK: - Site review scheduling

    func testSetNextReview_setsFutureReviewDate() async throws {
        let container = try ModelContainerFactory.inMemory()
        let store = makeStore(container)
        let sites = SiteService(store: store)
        let siteID = try await sites.createSite(url: "https://boards.example.com", name: "Example", intervalDays: 14)

        try await sites.setNextReview(id: siteID, daysFromNow: 7)

        let allSites = try await store.fetch(FetchDescriptor<Site>())
        let site = try XCTUnwrap(allSites.first { $0.id == siteID })
        let expected = Date(timeIntervalSinceNow: 7 * 86_400)
        let next = try XCTUnwrap(site.nextReviewAt)
        XCTAssertEqual(next.timeIntervalSince1970, expected.timeIntervalSince1970, accuracy: 120)
    }
}
