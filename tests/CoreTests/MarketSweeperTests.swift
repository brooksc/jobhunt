import Foundation
import SwiftData
import XCTest
@testable import JobhuntCore

/// Sweeping the whole directory, a resumable slice at a time (TASK-696).
///
/// The behaviour that matters is what happens when a sweep *doesn't* finish — which is the normal
/// case, since a full pass takes hours and the app gets quit. A sweep that restarts from zero every
/// launch never reaches the far end of the directory, and never reaching the end is
/// indistinguishable from there being nothing there.
final class MarketSweeperTests: XCTestCase {
    private struct NoOp: LLMProvider {
        let id: String = "noop"
        let concurrencyLimit: Int = 1
        func complete(_: ChatRequest) async throws -> ChatResponse {
            throw LLMProviderError.httpError(statusCode: 503, body: "no-op")
        }
    }

    private func makeStore() throws -> BackgroundStore {
        try BackgroundStore(modelContainer: ModelContainerFactory.inMemory())
    }

    private func makeSweeper(_ store: BackgroundStore, caps: DiscoveryCaps = .default) -> MarketSweeper {
        let queue = QueueActor(
            store: store, isPaused: { true }, onSetPaused: { _ in },
            readExtractionSettings: { ExtractionSettings(
                llmModel: "", preferredLocations: "", locationFilterEnabled: false,
                locationAllowRemote: true, locationAllowHybrid: true, locationAllowOnsite: true
            ) },
            providerFactory: { NoOp() }
        )
        return MarketSweeper(
            store: store,
            sweeper: DiscoverySweeper(
                store: store, jobService: JobService(store: store, queue: queue),
                session: MockURLProtocol.makeSession(), caps: caps, ledgerRejections: false
            ),
            session: MockURLProtocol.makeSession()
        )
    }

    private func boards(_ count: Int) -> [MarketBoard] {
        (1 ... count).map { MarketBoard(kind: "greenhouse", slug: "company-\($0)") }
    }

    private let criteria = DiscoveryCriteria(titleIncludeAny: ["program manager"])

    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
        // Every board answers with one matching posting, and its detail endpoint answers with a
        // real body — otherwise hydration fails and nothing is ever ingested, which would make
        // these tests measure the stub rather than the sweeper.
        MockURLProtocol.handlers.append(("boards-api.greenhouse.io", { request in
            let response = HTTPURLResponse(
                url: request.url ?? URL(fileURLWithPath: "/"), statusCode: 200,
                httpVersion: nil, headerFields: nil
            )!
            let path = request.url?.path ?? ""
            let segments = path.split(separator: "/").map(String.init)
            // /v1/boards/{slug}/jobs[/{id}] — the slug is at index 2.
            let slug = segments.count > 2 ? segments[2] : "x"
            let id = abs(slug.hashValue % 100_000)
            // .../boards/{slug}/jobs        → the board listing
            // .../boards/{slug}/jobs/{id}   → one posting, with a body
            let isDetail = segments.last != "jobs"
            let body = isDetail
                ? """
                { "id": \(id), "title": "Program Manager",
                  "content": "A real job description with enough text to be usable.",
                  "absolute_url": "https://boards.greenhouse.io/\(slug)/jobs/\(id)",
                  "location": { "name": "Remote, United States" } }
                """
                : """
                { "jobs": [ { "id": \(id), "title": "Program Manager",
                  "absolute_url": "https://boards.greenhouse.io/\(slug)/jobs/\(id)",
                  "location": { "name": "Remote, United States" } } ] }
                """
            return (response, Data(body.utf8))
        }))
    }

    override func tearDown() {
        MockURLProtocol.reset()
        super.tearDown()
    }

    // MARK: - Slicing

    func testASliceStopsAtItsBoardLimitAndReportsWhereItGotTo() async throws {
        let store = try makeStore()
        let sweeper = makeSweeper(store)
        let (slice, next) = await sweeper.sweepSlice(
            boards: boards(50), cursor: 0, boardLimit: 5, criteria: criteria,
            remainingDailyBudget: 100
        )
        XCTAssertEqual(slice.boardsSwept, 5)
        XCTAssertEqual(next, 5, "the cursor is where the next slice picks up")
    }

    /// The whole point of the cursor: a second slice continues rather than repeating.
    func testTheNextSliceContinuesFromTheCursor() async throws {
        let store = try makeStore()
        let sweeper = makeSweeper(store)
        let all = boards(20)
        let (_, afterFirst) = await sweeper.sweepSlice(
            boards: all, cursor: 0, boardLimit: 4, criteria: criteria, remainingDailyBudget: 100
        )
        let (second, afterSecond) = await sweeper.sweepSlice(
            boards: all, cursor: afterFirst, boardLimit: 4, criteria: criteria,
            remainingDailyBudget: 100
        )
        XCTAssertEqual(afterFirst, 4)
        XCTAssertEqual(afterSecond, 8)
        XCTAssertEqual(second.boardsSwept, 4)
    }

    func testASliceStopsAtTheEndOfTheDirectory() async throws {
        let store = try makeStore()
        let sweeper = makeSweeper(store)
        let (slice, next) = await sweeper.sweepSlice(
            boards: boards(3), cursor: 0, boardLimit: 100, criteria: criteria,
            remainingDailyBudget: 100
        )
        XCTAssertEqual(slice.boardsSwept, 3)
        XCTAssertEqual(next, 3)
    }

    // MARK: - Budget

    /// The daily cap is shared with the per-company scheduler, so a market sweep must stop when it's
    /// spent rather than keep finding postings it isn't allowed to act on.
    func testTheSliceStopsWhenTheDailyBudgetIsSpent() async throws {
        let store = try makeStore()
        let sweeper = makeSweeper(store, caps: DiscoveryCaps(perSweep: 1, perDay: 100))
        let (slice, next) = await sweeper.sweepSlice(
            boards: boards(50), cursor: 0, boardLimit: 50, criteria: criteria,
            remainingDailyBudget: 3
        )
        XCTAssertEqual(slice.postingsIngested, 3)
        XCTAssertNotNil(slice.stopReason, "a cap that stops a sweep has to say so")
        XCTAssertLessThan(next, 50, "the cursor stays put so tomorrow resumes here")
    }

    func testAnExhaustedBudgetSweepsNothingAtAll() async throws {
        let store = try makeStore()
        let sweeper = makeSweeper(store)
        let (slice, next) = await sweeper.sweepSlice(
            boards: boards(10), cursor: 0, boardLimit: 10, criteria: criteria,
            remainingDailyBudget: 0
        )
        XCTAssertEqual(slice.boardsSwept, 0, "no point reading boards we can't act on")
        XCTAssertEqual(next, 0)
    }

    // MARK: - Checkpointing

    func testProgressSurvivesAcrossSlices() async throws {
        let store = try makeStore()
        let sweeper = makeSweeper(store)
        try await store.startMarketSweep(boardCount: 20)

        let (first, next) = await sweeper.sweepSlice(
            boards: boards(20), cursor: 0, boardLimit: 4, criteria: criteria,
            remainingDailyBudget: 100
        )
        try await store.recordMarketSweepSlice(first, nextCursor: next)

        let loaded: MarketSweepState? = try await store.marketSweepState()
        let state = try XCTUnwrap(loaded)
        XCTAssertEqual(state.cursor, 4)
        XCTAssertEqual(state.boardsSwept, 4)
        XCTAssertEqual(state.progress, 0.2, accuracy: 0.001)
        XCTAssertFalse(state.isFinished)
    }

    func testReachingTheEndFinishesTheSweep() async throws {
        let store = try makeStore()
        try await store.startMarketSweep(boardCount: 5)
        try await store.recordMarketSweepSlice(MarketSweepSlice(), nextCursor: 5)

        let loaded: MarketSweepState? = try await store.marketSweepState()
        let state = try XCTUnwrap(loaded)
        XCTAssertTrue(state.isFinished)
        XCTAssertEqual(state.progress, 1)
        XCTAssertNil(state.pauseReason, "a finished sweep isn't paused")
    }

    /// An unfinished sweep is always due — resuming it is the entire point.
    func testAnUnfinishedSweepIsAlwaysDue() {
        XCTAssertTrue(MarketSweepState(boardCount: 100).isDue(startHour: 3))
    }

    /// A wall-clock start, not an interval after the last finish. "Every 24 hours" drifts by however
    /// long the pass took, so an overnight sweep creeps into the afternoon within a week.
    func testAFinishedSweepWaitsForTheNextScheduledHour() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        func at(_ day: Int, _ hour: Int) throws -> Date {
            try XCTUnwrap(calendar.date(
                from: DateComponents(year: 2026, month: 8, day: day, hour: hour)
            ))
        }

        let state = MarketSweepState(boardCount: 100)
        state.finishedAt = try at(23, 8) // started 3am, ran five hours

        XCTAssertFalse(
            try state.isDue(startHour: 3, now: at(23, 20), calendar: calendar),
            "same evening — 3am has not come round again"
        )
        XCTAssertFalse(
            try state.isDue(startHour: 3, now: at(24, 2), calendar: calendar),
            "just before the next 3am"
        )
        XCTAssertTrue(
            try state.isDue(startHour: 3, now: at(24, 3), calendar: calendar),
            "3am the next day, regardless of how long the last pass ran"
        )
    }

    /// The drift this replaces: a five-hour pass finishing at 08:00 would, on a 24h interval, next
    /// start at 08:00 — then 13:00, then 18:00. A wall-clock hour stays put.
    func testTheStartTimeDoesNotDriftWithPassLength() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        func at(_ day: Int, _ hour: Int) throws -> Date {
            try XCTUnwrap(calendar.date(
                from: DateComponents(year: 2026, month: 8, day: day, hour: hour)
            ))
        }
        for finishHour in [5, 8, 14, 23] {
            let state = MarketSweepState(boardCount: 100)
            state.finishedAt = try at(23, finishHour)
            XCTAssertTrue(
                try state.isDue(startHour: 3, now: at(24, 3), calendar: calendar),
                "due at 3am whether the previous pass ended at \(finishHour):00 or not"
            )
        }
    }

    func testStartingASweepReplacesTheFinishedOne() async throws {
        let store = try makeStore()
        try await store.startMarketSweep(boardCount: 10)
        try await store.recordMarketSweepSlice(MarketSweepSlice(), nextCursor: 10)
        try await store.startMarketSweep(boardCount: 20)

        let states: [MarketSweepState] = try await store.fetch(FetchDescriptor<MarketSweepState>())
        XCTAssertEqual(states.count, 1, "position is one row; history lives in the ledger")
        XCTAssertEqual(states.first?.boardCount, 20)
        XCTAssertEqual(states.first?.cursor, 0)
    }

    // MARK: - Ledger volume

    /// A market pass sees on the order of a million postings. Recording a row per rejection would
    /// grow the ledger without bound to save re-running a filter that costs microseconds — so only
    /// what jobhunt actually acted on is written down.
    func testRejectionsAreNotLedgeredDuringAMarketSweep() async throws {
        let store = try makeStore()
        let sweeper = makeSweeper(store)
        // Criteria nothing matches, so every posting is a rejection.
        _ = await sweeper.sweepSlice(
            boards: boards(10), cursor: 0, boardLimit: 10,
            criteria: DiscoveryCriteria(titleIncludeAny: ["nothing matches this"]),
            remainingDailyBudget: 100
        )
        let counts: [String: Int] = try await store.discoveryOutcomeCounts()
        XCTAssertTrue(counts.isEmpty, "the ledger must not grow by one row per posting looked at")
    }

    /// …but an ingest still is, or the next pass would re-ingest the same job.
    func testIngestsAreStillLedgered() async throws {
        let store = try makeStore()
        let sweeper = makeSweeper(store)
        _ = await sweeper.sweepSlice(
            boards: boards(3), cursor: 0, boardLimit: 3, criteria: criteria,
            remainingDailyBudget: 100
        )
        let counts: [String: Int] = try await store.discoveryOutcomeCounts()
        XCTAssertEqual(counts["ingested"], 3)
    }

    // MARK: - Pacing

    /// Each vendor gets the pacing its hosting shape calls for. Workday spreads across thousands of
    /// hosts but pays a POST and pagination per board; the others all land on one server each, which
    /// is the case career-ops measured going wrong under load.
    func testEachVendorGetsItsOwnPacing() {
        XCTAssertEqual(MarketPacing.forKind("greenhouse"), .singleHost)
        XCTAssertEqual(MarketPacing.forKind("lever"), .singleHost)
        XCTAssertEqual(MarketPacing.forKind("ashby"), .singleHost)
        XCTAssertEqual(MarketPacing.forKind("workday"), .perTenantHost)
        XCTAssertGreaterThan(
            MarketPacing.perTenantHost.delayMilliseconds, MarketPacing.singleHost.delayMilliseconds
        )
    }
}

/// Pagination depth, which is the difference between a daily sweep and a four-day one (TASK-696).
final class MarketPageLimitTests: XCTestCase {
    /// A watched company wants its whole board — the user asked for that employer by name.
    func testAWatchedCompanyGetsTheSourceDefault() {
        XCTAssertNil(SourceConfig(slug: "acme").pageLimit)
    }

    /// A market pass re-reads 12,884 Workday tenants daily and only needs what's new. Measured: at
    /// no page cap a 104-board run averaged 13.2s per board, which is 105 hours for a full pass.
    func testAMarketPassCapsPagination() {
        XCTAssertEqual(MarketSweeper.marketPageLimit, 5)
        XCTAssertLessThan(
            MarketSweeper.marketPageLimit, WorkdaySource.sweepMaxPages,
            "a market pass must not read as deep as a board the user asked for by name"
        )
    }

    /// The cap only binds where pagination exists. Greenhouse, Lever and Ashby each return their
    /// whole board in one response, so nothing is lost there.
    func testOnlyWorkdayPaginatesAtAll() async throws {
        MockURLProtocol.reset()
        defer { MockURLProtocol.reset() }
        MockURLProtocol.handlers.append(("boards-api.greenhouse.io", { request in
            let response = HTTPURLResponse(
                url: request.url ?? URL(fileURLWithPath: "/"), statusCode: 200,
                httpVersion: nil, headerFields: nil
            )!
            let jobs = (1 ... 40).map { index in
                """
                { "id": \(index), "title": "Program Manager \(index)",
                  "absolute_url": "https://boards.greenhouse.io/acme/jobs/\(index)",
                  "location": { "name": "Remote" } }
                """
            }.joined(separator: ",")
            return (response, Data("{ \"jobs\": [\(jobs)] }".utf8))
        }))

        // A page limit that would truncate a paginating vendor leaves a single-response one intact.
        let postings = try await GreenhouseSource().fetchRecent(
            config: SourceConfig(slug: "acme", pageLimit: 1), since: nil,
            session: MockURLProtocol.makeSession()
        )
        XCTAssertEqual(postings.count, 40)
    }
}
