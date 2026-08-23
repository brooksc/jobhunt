import Foundation
import SwiftData

/// What happened to one swept posting.
public enum DiscoveryOutcome: String, Sendable, Equatable, CaseIterable {
    /// Cleared gate A and was handed to hydration + ingest.
    case ingested
    /// Cleared gate A but couldn't be given a body, so it was never ingested. Distinct from a
    /// rejection: the criteria liked it, the network didn't cooperate, and it should be retried.
    case hydrationFailed
    /// Rejected by gate A. The specific reason is in `rejectReasonRaw`.
    case rejected
}

/// Every posting a sweep has already judged (TASK-691, M2).
///
/// Without this, each sweep re-ingests the whole board. `DuplicateDetector` already stops duplicate
/// *jobs*, but it runs inside `ingestCapture` — after hydration has spent a request and after the
/// row has been through validation and hashing. At real board sizes that's thousands of wasted
/// round trips an hour.
///
/// **Rejections are recorded, not just passes.** Recording only what was ingested would mean
/// re-evaluating the same ~5,900 rejects on every sweep. That's cheap in CPU but it defeats the
/// second purpose: `criteriaFingerprint` records *which* criteria produced the verdict, so widening
/// the criteria correctly re-examines everything judged under the old ones. Without the fingerprint
/// a user who adds a keyword would never see the rows the old keywords discarded.
///
/// Deliberately outside the "don't optimise for scale this app won't reach" convention that governs
/// the rest of jobhunt. A few hundred jobs is the app's scale; a single Workday tenant is 3,000 rows
/// in one response, and career-ops has swept tenants of 23,000.
@Model
public final class DiscoveryLedgerEntry {
    /// `DiscoveredPosting.dedupKey` — an ATS posting id where the URL yields one, else a normalised
    /// URL. Unique, because seeing the same posting twice is the entire point of the table.
    @Attribute(.unique) public var dedupKey: String
    public var sourceID: String
    public var outcomeRaw: String
    /// Set only when `outcomeRaw == rejected`.
    public var rejectReasonRaw: String?
    /// `DiscoveryCriteria.fingerprint` at the time of the verdict — a stable SHA, not `hashValue`,
    /// which Swift re-seeds every launch.
    public var criteriaFingerprint: String
    public var firstSeenAt: Date
    public var lastSeenAt: Date
    /// The raw row as JSON, retained only for the most recent sweep of its source so the settings
    /// screen can replay gate A over real data ("these criteria would have passed 41 of 6,168").
    /// Cleared once superseded — the keys are worth keeping forever, the payloads are not.
    public var rawJSON: String?

    public init(
        dedupKey: String,
        sourceID: String,
        outcome: DiscoveryOutcome,
        rejectReason: DiscoveryRejectReason? = nil,
        criteriaFingerprint: String,
        firstSeenAt: Date = Date(),
        lastSeenAt: Date = Date(),
        rawJSON: String? = nil
    ) {
        self.dedupKey = dedupKey
        self.sourceID = sourceID
        outcomeRaw = outcome.rawValue
        rejectReasonRaw = rejectReason?.rawValue
        self.criteriaFingerprint = criteriaFingerprint
        self.firstSeenAt = firstSeenAt
        self.lastSeenAt = lastSeenAt
        self.rawJSON = rawJSON
    }

    public var outcome: DiscoveryOutcome {
        DiscoveryOutcome(rawValue: outcomeRaw) ?? .rejected
    }

    public var rejectReason: DiscoveryRejectReason? {
        rejectReasonRaw.flatMap(DiscoveryRejectReason.init(rawValue:))
    }

    /// Whether this posting still needs judging under the criteria now in force.
    ///
    /// An already-ingested posting is done forever — re-ingesting it because the criteria widened
    /// would resurrect jobs the user has since archived. Everything else is re-examined when the
    /// criteria change, and a hydration failure is retried even when they haven't, because that
    /// failure was the network's fault rather than the posting's.
    public func needsReevaluation(under fingerprint: String) -> Bool {
        switch outcome {
        case .ingested: false
        case .hydrationFailed: true
        case .rejected: criteriaFingerprint != fingerprint
        }
    }
}
