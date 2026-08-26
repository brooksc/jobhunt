import Foundation
import SwiftData

/// How gently to walk each vendor's boards.
///
/// **Patience is the design.** The brief was explicit: comprehensiveness beats speed, because the
/// cost of missing the right job is far higher than the cost of a sweep taking all day. So the
/// sweep is *sequential* — one board at a time, with a pause between — rather than fanning out.
///
/// That is a deliberate choice, not an oversight. career-ops measured what fan-out does to the
/// single-host vendors: at 20 concurrent, Lever's unreachable count went 2,436 → 4,100 and Ashby's
/// 683 → 1,675 across two sweeps an hour apart, recovering afterwards with no change to the
/// dataset. Those boards were never dead — they were refused, and every match on them was lost
/// silently. Since a missed match is the one outcome this feature exists to prevent, and since
/// nothing here is in a hurry, the safe setting wins.
///
/// **What that costs.** At roughly 185 ms per board (a 63 ms median fetch plus the pause),
/// Greenhouse, Lever and Ashby's 15,862 boards take about 50 minutes of sweep time. Workday is the
/// slow half: every tenant is a separate host needing a POST and pagination, so its 12,884 boards
/// run to several hours. A full pass is therefore most of a day of app-open time, spread across
/// slices — which is what `MarketSweepState`'s cursor exists to survive.
public struct MarketPacing: Sendable, Equatable {
    /// Pause after each board.
    public var delayMilliseconds: Int

    public init(delayMilliseconds: Int) {
        self.delayMilliseconds = delayMilliseconds
    }

    /// Greenhouse, Lever and Ashby serve their *entire* directory from one hostname each, so every
    /// request lands on the same server. See the note above on what happens when that is rushed.
    public static let singleHost = MarketPacing(delayMilliseconds: 120)

    /// Workday gives every tenant its own host, so successive requests hit different servers and the
    /// limiting factor is the resolver rather than any one vendor. Still paced, because each board
    /// is a POST plus pagination.
    public static let perTenantHost = MarketPacing(delayMilliseconds: 250)

    public static func forKind(_ kind: String) -> MarketPacing {
        kind == "workday" ? .perTenantHost : .singleHost
    }
}

/// What one slice of a market sweep did.
public struct MarketSweepSlice: Sendable, Equatable {
    public var boardsSwept = 0
    public var boardsUnreachable = 0
    public var postingsSeen = 0
    public var postingsPassed = 0
    public var postingsIngested = 0
    /// Set when the slice stopped early for a reason the user should see.
    public var stopReason: String?
}

/// Sweeps the public directory of ~29,000 boards, a slice at a time (TASK-696).
///
/// **A change detector, not an inventory.** It runs every day over the same boards, so it only has
/// to notice what is *new* — and vendors list newest-first. That is what makes `marketPageLimit`
/// affordable: reading the 100 newest postings from each Workday tenant daily costs eight hours a
/// pass, while reading all 2,000 costs four days, and the extra 1,900 are postings that either were
/// already seen yesterday or were rejected yesterday. Measured, not assumed: a 104-board test run
/// averaged 13.2 s per board with no page cap, which extrapolates to 105 hours for a full pass.
///
/// **Why a slice and not a loop.** A full pass takes hours, and the app will be quit, slept and
/// relaunched several times before it finishes. So this does a bounded amount of work per call and
/// persists its cursor, which makes the sweep resumable rather than restartable. A run that never
/// finishes finds nothing, and that is the failure mode of every naive version of this.
///
/// **What it does not do.** It doesn't create a `SearchSource` per board — 29,000 scheduled sources
/// would be absurd, and the scheduler is built for the handful of companies a user actively
/// watches. A market board is swept once per pass and remembered only through the ledger, which
/// records what was *acted on* rather than what was looked at.
public struct MarketSweeper: Sendable {
    let store: BackgroundStore
    let sweeper: DiscoverySweeper
    let session: URLSession

    /// Pages per board for vendors that paginate. Five pages is the 100 newest postings, which is
    /// far more than a day's worth of new listings on any real tenant. The first pass of a very
    /// large tenant sees only its newest 100; every pass after that catches anything added since.
    public static let marketPageLimit = 5

    public init(store: BackgroundStore, sweeper: DiscoverySweeper, session: URLSession = .shared) {
        self.store = store
        self.sweeper = sweeper
        self.session = session
    }

    /// Sweep up to `boardLimit` boards starting at `cursor`.
    ///
    /// - Parameter remainingDailyBudget: ingests still allowed today, shared with the per-company
    ///   scheduler. Decremented as boards produce jobs; the slice stops when it reaches zero, since
    ///   continuing would only find postings it isn't allowed to act on.
    public func sweepSlice(
        boards: [MarketBoard],
        cursor: Int,
        boardLimit: Int,
        criteria: DiscoveryCriteria,
        remainingDailyBudget: Int,
        now: Date = Date()
    ) async -> (slice: MarketSweepSlice, nextCursor: Int) {
        var slice = MarketSweepSlice()
        var budget = remainingDailyBudget
        var index = cursor
        // Once per slice, not per board: it scans the capture table, which is cheap a few hundred
        // times and ruinous 28,746 times.
        let alreadyCaptured = await (try? store.capturedDedupKeys()) ?? []

        guard budget > 0 else {
            slice.stopReason = "daily new-job limit reached — resumes tomorrow"
            return (slice, index)
        }

        let end = min(boards.count, cursor + boardLimit)
        while index < end {
            if Task.isCancelled {
                break
            }

            let board = boards[index]
            guard let source = JobSources.source(id: board.kind) else {
                index += 1
                continue
            }
            let result = await sweeper.sweep(
                source: source,
                config: SourceConfig(
                    slug: board.slug, pageLimit: Self.marketPageLimit,
                    // A market pass reads each board once, and the shared cache has no size limit.
                    useCache: false
                ),
                criteria: criteria,
                remainingDailyBudget: budget,
                alreadyCaptured: alreadyCaptured,
                now: now
            )

            // Advance only once the board is genuinely finished with. A board whose matches were
            // cut off by the per-sweep cap still has postings we have never looked at, and moving
            // past it would defer them to the *next full pass* — by which time a Workday tenant's
            // bounded result window may no longer include them. The ledger makes the retry cheap:
            // everything already ingested is skipped, so a re-swept board only does the remainder.
            //
            // **But staying has to be earned.** A hydration failure is deliberately retryable, so a
            // board with more unhydratable matches than the cap allows produces the same truncation
            // every visit — and with no progress to shrink it, the cursor would sit on that one
            // board forever and the entire market sweep would stop advancing. Permanently, and
            // silently, on one bad vendor endpoint. So the sweep only waits on a board it is
            // actually making progress through; a visit that ingested nothing moves on and picks the
            // board up on the next full pass.
            // Progress is what was *settled*, not what was created. A capped batch that recorded
            // fifty postings the user already had moved this board forward by fifty even though it
            // produced no job, and calling that a stall abandons the rest of the board until the
            // next full pass.
            let stalled = result.settled == 0 && budget > 0
            // A cancelled board is unfinished whatever else is true: it stopped because the app is
            // going away, not because the board ran out, so advancing past it would skip the rest
            // of it until the next full pass.
            let boardIsFinished = (result.truncatedByCap == 0 || stalled)
                && result.status != .rateLimited
                && !result.cancelled
            if boardIsFinished {
                index += 1
            }

            slice.boardsSwept += 1
            slice.postingsSeen += result.found
            slice.postingsPassed += result.passed
            slice.postingsIngested += result.ingested
            budget -= result.ingested

            // After the counters, so the work this board *did* do is still recorded and its
            // ingests still charged against the budget before the slice ends.
            if result.cancelled {
                slice.stopReason = "stopped part-way through — will resume here"
                break
            }

            switch result.status {
            case .unreachable, .rateLimited, .misconfigured:
                slice.boardsUnreachable += 1
            default:
                break
            }

            // A rate limit is the one signal worth stopping the whole slice for. Pushing on would
            // turn a temporary refusal into thousands of boards recorded as unreachable, and every
            // match on them lost — the precise failure career-ops measured. The cursor stays put,
            // so the next slice picks up exactly here.
            if result.status == .rateLimited {
                slice.stopReason = "\(source.displayName) is rate limiting — pausing until the next slice"
                break
            }
            if result.truncatedByCap > 0 {
                slice.stopReason = "\(result.truncatedByCap) more matches on this board than today's "
                    + "limit allows — it will be finished on the next run"
                break
            }
            if budget <= 0 {
                slice.stopReason = "daily new-job limit reached — resumes tomorrow"
                break
            }

            let pacing = MarketPacing.forKind(board.kind)
            try? await Task.sleep(for: .milliseconds(pacing.delayMilliseconds))
        }
        return (slice, index)
    }

    // MARK: - Checkpointing

    /// A pass, and the exact list it is walking.
    public struct ActivePass: Sendable {
        public let sweepID: String
        public let cursor: Int
        public let boards: [MarketBoard]
        public let revision: String
    }

    /// The pass to work on, or nil when nothing is due.
    ///
    /// Rebuilds the ordered list from the *persisted* priority set so a resume walks the identical
    /// list, and refuses to reuse a cursor whose `directoryRevision` no longer matches — a stale
    /// index against a changed directory re-reads some boards and skips others with no error
    /// anywhere, which is the worst kind of failure this feature can have.
    public func passForRun(
        boards: [MarketBoard], startHour: Int, priority: Set<String>, now: Date = Date()
    ) async -> ActivePass? {
        // A read that FAILS is not a store with no state in it. Conflating them let a transient
        // error delete an unfinished checkpoint and restart the pass from board zero — repeatedly,
        // if the error repeated, so the tail of the directory would never be reached.
        let existing: MarketSweepState?
        do {
            existing = try await store.marketSweepState()
        } catch {
            return nil
        }

        if let existing {
            // Cheapest question first. Ordering ~29,000 boards and hashing the result is the most
            // expensive thing in this function, and the loop asks every three minutes — 480 times a
            // day, almost always to be told the finished pass isn't due yet.
            if existing.isFinished {
                guard existing.isDue(startHour: startHour, now: now) else { return nil }
                return await startPass(boards: boards, priority: priority, now: now)
            }

            let resumed = MarketBoardOrder.ordered(boards, priority: existing.priority)
            let revision = MarketBoardOrder.revision(resumed)
            // Nil means the row predates the revision field, so the cursor's list is unknown and
            // cannot be trusted — same conclusion as a mismatch. The directory changed under an
            // unfinished pass: restarting loses progress, continuing loses *boards*, silently.
            // Progress is the cheaper thing to lose.
            guard existing.directoryRevision == revision else {
                return await startPass(boards: boards, priority: priority, now: now)
            }
            return ActivePass(
                sweepID: existing.sweepID, cursor: existing.cursor,
                boards: resumed, revision: revision
            )
        }
        return await startPass(boards: boards, priority: priority, now: now)
    }

    private func startPass(
        boards: [MarketBoard], priority: Set<String>, now: Date
    ) async -> ActivePass? {
        let ordered = MarketBoardOrder.ordered(boards, priority: priority)
        let revision = MarketBoardOrder.revision(ordered)
        guard let state = try? await store.startMarketSweep(
            boardCount: ordered.count, directoryRevision: revision, priority: priority, now: now
        ) else { return nil }
        return ActivePass(sweepID: state.sweepID, cursor: 0, boards: ordered, revision: revision)
    }
}

public extension BackgroundStore {
    func marketSweepState() throws -> MarketSweepState? {
        try modelContext.fetch(FetchDescriptor<MarketSweepState>()).first
    }

    /// Begin a pass, replacing any previous one. The row is reused rather than accumulated: history
    /// belongs in the ledger, which records findings; this only tracks position.
    @discardableResult
    func startMarketSweep(
        boardCount: Int, directoryRevision: String, priority: Set<String>, now: Date = Date()
    ) throws -> MarketSweepState {
        for old in try modelContext.fetch(FetchDescriptor<MarketSweepState>()) {
            modelContext.delete(old)
        }
        let state = MarketSweepState(
            startedAt: now, boardCount: boardCount,
            directoryRevision: directoryRevision, priority: priority
        )
        modelContext.insert(state)
        try modelContext.save()
        return state
    }

    /// Persist progress, but only onto the pass it belongs to.
    ///
    /// `sweepID` and `directoryRevision` are checked because the read-sweep-record sequence is not
    /// atomic: a pass can be restarted between a slice starting and finishing, and recording the
    /// old slice's counts and cursor onto the new pass would corrupt both its position and its
    /// totals.
    func recordMarketSweepSlice(
        _ slice: MarketSweepSlice,
        nextCursor: Int,
        sweepID: String,
        directoryRevision: String,
        boardCount: Int,
        now: Date = Date()
    ) throws {
        guard let state = try marketSweepState(),
              state.sweepID == sweepID,
              state.directoryRevision == directoryRevision
        else { return }

        state.cursor = nextCursor
        // Against the CURRENT list length, not the one stored when the pass began: a directory that
        // grew would otherwise finish early and drop the new boards, and one that shrank would stall
        // forever at a cursor it can never reach.
        state.boardCount = boardCount
        state.boardsSwept += slice.boardsSwept
        state.boardsUnreachable += slice.boardsUnreachable
        state.postingsSeen += slice.postingsSeen
        state.postingsPassed += slice.postingsPassed
        state.postingsIngested += slice.postingsIngested
        state.pauseReason = slice.stopReason
        state.updatedAt = now
        if nextCursor >= boardCount, boardCount > 0 {
            state.finishedAt = now
            state.pauseReason = nil
        }
        try modelContext.save()
    }
}
