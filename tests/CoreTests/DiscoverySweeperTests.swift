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
