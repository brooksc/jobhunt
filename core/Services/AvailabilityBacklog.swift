import Foundation

/// The jobs a check couldn't answer for, so a background pass can finish the job.
///
/// A single sweep deliberately doesn't answer everything. LinkedIn is checked twelve per run because
/// it throttles bursts, and a throttled or unreachable ATS board yields "don't know" rather than a
/// verdict. Both are correct in isolation, and both leave postings whose state is simply unknown —
/// which is the opposite of what the check is for. Time spent on a role that closed weeks ago is the
/// cost this is trying to avoid.
///
/// So a run seeds a backlog, a background pass drains it a batch at a time at the same gentle pace,
/// and when there is nothing left to ask the user is told once, with everything that turned out to
/// be gone.
///
/// **Session-scoped.** Nothing here is persisted: the app records no per-job check history at all
/// (TASK-674), so a relaunch starts over. That's honest rather than ideal — a drain that survived
/// relaunch would need to know which jobs are still owed an answer, which is exactly what isn't
/// stored yet.
public struct AvailabilityBacklog: Sendable {
    /// Jobs still owed an answer, in the order they were deferred.
    public private(set) var pendingJobIDs: [String] = []
    /// Everything found gone across every pass of this drain, deduplicated by job.
    public private(set) var gone: [GoneJobResult] = []
    /// True once a drain has produced at least one result to report — so a drain that finishes having
    /// found nothing stays silent instead of posting "0 jobs may be gone".
    public var hasFindings: Bool {
        !gone.isEmpty
    }

    public var isDrained: Bool {
        pendingJobIDs.isEmpty
    }

    /// How many postings one background pass re-asks about.
    ///
    /// Matched to the checker's own LinkedIn cap: these are the postings whose hosts objected to being
    /// asked quickly, so a bigger batch would reproduce the throttling that deferred them.
    public static let batchSize = 12

    public init() {}

    /// Reasons worth asking about again.
    ///
    /// `notCheckedThisRun` is the LinkedIn rotation: nothing was wrong, the posting simply wasn't due.
    /// `rateLimited` and `unreachable` are transient by definition. The others are excluded on purpose:
    /// a bot-challenge page and a client-rendered shell will answer exactly the same way in twenty
    /// minutes, so retrying them is pure noise against someone else's rate limit — and `noURL` cannot
    /// be checked at all, ever.
    public static let retryableReasons: Set<UnverifiedReason> = [
        .notCheckedThisRun, .rateLimited, .unreachable
    ]

    /// Fold a sweep's outcome in: its findings accumulate, and the jobs it covered leave the pending
    /// set unless it still couldn't answer for them.
    ///
    /// - Parameter covering: the jobs this sweep was actually given. Defaults to everything it reached
    ///   a conclusion about.
    ///
    /// This used to REPLACE the pending set outright, on the reasoning that a pass re-asks about the
    /// jobs it was given. That holds only when the pass is given ALL of them — and the background
    /// drain deliberately isn't: it takes a batch of twelve, because the postings in the backlog are
    /// exactly the ones whose hosts objected to being asked quickly. So a drain over 58 deferred
    /// postings checked twelve, discarded the other 46 untouched, and reported itself finished. Only
    /// the covered jobs may leave.
    public mutating func absorb(_ sweep: AvailabilitySweep, covering: [String]? = nil) {
        var seen = Set(gone.map(\.jobID))
        for result in sweep.gone where seen.insert(result.jobID).inserted {
            gone.append(result)
        }

        let covered = Set(covering ?? sweep.outcomes.map(\.jobID))
        let stillPending = sweep.unverified
            .filter { Self.retryableReasons.contains($0.reason) }
            .map(\.jobID)
        let stillPendingSet = Set(stillPending)

        // Keep the order stable so the drain works through the backlog front-to-back rather than
        // re-rolling which twelve it looks at.
        var next = pendingJobIDs.filter { !covered.contains($0) || stillPendingSet.contains($0) }
        let known = Set(next)
        next.append(contentsOf: stillPending.filter { !known.contains($0) })
        pendingJobIDs = next
    }

    /// The next slice to check. Batches are small on purpose: the point is to be gentler than a sweep,
    /// not to retry the same burst that got throttled.
    public func nextBatch(limit: Int) -> [String] {
        Array(pendingJobIDs.prefix(max(1, limit)))
    }

    /// Clears the findings once they've been shown, so the next drain reports only what it finds.
    public mutating func clearFindings() {
        gone = []
    }
}
