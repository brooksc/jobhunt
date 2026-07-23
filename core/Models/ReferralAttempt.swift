import Foundation
import SwiftData

/// One referral-outreach request for a job (TASK-630/644). Referral progress is orthogonal to
/// `JobStatus`, so it lives in its own model keyed by `jobID` (no relationship — the frozen `Job` is
/// untouched; in `SchemaV1.models`, a non-breaking change). A job can hold many requests (parallel
/// recipients). A special `not_pursuing` marker (no recipient) records the job-level "N/A — no referral
/// possible" decision.
///
/// A request moves through `requested` → `responded` → `submitted` (or `declined`); each state stamps
/// its own optional date so the dashboard can nudge stale requests. The extra dates are optional, so
/// adding them is a lightweight SwiftData migration over existing TASK-630 rows.
@Model
public final class ReferralAttempt {
    @Attribute(.unique) public var id: String
    public var jobID: String
    public var recipientName: String
    /// A stable contact identifier — LinkedIn profile URL, email, etc. — used for duplicate detection.
    public var recipientIdentifier: String?
    public var channel: String?
    public var note: String?
    /// When the referral was requested (the ask date) — always set; anchors follow-up nudges.
    public var requestedAt: Date
    /// When the recipient responded/agreed (nil until reached).
    public var respondedAt: Date?
    /// When the referral was confirmed submitted (nil until reached).
    public var submittedAt: Date?
    /// When the recipient declined (nil unless declined).
    public var declinedAt: Date?
    /// One of `ReferralOutcome` raw values: requested / responded / referred(=submitted) / declined /
    /// not_pursuing(=N/A).
    public var outcome: String

    public init(
        id: String = UUID().uuidString, jobID: String, recipientName: String,
        recipientIdentifier: String? = nil, channel: String? = nil, note: String? = nil,
        requestedAt: Date = Date(), respondedAt: Date? = nil, submittedAt: Date? = nil,
        declinedAt: Date? = nil, outcome: String
    ) {
        self.id = id
        self.jobID = jobID
        self.recipientName = recipientName
        self.recipientIdentifier = recipientIdentifier
        self.channel = channel
        self.note = note
        self.requestedAt = requestedAt
        self.respondedAt = respondedAt
        self.submittedAt = submittedAt
        self.declinedAt = declinedAt
        self.outcome = outcome
    }
}

/// Sendable payload for recording/editing a referral attempt across the store actor (TASK-630).
public struct ReferralAttemptInput: Sendable {
    public let id: String?
    public let jobID: String
    public let recipientName: String
    public let recipientIdentifier: String?
    public let channel: String?
    public let note: String?
    public let requestedAt: Date
    public let respondedAt: Date?
    public let submittedAt: Date?
    public let declinedAt: Date?
    public let outcome: String

    public init(
        id: String? = nil, jobID: String, recipientName: String, recipientIdentifier: String? = nil,
        channel: String? = nil, note: String? = nil, requestedAt: Date = Date(), respondedAt: Date? = nil,
        submittedAt: Date? = nil, declinedAt: Date? = nil, outcome: String
    ) {
        self.id = id
        self.jobID = jobID
        self.recipientName = recipientName
        self.recipientIdentifier = recipientIdentifier
        self.channel = channel
        self.note = note
        self.requestedAt = requestedAt
        self.respondedAt = respondedAt
        self.submittedAt = submittedAt
        self.declinedAt = declinedAt
        self.outcome = outcome
    }
}
