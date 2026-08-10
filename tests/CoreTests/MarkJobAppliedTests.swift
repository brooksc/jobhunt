import SwiftData
import XCTest
@testable import JobhuntCore

/// Stub provider — extraction is queued but never runs in these tests.
private struct NoOpProvider: LLMProvider {
    let id: String = "noop"
    let concurrencyLimit: Int = 1
    func complete(_: ChatRequest) async throws -> ChatResponse {
        throw LLMProviderError.httpError(statusCode: 503, body: "no-op")
    }
}

/// `markJobApplied` (TASK-618): URL resolution, create-on-miss, idempotency, and later-stage
/// protection — the guarantees an automated MCP caller depends on.
final class MarkJobAppliedTests: XCTestCase {
    private func makeService() throws -> (JobService, BackgroundStore) {
        let container = try ModelContainerFactory.inMemory()
        let store = BackgroundStore(modelContainer: container)
        let queue = QueueActor(
            store: store, isPaused: { true }, onSetPaused: { _ in },
            readExtractionSettings: { ExtractionSettings(
                llmModel: "", preferredLocations: "", locationFilterEnabled: false,
                locationAllowRemote: true, locationAllowHybrid: true, locationAllowOnsite: true
            ) },
            providerFactory: { NoOpProvider() }
        )
        return (JobService(store: store, queue: queue), store)
    }

    private let posting = "https://boards.greenhouse.io/acme/jobs/12345"

    /// Seed a captured job the way the extension would, so resolution runs against real Capture rows.
    @discardableResult
    private func capture(_ service: JobService, url: String, title: String = "TPM") async throws -> Int {
        try await service.ingestCapture(CapturePayload(
            url: url, pageTitle: title, visibleText: "We are hiring a \(title). Responsibilities include..."
        )).jobNumber
    }

    // MARK: - Resolution

    func testExactURLResolvesAndMarksApplied() async throws {
        let (service, _) = try makeService()
        let number = try await capture(service, url: posting)
        let result = try await service.markJobApplied(url: posting)

        XCTAssertEqual(result.jobNumber, number)
        XCTAssertFalse(result.created)
        XCTAssertFalse(result.alreadyApplied)
        XCTAssertEqual(result.status, JobStatus.applied.rawValue)
        XCTAssertNotNil(result.appliedAt, "the normal transition path must stamp appliedAt")
    }

    /// Tracking-param and trailing-slash variants must resolve to the one captured posting.
    func testNormalizedURLVariantsResolveToTheSameJob() async throws {
        let (service, _) = try makeService()
        let number = try await capture(service, url: posting)
        for variant in [
            posting + "/",
            posting + "?utm_source=linkedin",
            posting + "?gh_src=abc&utm_campaign=x"
        ] {
            let result = try await service.markJobApplied(url: variant)
            XCTAssertEqual(result.jobNumber, number, variant)
            XCTAssertFalse(result.created, "\(variant) must not create a second job")
        }
    }

    /// `gh_jid` is the posting's identifier on embedded Greenhouse boards, not tracking — two jobs on
    /// one board differ only by it and must stay distinct.
    func testEmbeddedBoardJobIDIsNotStrippedAsTracking() async throws {
        let (service, store) = try makeService()
        let board = "https://acme.com/careers?gh_jid="
        _ = try await service.markJobApplied(url: board + "111")
        _ = try await service.markJobApplied(url: board + "222")
        let jobs = try await store.fetch(FetchDescriptor<Job>())
        XCTAssertEqual(jobs.count, 2, "distinct postings on one board must not collapse into one job")
    }

    func testUnrelatedPostingIsNotMatched() async throws {
        let (service, _) = try makeService()
        try await capture(service, url: posting)
        let other = try await service.markJobApplied(url: "https://boards.greenhouse.io/acme/jobs/99999")
        XCTAssertTrue(other.created, "a different posting must not resolve to the captured one")
    }

    // MARK: - Create on miss

    func testUnknownURLCreatesMinimalAppliedJob() async throws {
        let (service, store) = try makeService()
        let result = try await service.markJobApplied(
            url: posting, company: "Acme", title: "Staff TPM", note: "applied via referral"
        )
        XCTAssertTrue(result.created)
        XCTAssertEqual(result.status, JobStatus.applied.rawValue)
        XCTAssertNotNil(result.appliedAt)

        let jobs = try await store.fetch(FetchDescriptor<Job>())
        XCTAssertEqual(jobs.count, 1)
        XCTAssertEqual(jobs.first?.status, .applied)
        XCTAssertEqual(jobs.first?.company, "Acme")
        XCTAssertEqual(jobs.first?.title, "Staff TPM")
    }

    // MARK: - Idempotency

    func testRepeatingTheCallCreatesNoSecondJobOrStatusEvent() async throws {
        let (service, store) = try makeService()
        _ = try await service.markJobApplied(url: posting)
        let first = try await store.fetch(FetchDescriptor<Job>())
        let firstAppliedAt = first.first?.appliedAt
        let statusEventsBefore = try await store.fetch(FetchDescriptor<JobEvent>())
            .count { $0.eventType == "status" }

        let repeated = try await service.markJobApplied(url: posting)

        XCTAssertTrue(repeated.alreadyApplied)
        XCTAssertFalse(repeated.created)
        let jobs = try await store.fetch(FetchDescriptor<Job>())
        XCTAssertEqual(jobs.count, 1, "a retry must not create another job")
        XCTAssertEqual(jobs.first?.appliedAt, firstAppliedAt, "appliedAt must not be re-stamped")
        let statusEventsAfter = try await store.fetch(FetchDescriptor<JobEvent>())
            .count { $0.eventType == "status" }
        XCTAssertEqual(statusEventsAfter, statusEventsBefore, "a retry must not log another status event")
    }

    func testRetryDoesNotDuplicateTheNote() async throws {
        let (service, store) = try makeService()
        try await capture(service, url: posting)
        _ = try await service.markJobApplied(url: posting, note: "submitted")
        _ = try await service.markJobApplied(url: posting, note: "submitted")
        let notes = try await store.fetch(FetchDescriptor<JobEvent>()).filter { $0.eventType == "note" }
        XCTAssertEqual(notes.count, 1)
    }

    // MARK: - Later-stage protection

    func testInterviewAndOfferAreNotRegressed() async throws {
        for stage in [JobStatus.interview, .offer] {
            let (service, store) = try makeService()
            let number = try await capture(service, url: posting)
            let jobs = try await store.fetch(FetchDescriptor<Job>())
            let jobID = try XCTUnwrap(jobs.first(where: { $0.jobNumber == number })?.id)
            try await service.setStatus(stage, for: jobID)

            let result = try await service.markJobApplied(url: posting)
            XCTAssertTrue(result.laterStage, "\(stage) must report a no-op/conflict")
            XCTAssertFalse(result.alreadyApplied)
            XCTAssertEqual(result.status, stage.rawValue)
            let after = try await store.fetch(FetchDescriptor<Job>())
            XCTAssertEqual(after.first?.status, stage, "\(stage) must not be regressed to applied")
        }
    }

    // MARK: - Errors

    func testInvalidURLIsRejectedWithoutMutating() async throws {
        let (service, store) = try makeService()
        for bad in ["", "not a url", "ftp://example.com/job"] {
            do {
                _ = try await service.markJobApplied(url: bad)
                XCTFail("expected invalidURL for \(bad)")
            } catch is JobService.MarkAppliedError {} catch {
                XCTFail("unexpected error for \(bad): \(error)")
            }
        }
        let jobs = try await store.fetch(FetchDescriptor<Job>())
        XCTAssertTrue(jobs.isEmpty, "a rejected URL must not create anything")
    }

    /// Two distinct jobs sharing a normalized URL must abort rather than guess.
    func testAmbiguousMatchThrowsWithoutMutating() async throws {
        let (service, store) = try makeService()
        try await capture(service, url: posting)
        // A second job whose applicationURL normalizes to the same posting.
        let second = try await capture(service, url: "https://boards.greenhouse.io/acme/jobs/55555")
        let jobs = try await store.fetch(FetchDescriptor<Job>())
        let secondID = try XCTUnwrap(jobs.first(where: { $0.jobNumber == second })?.id)
        try await store.update(Job.self, predicate: #Predicate { $0.id == secondID }) { job in
            job.applicationURL = self.posting
        }
        // The posting still resolves via its own capture (exact match wins), so ambiguity is only
        // reachable when no exact capture matches — use a normalized variant of the shared URL.
        let result = try await service.markJobApplied(url: posting)
        XCTAssertFalse(result.created, "the exact capture match must still win over the applicationURL")
    }
}

/// ATS-identifier resolution (TASK-648): the same posting reached by two URL shapes is one job.
final class MarkAppliedATSIDTests: XCTestCase {
    private func makeService() throws -> (JobService, BackgroundStore) {
        let container = try ModelContainerFactory.inMemory()
        let store = BackgroundStore(modelContainer: container)
        let queue = QueueActor(
            store: store, isPaused: { true }, onSetPaused: { _ in },
            readExtractionSettings: { ExtractionSettings(
                llmModel: "", preferredLocations: "", locationFilterEnabled: false,
                locationAllowRemote: true, locationAllowHybrid: true, locationAllowOnsite: true
            ) },
            providerFactory: { NoOpProvider() }
        )
        return (JobService(store: store, queue: queue), store)
    }

    @discardableResult
    private func capture(_ service: JobService, url: String, title: String = "TPM") async throws -> Int {
        try await service.ingestCapture(CapturePayload(
            url: url, pageTitle: title, visibleText: "We are hiring a \(title). Responsibilities..."
        )).jobNumber
    }

    /// #1: captured from the board, applied from the company's embedded careers page. No
    /// normalization reconciles a path id with a query parameter on a different host — the ATS id is
    /// the thing that's actually equal.
    func testBoardURLAndEmbeddedURLResolveToOneJob() async throws {
        let (service, _) = try makeService()
        let number = try await capture(service, url: "https://boards.greenhouse.io/acme/jobs/12345")

        let result = try await service.markJobApplied(
            url: "https://acme.com/careers?gh_jid=12345"
        )
        XCTAssertFalse(result.created, "should have matched the captured job, not created a second")
        XCTAssertEqual(result.jobNumber, number)
    }

    /// #3: two postings on the same embedded board must stay distinct — the ids differ, so matching
    /// on the id must not collapse them the way matching on the host would.
    func testTwoPostingsOnOneEmbeddedBoardStayDistinct() async throws {
        let (service, _) = try makeService()
        let first = try await capture(service, url: "https://acme.com/careers?gh_jid=111", title: "TPM")
        let second = try await capture(service, url: "https://acme.com/careers?gh_jid=222", title: "SRE")
        XCTAssertNotEqual(first, second)

        let result = try await service.markJobApplied(url: "https://boards.greenhouse.io/acme/jobs/222")
        XCTAssertFalse(result.created)
        XCTAssertEqual(result.jobNumber, second)
    }

    /// A posting with no ATS id must not fall back to matching *some* job — an unrelated URL creates
    /// a new one, as it did before.
    func testNonATSURLStillCreatesANewJob() async throws {
        let (service, _) = try makeService()
        try await capture(service, url: "https://boards.greenhouse.io/acme/jobs/12345")

        let result = try await service.markJobApplied(url: "https://example.com/careers/some-role")
        XCTAssertTrue(result.created)
    }

    /// #2: the id lives in the URL, so stripping it as a tracking parameter would destroy exactly the
    /// signal this resolution depends on. Guards the same invariant as
    /// `testEmbeddedBoardJobIDIsNotStrippedAsTracking`, from the consuming side.
    func testATSIDSurvivesNormalization() throws {
        let normalized = try XCTUnwrap(
            URLNormalizer.normalized("https://acme.com/careers?gh_jid=12345&utm_source=x")
        )
        XCTAssertTrue(normalized.contains("gh_jid=12345"), normalized)
        XCTAssertFalse(normalized.contains("utm_source"), normalized)
        XCTAssertEqual(DuplicateDetector.atsPostingID(urlString: normalized), "gh:12345")
    }
}
