import Foundation
import SwiftData
import XCTest
@testable import JobhuntCore

/// Reading the canonical posting from the Greenhouse board API (TASK-632).
///
/// Network-free: `fetch` is a thin loop over `decode`, and what's worth pinning is the payload
/// shape and the refresh's effect on the store.
final class GreenhouseJobBoardDecodeTests: XCTestCase {
    private func payload(
        content: String = "&lt;p&gt;Build &amp;amp; ship platform tooling.&lt;/p&gt;",
        extra: String = ""
    ) -> Data {
        Data("""
        {
          "id": 4567,
          "title": "Staff Platform Engineer",
          "content": "\(content)",
          "absolute_url": "https://boards.greenhouse.io/acme/jobs/4567",
          "updated_at": "2026-07-14T10:11:12.000Z",
          "first_published": "2026-05-02T09:00:00-04:00",
          "location": { "name": "San Francisco, CA" },
          "departments": [{ "name": "Engineering" }, { "name": "Platform" }]
          \(extra)
        }
        """.utf8)
    }

    func testDecodesTheFieldsWeUse() throws {
        let posting = try XCTUnwrap(GreenhouseJobBoard.decode(payload(), board: "acme"))
        XCTAssertEqual(posting.title, "Staff Platform Engineer")
        XCTAssertEqual(posting.locationName, "San Francisco, CA")
        XCTAssertEqual(posting.departments, ["Engineering", "Platform"])
        XCTAssertEqual(posting.board, "acme")
        XCTAssertNotNil(posting.updatedAt)
        XCTAssertNotNil(posting.firstPublished)
    }

    /// `content` is the only field worth failing over: a posting with a title and no body gives the
    /// refresh nothing to do, and writing an empty description would be strictly worse than leaving
    /// the scrape alone.
    func testMissingOrEmptyContentIsNotAUsablePosting() {
        XCTAssertNil(GreenhouseJobBoard.decode(Data(#"{"title":"X"}"#.utf8), board: "acme"))
        XCTAssertNil(GreenhouseJobBoard.decode(payload(content: ""), board: "acme"))
    }

    func testGarbageIsNotAPosting() {
        XCTAssertNil(GreenhouseJobBoard.decode(Data("not json".utf8), board: "acme"))
    }

    /// Greenhouse sends ISO-8601 with fractional seconds on some boards and without on others. The
    /// offset form is what a live board actually returned (gitlab/8503792002, checked 2026-08-09) —
    /// not `Z`, which is what you'd assume from the docs.
    func testTimestampParsesEveryFormGreenhouseSends() {
        XCTAssertNotNil(GreenhouseJobBoard.parseTimestamp("2026-07-14T10:11:12.000Z"))
        XCTAssertNotNil(GreenhouseJobBoard.parseTimestamp("2026-07-14T10:11:12Z"))
        XCTAssertNotNil(GreenhouseJobBoard.parseTimestamp("2026-08-03T16:43:10-04:00"))
        XCTAssertNil(GreenhouseJobBoard.parseTimestamp("last Tuesday"))
    }

    /// The API's `content` is HTML, escaped. Running it through the shared cleaner rather than a
    /// bespoke strip is deliberate — a second implementation would drift from what extraction was
    /// tuned on.
    func testDescriptionIsUnescapedAndStripped() throws {
        let posting = try XCTUnwrap(GreenhouseJobBoard.decode(payload(), board: "acme"))
        let text = GreenhouseJobBoard.plainTextDescription(posting)
        XCTAssertTrue(text.contains("Build & ship platform tooling"), text)
        XCTAssertFalse(text.contains("<p>"), text)
        XCTAssertFalse(text.contains("&amp;"), text)
    }
}

/// Applying a fetched posting to the store.
final class GreenhouseRefreshApplyTests: XCTestCase {
    private var container: ModelContainer!

    override func setUp() async throws {
        container = try ModelContainerFactory.inMemory()
    }

    override func tearDown() async throws {
        container = nil
    }

    private func makeStore() -> BackgroundStore {
        BackgroundStore(modelContainer: container)
    }

    /// Built as the provider would hand it over: already plain text, since the vendors differ in
    /// whether they publish HTML and the store shouldn't care.
    private func posting(
        title: String? = "Staff Platform Engineer",
        location: String? = "San Francisco, CA"
    ) -> ATSPosting {
        ATSPosting(
            contentPlain: "The real description, in full.",
            title: title,
            locationName: location,
            firstPublished: nil,
            updatedAt: nil,
            absoluteURL: nil,
            providerName: "Greenhouse",
            boardKey: "acme"
        )
    }

    /// #1: the scraped shell text is replaced by the employer's own description.
    func testReplacesTheDescription() async throws {
        let store = makeStore()
        let jobID = try await seedJobWithCapture(store: store)

        let outcome = try await store.applyATSRefresh(jobID: jobID, posting: posting())
        XCTAssertTrue(outcome.descriptionChanged)

        let jobs = try await store.fetch(FetchDescriptor<Job>())
        let cleaned = try XCTUnwrap(jobs.first?.capture?.cleanedDescription)
        XCTAssertTrue(cleaned.contains("The real description, in full"), cleaned)
        XCTAssertFalse(cleaned.contains("Enable JavaScript"), cleaned)
    }

    /// `visibleText` has to move with it: a later re-clean recomputes `cleanedDescription` from it,
    /// which would silently undo the refresh.
    func testVisibleTextIsKeptInStepSoARecleanCantUndoIt() async throws {
        let store = makeStore()
        let jobID = try await seedJobWithCapture(store: store)
        try await store.applyATSRefresh(jobID: jobID, posting: posting())

        try await store.recleanAllCaptures()

        let jobs = try await store.fetch(FetchDescriptor<Job>())
        let cleaned = try XCTUnwrap(jobs.first?.capture?.cleanedDescription)
        XCTAssertTrue(cleaned.contains("The real description, in full"), cleaned)
    }

    /// #2: clean metadata is backfilled.
    func testBackfillsTitleAndLocation() async throws {
        let store = makeStore()
        let jobID = try await seedJobWithCapture(store: store)

        let outcome = try await store.applyATSRefresh(jobID: jobID, posting: posting())
        XCTAssertTrue(outcome.titleChanged)
        XCTAssertTrue(outcome.locationChanged)

        let jobs = try await store.fetch(FetchDescriptor<Job>())
        XCTAssertEqual(jobs.first?.title, "Staff Platform Engineer")
        XCTAssertEqual(jobs.first?.location, "San Francisco, CA")
    }

    /// #2, the half that matters more: a field the user edited by hand is left alone — and *said*
    /// so, because silently keeping their value looks identical to the refresh not working.
    func testManualOverridesAreKeptAndReported() async throws {
        let store = makeStore()
        let jobID = try await seedJobWithCapture(store: store, overrides: #"["title"]"#)

        let outcome = try await store.applyATSRefresh(jobID: jobID, posting: posting())
        XCTAssertFalse(outcome.titleChanged)
        XCTAssertEqual(outcome.skippedOverrides, ["title"])

        let jobs = try await store.fetch(FetchDescriptor<Job>())
        XCTAssertEqual(jobs.first?.title, "Scraped Title")
        // The unoverridden field still updates.
        XCTAssertEqual(jobs.first?.location, "San Francisco, CA")
    }

    /// Re-running against the same posting must report "nothing changed" rather than claiming a
    /// refresh — the caller uses this to decide whether to spend a re-extraction.
    func testSecondRefreshIsANoOp() async throws {
        let store = makeStore()
        let jobID = try await seedJobWithCapture(store: store)
        try await store.applyATSRefresh(jobID: jobID, posting: posting())

        let second = try await store.applyATSRefresh(jobID: jobID, posting: posting())
        XCTAssertFalse(second.changedAnything)
    }

    /// A posting with no title/location still refreshes the description rather than failing.
    func testPartialPostingStillRefreshesWhatItHas() async throws {
        let store = makeStore()
        let jobID = try await seedJobWithCapture(store: store)

        let outcome = try await store.applyATSRefresh(
            jobID: jobID, posting: posting(title: nil, location: nil)
        )
        XCTAssertTrue(outcome.descriptionChanged)
        XCTAssertFalse(outcome.titleChanged)
        XCTAssertFalse(outcome.locationChanged)
    }

    /// #4's store half: an unknown job is an error, not a silent no-op that reads as success.
    func testUnknownJobThrows() async throws {
        let store = makeStore()
        do {
            _ = try await store.applyATSRefresh(jobID: "nope", posting: posting())
            XCTFail("expected a notFound error")
        } catch {}
    }

    /// `greenhouseIdentity` finds the id on the capture URL, which keeps the `?gh_jid=` an extracted
    /// application URL may not carry.
    func testIdentityIsFoundFromTheCaptureURL() async throws {
        let store = makeStore()
        let jobID = try await seedJobWithCapture(store: store)

        let identity = try await store.atsIdentity(jobID: jobID)
        XCTAssertEqual(identity?.atsID, "gh:4567")
        XCTAssertEqual(identity?.company, "Acme")
    }

    func testNonGreenhouseJobHasNoIdentity() async throws {
        let store = makeStore()
        let jobID = try await seedJobWithCapture(
            store: store, captureURL: "https://example.com/careers/123"
        )
        let identity = try await store.atsIdentity(jobID: jobID)
        XCTAssertNil(identity)
    }

    // MARK: - Seeding

    /// Inserted through a plain context rather than the store's API: the relationship has to be set
    /// before the save, and `BackgroundStore.insertBatch` can't express the link.
    @discardableResult
    private func seedJobWithCapture(
        store _: BackgroundStore,
        overrides: String? = nil,
        captureURL: String = "https://careers.acme.com/?gh_jid=4567"
    ) async throws -> String {
        let jobID = "job-gh-\(UUID().uuidString)"
        let context = ModelContext(container)
        let capture = Capture(
            url: captureURL,
            pageTitle: "Acme Careers",
            visibleText: "Enable JavaScript to view this page.",
            cleanedDescription: "Enable JavaScript to view this page.",
            rawHash: UUID().uuidString
        )
        let job = Job(id: jobID, jobNumber: 1, company: "Acme", title: "Scraped Title")
        job.location = "Somewhere"
        job.manualFieldOverridesJSON = overrides
        job.capture = capture
        context.insert(capture)
        context.insert(job)
        try context.save()
        return jobID
    }
}
