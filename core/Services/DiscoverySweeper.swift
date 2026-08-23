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

    public init(
        status: SearchSourceStatus, found: Int = 0, passed: Int = 0, ingested: Int = 0,
        hydrationFailures: Int = 0, truncatedByCap: Int = 0,
        rejections: [DiscoveryRejectReason: Int] = [:], error: String? = nil
    ) {
        self.status = status
        self.found = found
        self.passed = passed
        self.ingested = ingested
        self.hydrationFailures = hydrationFailures
        self.truncatedByCap = truncatedByCap
        self.rejections = rejections
        self.error = error
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
    public func sweep(
        source: any JobSource,
        config: SourceConfig,
        criteria: DiscoveryCriteria,
        since: Date? = nil,
        remainingDailyBudget: Int = Int.max,
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
            try? await store.clearRetainedRawRows(sourceID: source.id)
        }

        // 2. Gate A — free, and runs on everything.
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

        // 3. Ledger — drop everything already judged under these criteria. This is what makes the
        // second sweep of an unchanged board cost nothing.
        let unjudged = await (try? store.unjudgedPostings(survivors, criteriaFingerprint: fingerprint))
            ?? survivors

        // 4. Caps, applied here so they bound hydration requests and not just ingests.
        let allowance = max(0, min(caps.perSweep, remainingDailyBudget))
        let toIngest = Array(unjudged.prefix(allowance))
        let truncated = unjudged.count - toIngest.count

        // 5. Hydrate and ingest, one at a time. A burst of parallel requests to one board is what
        // rate limiting is for, and there are at most `allowance` of them.
        var ingested = 0
        var hydrationFailures = 0
        for posting in toIngest {
            if Task.isCancelled {
                break
            }
            if let body = await hydrate(posting) {
                if await ingest(posting, body: body, sourceName: source.displayName, now: now) {
                    outcomes.append((posting, .ingested, nil))
                    ingested += 1
                } else {
                    // Ingest refused it — a URL policy rejection, or a duplicate resolved inside
                    // ingestCapture. Ledger it as done either way: retrying next sweep would refuse
                    // it identically, forever.
                    outcomes.append((posting, .ingested, nil))
                }
            } else {
                outcomes.append((posting, .hydrationFailed, nil))
                hydrationFailures += 1
            }
        }

        try? await store.recordDiscoveryOutcomes(
            outcomes.map { (posting: $0.0, outcome: $0.1, reason: $0.2) },
            criteriaFingerprint: fingerprint,
            now: now
        )

        return SweepResult(
            status: .ok,
            found: postings.count,
            passed: survivors.count,
            ingested: ingested,
            hydrationFailures: hydrationFailures,
            truncatedByCap: truncated,
            rejections: rejections
        )
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

    /// Hands the posting to the same entry point the browser extension uses. Unchanged, on purpose:
    /// a second ingest path would drift from the first, and everything downstream — cleaning,
    /// hashing, duplicate detection, the extraction queue — already works.
    func ingest(
        _ posting: DiscoveredPosting, body: String, sourceName: String, now: Date
    ) async -> Bool {
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
            structuredDataJSON: nil
        )
        return await (try? jobService.ingestCapture(payload)) != nil
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
