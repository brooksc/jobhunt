import Foundation

/// What one sweep of one source did. Everything here reaches the UI — a sweep that says only
/// "0 new" is indistinguishable from a broken one.
public struct SweepResult: Sendable, Equatable {
    public var status: SearchSourceStatus
    /// Rows the board listed.
    public var found: Int
    /// Rows that cleared gate A *and* weren't already in the ledger.
    public var passed: Int
    /// Rows that got a body and reached `ingestCapture`.
    public var ingested: Int
    /// Cleared the gate but couldn't be given a body. Retried next sweep.
    public var hydrationFailures: Int
    /// Cleared the gate but hit a cap. **Must be surfaced** — a silent cap reads as
    /// "nothing more was found".
    public var truncatedByCap: Int
    public var rejections: [DiscoveryRejectReason: Int]
    public var error: String?

    /// Postings this visit settled *permanently* — written to the ledger with a verdict that is
    /// never revisited (ingested, or already in the library). Zero means the next visit will do
    /// exactly this visit's work again.
    ///
    /// Separate from `ingested` because the market sweep's anti-pin rule needs "did this board
    /// move forward", not "did it produce a job". A capped batch can settle fifty postings the user
    /// already had and create nothing; treating that as no progress abandons the board's remaining
    /// matches until the next full 29,000-board pass, by which time short-lived postings are gone.
    public var settled: Int

    /// The sweep stopped because the task was cancelled — app quitting, restore, settings change —
    /// rather than because the board ran out. The board is unfinished regardless of what the other
    /// counters say, and must not be treated as done.
    public var cancelled: Bool

    public init(
        status: SearchSourceStatus, found: Int = 0, passed: Int = 0, ingested: Int = 0,
        hydrationFailures: Int = 0, truncatedByCap: Int = 0,
        rejections: [DiscoveryRejectReason: Int] = [:], error: String? = nil,
        settled: Int = 0, cancelled: Bool = false
    ) {
        self.status = status
        self.found = found
        self.passed = passed
        self.ingested = ingested
        self.hydrationFailures = hydrationFailures
        self.truncatedByCap = truncatedByCap
        self.rejections = rejections
        self.error = error
        self.settled = settled
        self.cancelled = cancelled
    }
}

/// Ceilings on how much one sweep may spend.
///
/// A circuit breaker, not a budget. Measured against career-ops' own history the real yield is
/// about two postings a day, so these numbers are two orders of magnitude above what a working
/// configuration produces. They exist for the case where they are the only thing standing between a
/// misconfiguration and 15,000 extractions overnight — an empty `titleIncludeAny` does exactly that.
public struct DiscoveryCaps: Sendable, Equatable {
    public var perSweep: Int
    public var perDay: Int

    public init(perSweep: Int = 50, perDay: Int = 200) {
        self.perSweep = perSweep
        self.perDay = perDay
    }

    public static let `default` = DiscoveryCaps()
}

/// Runs one source end to end: fetch → gate → ledger → hydrate → ingest (TASK-692, M3).
///
/// The order is the whole design. Everything expensive happens as late as possible and to as few
/// rows as possible: the gate is free and runs on all 15,000, the ledger lookup is one query and
/// removes everything already judged, and only what survives both — bounded by the cap — costs a
/// network request and an LLM call.
///
/// Nothing here mutates an existing job. Discovery only ever creates, through the same
/// `ingestCapture` a browser capture uses, unchanged.
public struct DiscoverySweeper: Sendable {
    let store: BackgroundStore
    let jobService: JobService
    let session: URLSession
    let caps: DiscoveryCaps
    let ledgerRejections: Bool

    /// - Parameter ledgerRejections: whether a posting the gate turned down is written to the
    ///   ledger. True for a watched company, where a board is a few hundred rows and recording the
    ///   verdict makes the histogram possible. **False for a market sweep**, which sees on the order
    ///   of a million postings per pass — a row each would grow the ledger without bound to save
    ///   re-running a filter that costs microseconds and touches nothing. Passes and hydration
    ///   failures are always recorded, because those are the ones that must not be repeated.
    public init(
        store: BackgroundStore,
        jobService: JobService,
        session: URLSession = .shared,
        caps: DiscoveryCaps = .default,
        ledgerRejections: Bool = true
    ) {
        self.store = store
        self.jobService = jobService
        self.session = session
        self.caps = caps
        self.ledgerRejections = ledgerRejections
    }

    /// Sweep one source.
    ///
    /// - Parameter remainingDailyBudget: how many ingests are still allowed today across all
    ///   sources. Passed in rather than read here so the scheduler owns the day boundary and one
    ///   greedy source can't exhaust the rest.
    /// - Parameter alreadyCaptured: dedup keys the store already holds, used to skip the hydration
    ///   request for postings the user already has.
    ///
    ///   **Purely an optimisation.** The guarantee that discovery never modifies an existing job
    ///   lives in the store, inside the same transaction as the existence check (`createOnly`),
    ///   because a caller-side snapshot goes stale during network work, fails open when the read
    ///   throws, and can simply be forgotten by a caller — all three of which happened here before
    ///   the invariant was moved.
    public func sweep(
        source: any JobSource,
        config: SourceConfig,
        criteria: DiscoveryCriteria,
        since: Date? = nil,
        remainingDailyBudget: Int = Int.max,
        alreadyCaptured: Set<String> = [],
        now: Date = Date()
    ) async -> SweepResult {
        let fingerprint = criteria.fingerprint

        // 1. Fetch. A board that answers with nothing is a success with zero rows — see SourceError.
        let postings: [DiscoveredPosting]
        do {
            postings = try await source.fetchRecent(config: config, since: since, session: session)
        } catch let error as SourceError {
            return SweepResult(status: status(for: error), error: message(for: error))
        } catch {
            return SweepResult(status: .unreachable, error: "the board didn't answer")
        }
        guard !postings.isEmpty else { return SweepResult(status: .empty) }

        // Exactly one sweep's raw rows are retained per source, for the settings preview. Cleared
        // before recording rather than after, so a sweep that crashes leaves the older set rather
        // than nothing. Skipped for a market sweep, which shares one source id across thousands of
        // boards — clearing per board would erase the previous board's rows, and keeping them all
        // would retain the whole market.
        if ledgerRejections {
            do {
                try await store.clearRetainedRawRows(sourceID: source.id)
            } catch {
                // Best-effort: the preview keeps the older sweep's rows, which is the documented
                // failure mode above. Still a store error, so it doesn't vanish.
                NSLog("DiscoverySweeper: clearRetainedRawRows(\(source.id)) failed: \(error)")
            }
        }

        // 2. Gate A — free, and runs on everything.
        let gated = applyGate(postings, criteria: criteria, now: now)
        var rejections = gated.rejections
        var outcomes = gated.outcomes
        let survivors = gated.survivors

        // 3. Ledger — drop everything already judged under these criteria. This is what makes the
        // second sweep of an unchanged board cost nothing.
        // Fails CLOSED. Treating a ledger read error as "nothing has been judged yet" would let
        // already-handled postings consume the day's allowance — crowding out genuinely new ones
        // later in the board — and would recreate discoveries the user had deleted. A board we
        // can't reason about is a board we skip, and the cursor doesn't advance past it.
        var unjudged: [DiscoveredPosting]
        do {
            unjudged = try await store.unjudgedPostings(survivors, criteriaFingerprint: fingerprint)
        } catch {
            return SweepResult(
                status: .unreachable, found: postings.count, passed: survivors.count,
                rejections: rejections, error: "couldn't read what has already been seen"
            )
        }

        // …and drop anything the user already has, whatever route it arrived by. Discovery only
        // ever creates; it must not reach into a job that already exists.
        if !alreadyCaptured.isEmpty {
            let known = unjudged.filter { alreadyCaptured.contains($0.dedupKey) }
            unjudged.removeAll { alreadyCaptured.contains($0.dedupKey) }
            // Ledgered so the next pass skips them without re-deriving the capture set.
            outcomes.append(contentsOf: known.map { ($0, DiscoveryOutcome.alreadyCaptured, nil) })
        }

        // 4. Caps, applied here so they bound hydration requests and not just ingests.
        let allowance = max(0, min(caps.perSweep, remainingDailyBudget))
        let toIngest = Array(unjudged.prefix(allowance))
        let truncated = unjudged.count - toIngest.count

        // 5. Hydrate, apply gate B to the body, and ingest what survives.
        let run = await hydrateAndIngest(toIngest, source: source, criteria: criteria, now: now)
        outcomes.append(contentsOf: run.outcomes)
        let ingested = run.ingested
        let hydrationFailures = run.hydrationFailures
        let unprocessed = run.unprocessed
        rejections.merge(run.rejections) { $0 + $1 }

        // A ledger row that never landed will be re-derived next visit, so it isn't progress. A
        // *job* that landed is progress whatever the ledger did: each ingest commits its own
        // Job/Capture in its own transaction, before this batch write, and those rows are already
        // in `capturedDedupKeys` — the next visit sees them as alreadyCaptured and does less work.
        //
        // Conflating the two meant a ledger failure after twenty successful ingests reported zero
        // progress, which MarketSweeper reads as a stall and answers by abandoning the rest of the
        // board for the whole pass.
        var settled = ingested
        do {
            try await store.recordDiscoveryOutcomes(
                outcomes.map { (posting: $0.0, outcome: $0.1, reason: $0.2) },
                criteriaFingerprint: fingerprint,
                now: now
            )
            settled = outcomes.count { $0.1 == .ingested || $0.1 == .alreadyCaptured }
        } catch {
            // `ingested` alone stands.
        }

        return SweepResult(
            status: .ok,
            found: postings.count,
            passed: survivors.count,
            ingested: ingested,
            hydrationFailures: hydrationFailures,
            truncatedByCap: truncated + unprocessed,
            rejections: rejections,
            settled: settled,
            cancelled: unprocessed > 0
        )
    }

    /// Hydrate and ingest a bounded batch, one posting at a time.
    ///
    /// Sequential on purpose: a burst of parallel requests to one board is what rate limiting is
    /// for, and there are at most `caps.perSweep` of them.
    private func hydrateAndIngest(
        _ toIngest: [DiscoveredPosting], source: any JobSource, criteria: DiscoveryCriteria, now: Date
    ) async -> (
        outcomes: [(DiscoveredPosting, DiscoveryOutcome, DiscoveryRejectReason?)],
        ingested: Int,
        hydrationFailures: Int,
        rejections: [DiscoveryRejectReason: Int],
        unprocessed: Int
    ) {
        var outcomes: [(DiscoveredPosting, DiscoveryOutcome, DiscoveryRejectReason?)] = []
        var ingested = 0
        var hydrationFailures = 0
        var rejections: [DiscoveryRejectReason: Int] = [:]

        for (index, posting) in toIngest.enumerated() {
            if Task.isCancelled {
                // Postings already admitted to this batch that were never looked at. They are not
                // truncated by the cap and carry no ledger verdict, so without counting them a
                // cancelled board is indistinguishable from a finished one and the market cursor
                // moves past it — losing the rest of the board until the next full pass.
                return (outcomes, ingested, hydrationFailures, rejections, toIngest.count - index)
            }
            guard let body = await hydrate(posting) else {
                outcomes.append((posting, .hydrationFailed, nil))
                hydrationFailures += 1
                continue
            }
            // Gate B. The body is the first place a salary band exists — no board list endpoint
            // publishes one — so the floor is applied here, before the extraction and fit score that
            // are what a posting actually costs.
            //
            // Always ledgered, even for a market sweep where gate-A rejections aren't: this verdict
            // cost a network request, and not recording it would pay for the same fetch on every
            // pass, forever.
            if case let .reject(reason) = criteria.evaluateHydrated(body: body) {
                outcomes.append((posting, .rejected, reason))
                rejections[reason, default: 0] += 1
                continue
            }
            switch await ingest(
                posting, body: body, sourceName: source.displayName, sourceID: source.id, now: now
            ) {
            case .created:
                outcomes.append((posting, .ingested, nil))
                ingested += 1
            case .alreadyExisted:
                // The store refused to touch it, which is the guarantee working. Not a find.
                outcomes.append((posting, .alreadyCaptured, nil))
            case .refused:
                // Deterministic: a URL-policy rejection, or a content duplicate resolved inside
                // ingestCapture. Retrying would refuse it identically, so record it.
                outcomes.append((posting, .alreadyCaptured, nil))
            case .failed:
                // Operational. Deliberately NOT recorded — a terminal verdict on a transient store
                // error would suppress a real posting forever.
                hydrationFailures += 1
            }
        }
        return (outcomes, ingested, hydrationFailures, rejections, 0)
    }

    /// Gate A over a board's postings. Split out for size, and because it is the one part of a
    /// sweep with no I/O in it at all.
    func applyGate(
        _ postings: [DiscoveredPosting], criteria: DiscoveryCriteria, now: Date
    ) -> (
        survivors: [DiscoveredPosting],
        rejections: [DiscoveryRejectReason: Int],
        outcomes: [(DiscoveredPosting, DiscoveryOutcome, DiscoveryRejectReason?)]
    ) {
        var rejections: [DiscoveryRejectReason: Int] = [:]
        var outcomes: [(DiscoveredPosting, DiscoveryOutcome, DiscoveryRejectReason?)] = []
        var survivors: [DiscoveredPosting] = []
        for posting in postings {
            switch criteria.evaluate(posting, now: now) {
            case .pass:
                survivors.append(posting)
            case let .reject(reason):
                rejections[reason, default: 0] += 1
                if ledgerRejections {
                    outcomes.append((posting, .rejected, reason))
                }
            }
        }
        return (survivors, rejections, outcomes)
    }

    // MARK: - Hydration

    /// The body a posting needs before it can be ingested.
    ///
    /// `ingestCapture` requires text and nothing downstream fetches a URL to get it — a browser
    /// capture arrives with the body attached. Greenhouse's and Workday's list endpoints publish no
    /// description, so this is where the body comes from, and it runs only on rows that already
    /// cleared the gate and the ledger and the cap.
    ///
    /// Returns nil rather than a stub. A job whose description is its own title would be extracted
    /// into nonsense and then fit-scored against the nonsense, which is worse than not having the
    /// row at all.
    func hydrate(_ posting: DiscoveredPosting) async -> String? {
        if let body = posting.descriptionPlain, !body.isEmpty {
            return body
        }
        guard let atsID = DuplicateDetector.atsPostingID(urlString: posting.url),
              let provider = ATSRegistry.provider(forATSID: atsID) else { return nil }
        let fetched = await provider.fetchPosting(
            atsID: atsID, company: posting.company, urlString: posting.url, session: session
        )
        guard let content = fetched?.contentPlain, !content.isEmpty else { return nil }
        return content
    }

    // MARK: - Ingest

    /// Why an ingest didn't produce a job.
    ///
    /// `refused` is deterministic — a URL-policy rejection, a content duplicate — so it is terminal
    /// and gets ledgered. `failed` is operational, so it is NOT ledgered: writing it down would let
    /// one transient store hiccup suppress a posting permanently.
    enum IngestOutcome { case created, alreadyExisted, refused, failed }

    /// Hands the posting to the same entry point the browser extension uses, with `createOnly` set.
    /// One ingest path, on purpose: a second would drift from the first, and everything downstream —
    /// cleaning, hashing, duplicate detection, the extraction queue — already works. The only
    /// difference is that discovery is forbidden from modifying what it finds.
    func ingest(
        _ posting: DiscoveredPosting, body: String, sourceName: String, sourceID: String, now: Date
    ) async -> IngestOutcome {
        let stamp = DateFormatter.discoveryNote.string(from: now)
        let payload = CapturePayload(
            url: posting.url,
            pageTitle: posting.title,
            selectedText: nil,
            visibleText: body,
            // Provenance the user can read. The alternative — a `discovered` status — would touch
            // every status-handling site in the app for something a note conveys.
            userNote: "Found automatically via \(sourceName) on \(stamp)",
            canonicalURL: nil,
            structuredDataJSON: nil,
            // The note is user-facing copy; this is the fact. Counting discoveries by parsing the
            // note would lose finds the user edited and miscount notes that merely start the same.
            discoveredBySourceID: sourceID
        )
        do {
            let result = try await jobService.ingestCapture(payload, createOnly: true)
            if result.alreadyExisted || result.isDuplicate {
                return .alreadyExisted
            }
            return .created
        } catch is JobServiceError {
            // The payload itself is unacceptable — a bad URL, no text. Deterministic.
            return .refused
        } catch {
            return .failed
        }
    }

    // MARK: - Failure mapping

    func status(for error: SourceError) -> SearchSourceStatus {
        switch error {
        case .misconfigured: .misconfigured
        case .unreachable: .unreachable
        case .malformedResponse: .unreachable
        }
    }

    func message(for error: SourceError) -> String {
        switch error {
        case let .misconfigured(detail), let .unreachable(detail), let .malformedResponse(detail):
            detail
        }
    }
}

extension DateFormatter {
    static let discoveryNote: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
