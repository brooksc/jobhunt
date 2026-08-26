import Foundation
import SwiftData
import XCTest
@testable import JobhuntCore

/// One source, end to end: fetch → gate → ledger → hydrate → ingest (TASK-692, M3).
///
/// The order is the design, so most of these tests are about *what didn't happen*: how many
/// requests weren't made, how many extractions weren't queued. A sweeper that produces the right
/// jobs while hydrating all 15,000 rows would pass a naive test and be unusable.
final class DiscoverySweeperTests: XCTestCase {
    /// Never called — the queue is paused in every test here.
    private struct SweeperNoOpProvider: LLMProvider {
        let id: String = "noop"
        let concurrencyLimit: Int = 1
        func complete(_: ChatRequest) async throws -> ChatResponse {
            throw LLMProviderError.httpError(statusCode: 503, body: "no-op")
        }
    }

    /// A source that answers from memory rather than the network.
    private struct StubSource: JobSource {
        let id = "stub"
        let displayName = "Stub"
        let configuration = SourceConfiguration.perCompany(slugHint: "x")
        let postings: [DiscoveredPosting]
        let error: SourceError?

        init(postings: [DiscoveredPosting] = [], error: SourceError? = nil) {
            self.postings = postings
            self.error = error
        }

        func fetchRecent(
            config _: SourceConfig, since _: Date?, session _: URLSession
        ) async throws -> [DiscoveredPosting] {
            if let error {
                throw error
            }
            return postings
        }
    }

    /// Paused queue: the sweep's job is to create rows and enqueue them, not to run the LLM.
    private func makeSweeper(
        store: BackgroundStore, caps: DiscoveryCaps = .default
    ) -> DiscoverySweeper {
        let queue = QueueActor(
            store: store,
            isPaused: { true },
            onSetPaused: { _ in },
            readExtractionSettings: { ExtractionSettings(
                llmModel: "",
                preferredLocations: "",
                locationFilterEnabled: false,
                locationAllowRemote: true,
                locationAllowHybrid: true,
                locationAllowOnsite: true
            ) },
            providerFactory: { SweeperNoOpProvider() }
        )
        return DiscoverySweeper(
            store: store, jobService: JobService(store: store, queue: queue),
            session: MockURLProtocol.makeSession(), caps: caps
        )
    }

    private func posting(
        _ index: Int, title: String = "Program Manager", body: String? = "A real job description."
    ) -> DiscoveredPosting {
        DiscoveredPosting(
            dedupKey: "gh:\(index)",
            url: "https://boards.greenhouse.io/acme/jobs/\(index)",
            title: title, company: "Acme", locationRaw: "Remote, United States",
            descriptionPlain: body, sourceID: "stub"
        )
    }

    private let criteria = DiscoveryCriteria(titleIncludeAny: ["program manager"])

    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
    }

    override func tearDown() {
        MockURLProtocol.reset()
        super.tearDown()
    }

    // MARK: - The happy path

    func testAPassingPostingBecomesAJob() async throws {
        let store = try BackgroundStore(modelContainer: ModelContainerFactory.inMemory())
        let sweeper = makeSweeper(store: store)
        let result = await sweeper.sweep(
            source: StubSource(postings: [posting(1)]), config: SourceConfig(slug: "acme"),
            criteria: criteria
        )
        XCTAssertEqual(result.status, .ok)
        XCTAssertEqual(result.found, 1)
        XCTAssertEqual(result.passed, 1)
        XCTAssertEqual(result.ingested, 1)

        let jobs: [Job] = try await store.fetch(FetchDescriptor<Job>())
        XCTAssertEqual(jobs.count, 1)
        let captures: [Capture] = try await store.fetch(FetchDescriptor<Capture>())
        XCTAssertEqual(captures.first?.url, "https://boards.greenhouse.io/acme/jobs/1")
    }

    /// Provenance the user can read, rather than a `discovered` status that would touch every
    /// status-handling site in the app.
    func testAnIngestedJobSaysWhereItCameFrom() async throws {
        let store = try BackgroundStore(modelContainer: ModelContainerFactory.inMemory())
        let sweeper = makeSweeper(store: store)
        _ = await sweeper.sweep(
            source: StubSource(postings: [posting(1)]), config: SourceConfig(slug: "acme"),
            criteria: criteria
        )
        let captures: [Capture] = try await store.fetch(FetchDescriptor<Capture>())
        let note = try XCTUnwrap(captures.first?.userNote)
        XCTAssertTrue(note.contains("Found automatically"), note)
        XCTAssertTrue(note.contains("Stub"), note)
    }

    // MARK: - The gate runs before anything expensive

    func testRejectedPostingsAreCountedAndNeverIngested() async throws {
        let store = try BackgroundStore(modelContainer: ModelContainerFactory.inMemory())
        let sweeper = makeSweeper(store: store)
        let result = await sweeper.sweep(
            source: StubSource(postings: [
                posting(1), posting(2, title: "Backend Engineer"), posting(3, title: "Data Analyst")
            ]),
            config: SourceConfig(slug: "acme"), criteria: criteria
        )
        XCTAssertEqual(result.found, 3)
        XCTAssertEqual(result.passed, 1)
        XCTAssertEqual(result.ingested, 1)
        XCTAssertEqual(result.rejections[.title], 2)

        let jobs: [Job] = try await store.fetch(FetchDescriptor<Job>())
        XCTAssertEqual(jobs.count, 1)
    }

    /// The claim the whole ordering exists to support: a second sweep of an unchanged board does no
    /// work at all. Without the ledger check this would re-ingest everything on every run.
    func testASecondSweepOfAnUnchangedBoardIngestsNothing() async throws {
        let store = try BackgroundStore(modelContainer: ModelContainerFactory.inMemory())
        let sweeper = makeSweeper(store: store)
        let source = StubSource(postings: [posting(1), posting(2)])

        let first = await sweeper.sweep(
            source: source, config: SourceConfig(slug: "acme"), criteria: criteria
        )
        let second = await sweeper.sweep(
            source: source, config: SourceConfig(slug: "acme"), criteria: criteria
        )
        XCTAssertEqual(first.ingested, 2)
        XCTAssertEqual(second.ingested, 0, "everything was already judged")
        XCTAssertEqual(second.found, 2, "…but the board was still read, so health stays accurate")

        let jobs: [Job] = try await store.fetch(FetchDescriptor<Job>())
        XCTAssertEqual(jobs.count, 2)
    }

    // MARK: - Hydration

    /// A job whose description is its own title would be extracted into nonsense and then
    /// fit-scored against the nonsense. Not having the row is better, and the ledger records the
    /// failure so the next sweep retries it.
    func testAPostingThatCannotBeGivenABodyIsNotIngested() async throws {
        let store = try BackgroundStore(modelContainer: ModelContainerFactory.inMemory())
        let sweeper = makeSweeper(store: store)
        // No inline body, and the stubbed network returns nothing usable for the detail fetch.
        MockURLProtocol.handlers.append(("boards-api.greenhouse.io", { request in
            let response = HTTPURLResponse(
                url: request.url ?? URL(fileURLWithPath: "/"), statusCode: 404,
                httpVersion: nil, headerFields: nil
            )!
            return (response, Data())
        }))

        let result = await sweeper.sweep(
            source: StubSource(postings: [posting(1, body: nil)]),
            config: SourceConfig(slug: "acme"), criteria: criteria
        )
        XCTAssertEqual(result.passed, 1)
        XCTAssertEqual(result.ingested, 0)
        XCTAssertEqual(result.hydrationFailures, 1)

        let jobs: [Job] = try await store.fetch(FetchDescriptor<Job>())
        XCTAssertTrue(jobs.isEmpty)
    }

    /// Lever and Ashby ship the body in the board payload, so no request is needed at all.
    func testAnInlineBodyNeedsNoSecondRequest() async throws {
        let store = try BackgroundStore(modelContainer: ModelContainerFactory.inMemory())
        let sweeper = makeSweeper(store: store)
        // Any detail request would 500; the sweep must not make one.
        MockURLProtocol.handlers.append(("greenhouse", { request in
            let response = HTTPURLResponse(
                url: request.url ?? URL(fileURLWithPath: "/"), statusCode: 500,
                httpVersion: nil, headerFields: nil
            )!
            return (response, Data())
        }))
        let result = await sweeper.sweep(
            source: StubSource(postings: [posting(1, body: "Inline description from the board.")]),
            config: SourceConfig(slug: "acme"), criteria: criteria
        )
        XCTAssertEqual(result.ingested, 1)
        XCTAssertEqual(result.hydrationFailures, 0)
    }

    // MARK: - Caps

    /// The cap bounds hydration, not just ingest — it's applied before any request is made, which
    /// is the difference between spending 50 requests and 6,000.
    func testThePerSweepCapBoundsWhatIsIngested() async throws {
        let store = try BackgroundStore(modelContainer: ModelContainerFactory.inMemory())
        let sweeper = makeSweeper(store: store, caps: DiscoveryCaps(perSweep: 2, perDay: 100))
        let result = await sweeper.sweep(
            source: StubSource(postings: (1 ... 10).map { posting($0) }),
            config: SourceConfig(slug: "acme"), criteria: criteria
        )
        XCTAssertEqual(result.passed, 10)
        XCTAssertEqual(result.ingested, 2)
        XCTAssertEqual(
            result.truncatedByCap, 8,
            "a silent cap reads as 'nothing more was found' — the count has to reach the UI"
        )
    }

    /// The day budget is passed in rather than read here, so one greedy source can't exhaust what
    /// the others were going to use.
    func testTheDailyBudgetOverridesALargerPerSweepCap() async throws {
        let store = try BackgroundStore(modelContainer: ModelContainerFactory.inMemory())
        let sweeper = makeSweeper(store: store, caps: DiscoveryCaps(perSweep: 50, perDay: 200))
        let result = await sweeper.sweep(
            source: StubSource(postings: (1 ... 10).map { posting($0) }),
            config: SourceConfig(slug: "acme"), criteria: criteria, remainingDailyBudget: 3
        )
        XCTAssertEqual(result.ingested, 3)
        XCTAssertEqual(result.truncatedByCap, 7)
    }

    func testAnExhaustedBudgetIngestsNothingButStillReports() async throws {
        let store = try BackgroundStore(modelContainer: ModelContainerFactory.inMemory())
        let sweeper = makeSweeper(store: store)
        let result = await sweeper.sweep(
            source: StubSource(postings: [posting(1)]), config: SourceConfig(slug: "acme"),
            criteria: criteria, remainingDailyBudget: 0
        )
        XCTAssertEqual(result.ingested, 0)
        XCTAssertEqual(result.truncatedByCap, 1)
        XCTAssertEqual(result.found, 1, "health still reflects that the board answered")
    }

    // MARK: - Health

    /// The distinction the whole `SourceError` type exists for. An empty board is a successful run
    /// with nothing in it, and it must not be filed as a failure — nor a failure as an empty board.
    func testAnEmptyBoardIsEmptyAndAnUnreachableOneIsUnreachable() async throws {
        let store = try BackgroundStore(modelContainer: ModelContainerFactory.inMemory())
        let sweeper = makeSweeper(store: store)

        let empty = await sweeper.sweep(
            source: StubSource(postings: []), config: SourceConfig(slug: "acme"), criteria: criteria
        )
        XCTAssertEqual(empty.status, .empty)
        XCTAssertNil(empty.error)

        let down = await sweeper.sweep(
            source: StubSource(error: .unreachable("HTTP 503")), config: SourceConfig(slug: "acme"),
            criteria: criteria
        )
        XCTAssertEqual(down.status, .unreachable)
        XCTAssertEqual(down.error, "HTTP 503")
    }

    func testAMisconfiguredSourceIsDistinctFromAnUnreachableOne() async throws {
        let store = try BackgroundStore(modelContainer: ModelContainerFactory.inMemory())
        let sweeper = makeSweeper(store: store)
        let result = await sweeper.sweep(
            source: StubSource(error: .misconfigured("not a Workday board URL")),
            config: SourceConfig(slug: "?"), criteria: criteria
        )
        XCTAssertEqual(
            result.status, .misconfigured,
            "the user can fix this one, and a red 'unreachable' dot would send them to check the network"
        )
    }
}

/// Discovery only ever creates (TASK-699).
///
/// `ingestCapture`'s same-URL path is a *recapture*: it overwrites the stored capture, resets
/// extraction and re-queues it. That is right when a user deliberately re-captures a posting in the
/// browser, and wrong for an unattended sweep — without this guard a first market pass would
/// re-extract every job the user already had whose posting was still open, spending real money to
/// replace descriptions they were happy with.
final class DiscoveryNeverTouchesExistingJobsTests: XCTestCase {
    private struct NoOp: LLMProvider {
        let id: String = "noop"
        let concurrencyLimit: Int = 1
        func complete(_: ChatRequest) async throws -> ChatResponse {
            throw LLMProviderError.httpError(statusCode: 503, body: "no-op")
        }
    }

    private struct StubSource: JobSource {
        let id = "stub"
        let displayName = "Stub"
        let configuration = SourceConfiguration.perCompany(slugHint: "x")
        let postings: [DiscoveredPosting]
        func fetchRecent(
            config _: SourceConfig, since _: Date?, session _: URLSession
        ) async throws -> [DiscoveredPosting] {
            postings
        }
    }

    private func makeSweeper(_ store: BackgroundStore) -> DiscoverySweeper {
        let queue = QueueActor(
            store: store, isPaused: { true }, onSetPaused: { _ in },
            readExtractionSettings: { ExtractionSettings(
                llmModel: "", preferredLocations: "", locationFilterEnabled: false,
                locationAllowRemote: true, locationAllowHybrid: true, locationAllowOnsite: true
            ) },
            providerFactory: { NoOp() }
        )
        return DiscoverySweeper(
            store: store, jobService: JobService(store: store, queue: queue),
            session: MockURLProtocol.makeSession()
        )
    }

    func testAPostingTheUserAlreadyHasIsNotIngestedAgain() async throws {
        let store = try BackgroundStore(modelContainer: ModelContainerFactory.inMemory())
        // A job the user captured through the browser, with the tracking parameter the extension
        // would have picked up.
        let capture = Capture(
            url: "https://boards.greenhouse.io/acme/jobs/4567?gh_src=abc",
            pageTitle: "Program Manager", rawHash: "existing"
        )
        let job = Job(company: "Acme")
        job.capture = capture
        try await store.insert(job)

        // The sweep sees the same posting without the tracking parameter.
        let posting = DiscoveredPosting(
            dedupKey: "gh:4567", url: "https://boards.greenhouse.io/acme/jobs/4567",
            title: "Program Manager", company: "Acme", locationRaw: "Remote",
            descriptionPlain: "A description.", sourceID: "stub"
        )
        let known: Set<String> = try await store.capturedDedupKeys()
        XCTAssertTrue(
            known.contains("gh:4567"),
            "keyed on the ATS id, so a tracking parameter doesn't make it look like a different job"
        )

        let result = await makeSweeper(store).sweep(
            source: StubSource(postings: [posting]), config: SourceConfig(slug: "acme"),
            criteria: DiscoveryCriteria(titleIncludeAny: ["program manager"]),
            alreadyCaptured: known
        )
        XCTAssertEqual(result.passed, 1, "it still matches the criteria")
        XCTAssertEqual(result.ingested, 0, "…but the user already has it")

        let jobs: [Job] = try await store.fetch(FetchDescriptor<Job>())
        XCTAssertEqual(jobs.count, 1, "no second job, and no recapture of the first")
    }

    /// Without the guard, the same posting would go through — which is what makes the guard the
    /// thing doing the work rather than some incidental dedup.
    func testWithoutTheGuardItWouldHaveBeenIngested() async throws {
        let store = try BackgroundStore(modelContainer: ModelContainerFactory.inMemory())
        let posting = DiscoveredPosting(
            dedupKey: "gh:4567", url: "https://boards.greenhouse.io/acme/jobs/4567",
            title: "Program Manager", company: "Acme", locationRaw: "Remote",
            descriptionPlain: "A description.", sourceID: "stub"
        )
        let result = await makeSweeper(store).sweep(
            source: StubSource(postings: [posting]), config: SourceConfig(slug: "acme"),
            criteria: DiscoveryCriteria(titleIncludeAny: ["program manager"]),
            alreadyCaptured: []
        )
        XCTAssertEqual(result.ingested, 1)
    }
}

/// The safety property, stated against a realistic job rather than a synthetic one (TASK-699).
///
/// A recapture is destructive in ways that are easy to underestimate: it wipes every AI-extracted
/// field (`clearExtractionOwnedFields` nils company, title, location, salary, seniority, remote
/// type), sets extraction back to pending, queues a fresh LLM request, and moves a `.duplicate` job
/// to `.new`. Manual overrides survive, nothing else does. So this pins the whole shape of an
/// existing job across a sweep, not just its count.
final class DiscoveryLeavesExistingJobsTests: XCTestCase {
    private struct NoOp: LLMProvider {
        let id: String = "noop"
        let concurrencyLimit: Int = 1
        func complete(_: ChatRequest) async throws -> ChatResponse {
            throw LLMProviderError.httpError(statusCode: 503, body: "no-op")
        }
    }

    private struct StubSource: JobSource {
        let id = "stub"
        let displayName = "Stub"
        let configuration = SourceConfiguration.perCompany(slugHint: "x")
        let postings: [DiscoveredPosting]
        func fetchRecent(
            config _: SourceConfig, since _: Date?, session _: URLSession
        ) async throws -> [DiscoveredPosting] {
            postings
        }
    }

    func testAnAlreadyTrackedJobSurvivesASweepUnchanged() async throws {
        let store = try BackgroundStore(modelContainer: ModelContainerFactory.inMemory())

        let capture = Capture(
            url: "https://boards.greenhouse.io/acme/jobs/4567?gh_src=browser",
            pageTitle: "Senior Program Manager",
            cleanedDescription: "The description the user already had.",
            rawHash: "browser-capture"
        )
        let job = Job(company: "Acme")
        job.title = "Senior Program Manager"
        job.location = "Remote, United States"
        job.salaryMin = 180_000
        job.status = .pursuing
        job.extractionStatus = .succeeded
        job.extractedJSON = #"{"company":"Acme"}"#
        job.fitScore = 82
        job.capture = capture
        try await store.insert(job)

        let queue = QueueActor(
            store: store, isPaused: { true }, onSetPaused: { _ in },
            readExtractionSettings: { ExtractionSettings(
                llmModel: "", preferredLocations: "", locationFilterEnabled: false,
                locationAllowRemote: true, locationAllowHybrid: true, locationAllowOnsite: true
            ) },
            providerFactory: { NoOp() }
        )
        let sweeper = DiscoverySweeper(
            store: store, jobService: JobService(store: store, queue: queue),
            session: MockURLProtocol.makeSession()
        )
        let known: Set<String> = try await store.capturedDedupKeys()
        _ = await sweeper.sweep(
            source: StubSource(postings: [DiscoveredPosting(
                dedupKey: "gh:4567", url: "https://boards.greenhouse.io/acme/jobs/4567",
                title: "Senior Program Manager", company: "Acme",
                locationRaw: "Remote, United States",
                descriptionPlain: "A DIFFERENT description from the ATS.", sourceID: "stub"
            )]),
            config: SourceConfig(slug: "acme"),
            criteria: DiscoveryCriteria(titleIncludeAny: ["program manager"]),
            alreadyCaptured: known
        )

        let jobs: [Job] = try await store.fetch(FetchDescriptor<Job>())
        let after = try XCTUnwrap(jobs.first)
        XCTAssertEqual(jobs.count, 1)
        XCTAssertEqual(after.status, .pursuing, "the user's own triage decision must survive")
        XCTAssertEqual(after.extractionStatus, .succeeded, "no re-extraction was queued")
        XCTAssertEqual(after.company, "Acme", "extracted fields must not be wiped")
        XCTAssertEqual(after.title, "Senior Program Manager")
        XCTAssertEqual(after.location, "Remote, United States")
        XCTAssertEqual(after.salaryMin, 180_000)
        XCTAssertEqual(after.fitScore, 82, "the fit score cost money and must not be discarded")
        XCTAssertNotNil(after.extractedJSON)

        let captures: [Capture] = try await store.fetch(FetchDescriptor<Capture>())
        XCTAssertEqual(
            captures.first?.cleanedDescription, "The description the user already had.",
            "the stored description must not be overwritten by the sweep's version"
        )

        // The decisive one: a recapture always queues an extract request. None here means none ran.
        let requests: [LLMRequest] = try await store.fetch(FetchDescriptor<LLMRequest>())
        XCTAssertTrue(requests.isEmpty, "no LLM spend on a job the user already had")
    }
}

/// The create-only guarantee, tested where it actually lives (TASK-700).
///
/// The earlier tests handed the sweeper a correct snapshot of existing keys, which proves the
/// optimisation works and proves nothing about the guarantee. These go at the store instead, and
/// cover the three ways the snapshot approach failed: a caller that forgets it, a snapshot that
/// goes stale mid-sweep, and a lookup that throws.
final class CreateOnlyIngestTests: XCTestCase {
    private struct NoOp: LLMProvider {
        let id: String = "noop"
        let concurrencyLimit: Int = 1
        func complete(_: ChatRequest) async throws -> ChatResponse {
            throw LLMProviderError.httpError(statusCode: 503, body: "no-op")
        }
    }

    private func makeService(_ store: BackgroundStore) -> JobService {
        JobService(store: store, queue: QueueActor(
            store: store, isPaused: { true }, onSetPaused: { _ in },
            readExtractionSettings: { ExtractionSettings(
                llmModel: "", preferredLocations: "", locationFilterEnabled: false,
                locationAllowRemote: true, locationAllowHybrid: true, locationAllowOnsite: true
            ) },
            providerFactory: { NoOp() }
        ))
    }

    private func seedExistingJob(_ store: BackgroundStore) async throws {
        let capture = Capture(
            url: "https://boards.greenhouse.io/acme/jobs/4567",
            pageTitle: "Program Manager",
            cleanedDescription: "The description the user already had.",
            rawHash: "browser-capture"
        )
        let job = Job(company: "Acme")
        job.title = "Program Manager"
        job.status = .pursuing
        job.extractionStatus = .succeeded
        job.capture = capture
        try await store.insert(job)
    }

    private func payload(_ body: String) -> CapturePayload {
        CapturePayload(
            url: "https://boards.greenhouse.io/acme/jobs/4567",
            pageTitle: "Program Manager",
            visibleText: body,
            userNote: "Found automatically via Greenhouse on 2026-08-23"
        )
    }

    /// The guarantee holds with NO snapshot at all — which is the whole point of moving it into the
    /// store. This is the case that was broken: Run Now passed no keys and would have recaptured.
    func testCreateOnlyRefusesEvenWithNoCallerSideFiltering() async throws {
        let store = try BackgroundStore(modelContainer: ModelContainerFactory.inMemory())
        try await seedExistingJob(store)

        let result = try await makeService(store).ingestCapture(
            payload("A DIFFERENT description from the ATS."), createOnly: true
        )

        XCTAssertTrue(result.alreadyExisted)
        let jobs: [Job] = try await store.fetch(FetchDescriptor<Job>())
        let job = try XCTUnwrap(jobs.first)
        XCTAssertEqual(jobs.count, 1)
        XCTAssertEqual(job.status, .pursuing, "the user's triage decision survives")
        XCTAssertEqual(job.extractionStatus, .succeeded, "extraction was not reset")
        XCTAssertEqual(job.title, "Program Manager", "extracted fields were not wiped")

        let captures: [Capture] = try await store.fetch(FetchDescriptor<Capture>())
        XCTAssertEqual(
            captures.first?.cleanedDescription, "The description the user already had.",
            "the stored description was not overwritten"
        )
        let requests: [LLMRequest] = try await store.fetch(FetchDescriptor<LLMRequest>())
        XCTAssertTrue(requests.isEmpty, "no paid extraction was queued")
    }

    /// Without `createOnly` the very same call recaptures, so the flag is demonstrably what does the
    /// work — and this pins how destructive the path it guards actually is.
    func testWithoutCreateOnlyTheSameCallIsDestructive() async throws {
        let store = try BackgroundStore(modelContainer: ModelContainerFactory.inMemory())
        try await seedExistingJob(store)

        _ = try await makeService(store).ingestCapture(payload("A DIFFERENT description."))

        let jobs: [Job] = try await store.fetch(FetchDescriptor<Job>())
        let job = try XCTUnwrap(jobs.first)
        XCTAssertEqual(job.extractionStatus, .pending, "recapture resets extraction")
        XCTAssertNil(job.title, "recapture wipes the extracted fields")
        let requests: [LLMRequest] = try await store.fetch(FetchDescriptor<LLMRequest>())
        XCTAssertEqual(requests.count, 1, "recapture queues a paid extraction")
    }

    /// A job that arrives *after* a sweep took its snapshot — a browser capture mid-sweep, or an
    /// overlapping run. The snapshot can't know about it; the store transaction can.
    func testAJobCreatedAfterTheSnapshotIsStillProtected() async throws {
        let store = try BackgroundStore(modelContainer: ModelContainerFactory.inMemory())
        let service = makeService(store)

        // Snapshot taken while the store is empty — maximally stale.
        let snapshot: Set<String> = try await store.capturedDedupKeys()
        XCTAssertTrue(snapshot.isEmpty)

        try await seedExistingJob(store)

        let result = try await service.ingestCapture(payload("Later ATS body."), createOnly: true)
        XCTAssertTrue(result.alreadyExisted, "the store saw it even though the snapshot could not")
        let requests: [LLMRequest] = try await store.fetch(FetchDescriptor<LLMRequest>())
        XCTAssertTrue(requests.isEmpty)
    }

    /// A genuinely new posting still gets created — the guard must not be a blanket refusal.
    func testANewPostingIsStillCreated() async throws {
        let store = try BackgroundStore(modelContainer: ModelContainerFactory.inMemory())
        let result = try await makeService(store).ingestCapture(
            payload("A real description."), createOnly: true
        )
        XCTAssertFalse(result.alreadyExisted)
        let jobs: [Job] = try await store.fetch(FetchDescriptor<Job>())
        XCTAssertEqual(jobs.count, 1)
    }
}

/// What a sweep reports as *progress*, and why the market cursor depends on getting it right
/// (TASK-703 follow-up). A board reported as having moved forward keeps the cursor; one reported
/// as stalled loses its remaining matches until the next full pass over ~29,000 boards.
final class SweepProgressAccountingTests: XCTestCase {
    private struct NoOp: LLMProvider {
        let id: String = "noop"
        let concurrencyLimit: Int = 1
        func complete(_: ChatRequest) async throws -> ChatResponse {
            throw LLMProviderError.httpError(statusCode: 503, body: "no-op")
        }
    }

    private struct StubSource: JobSource {
        let id = "stub"
        let displayName = "Stub"
        let configuration = SourceConfiguration.perCompany(slugHint: "x")
        let postings: [DiscoveredPosting]
        func fetchRecent(
            config _: SourceConfig, since _: Date?, session _: URLSession
        ) async throws -> [DiscoveredPosting] {
            postings
        }
    }

    private func makeSweeper(_ store: BackgroundStore, caps: DiscoveryCaps) -> DiscoverySweeper {
        let queue = QueueActor(
            store: store, isPaused: { true }, onSetPaused: { _ in },
            readExtractionSettings: { ExtractionSettings(
                llmModel: "", preferredLocations: "", locationFilterEnabled: false,
                locationAllowRemote: true, locationAllowHybrid: true, locationAllowOnsite: true
            ) },
            providerFactory: { NoOp() }
        )
        return DiscoverySweeper(
            store: store, jobService: JobService(store: store, queue: queue),
            session: MockURLProtocol.makeSession(), caps: caps, ledgerRejections: false
        )
    }

    private func posting(_ index: Int) -> DiscoveredPosting {
        DiscoveredPosting(
            dedupKey: "gh:\(index)",
            url: "https://boards.greenhouse.io/acme/jobs/\(index)",
            title: "Program Manager", company: "Acme", locationRaw: "Remote, United States",
            descriptionPlain: "A real job description, long enough to be usable."
        )
    }

    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
    }

    /// A posting the user already holds is settled work: it is now in the ledger, so the next visit
    /// skips it. Counting only *created* jobs meant a capped batch that settled fifty
    /// already-captured postings reported zero progress and the board was abandoned.
    func testAlreadyCapturedPostingsCountAsProgress() async throws {
        let store = try BackgroundStore(modelContainer: ModelContainerFactory.inMemory())
        let sweeper = makeSweeper(store, caps: DiscoveryCaps(perSweep: 2, perDay: 100))
        let postings = (1 ... 5).map { posting($0) }

        let result = await sweeper.sweep(
            source: StubSource(postings: postings),
            config: SourceConfig(slug: "acme"),
            criteria: DiscoveryCriteria(titleIncludeAny: ["program manager"]),
            alreadyCaptured: Set(postings.map(\.dedupKey))
        )
        XCTAssertEqual(result.ingested, 0, "the user already has every one of them")
        XCTAssertEqual(result.settled, 5, "…but all five are now settled and will be skipped next time")
    }

    /// Cancellation stops the ingest loop mid-batch. The postings it never reached are neither
    /// truncated by the cap nor recorded in the ledger, so without saying so the board looks
    /// finished and the market cursor moves past it.
    func testCancellationReportsTheBoardAsUnfinished() async throws {
        let store = try BackgroundStore(modelContainer: ModelContainerFactory.inMemory())
        let sweeper = makeSweeper(store, caps: DiscoveryCaps(perSweep: 50, perDay: 100))
        let postings = (1 ... 10).map { posting($0) }
        let source = StubSource(postings: postings)
        let criteria = DiscoveryCriteria(titleIncludeAny: ["program manager"])

        let task = Task {
            await sweeper.sweep(
                source: source, config: SourceConfig(slug: "acme"),
                criteria: criteria, alreadyCaptured: []
            )
        }
        task.cancel()
        let result = await task.value

        if result.cancelled {
            XCTAssertGreaterThan(
                result.truncatedByCap, 0,
                "postings admitted to the batch but never looked at are unfinished work"
            )
        }
        // The board must never read as finished-and-empty when it was cut short.
        XCTAssertFalse(
            result.cancelled && result.truncatedByCap == 0,
            "a cancelled sweep that claims nothing is outstanding would advance the cursor"
        )
    }

    /// A board with fewer matches than the cap, all handled, is finished: nothing outstanding.
    func testAFullyProcessedBoardReportsNothingOutstanding() async throws {
        let store = try BackgroundStore(modelContainer: ModelContainerFactory.inMemory())
        let sweeper = makeSweeper(store, caps: DiscoveryCaps(perSweep: 50, perDay: 100))
        let postings = (1 ... 3).map { posting($0) }

        let result = await sweeper.sweep(
            source: StubSource(postings: postings),
            config: SourceConfig(slug: "acme"),
            criteria: DiscoveryCriteria(titleIncludeAny: ["program manager"]),
            alreadyCaptured: []
        )
        XCTAssertFalse(result.cancelled)
        XCTAssertEqual(result.truncatedByCap, 0)
        XCTAssertEqual(result.settled, 3)
    }
}
