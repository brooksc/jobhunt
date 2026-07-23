import Foundation
import SwiftData

/// One referral-outreach attempt for a job (TASK-630). Referral progress is orthogonal to `JobStatus`,
/// so it lives in its own model keyed by `jobID` (no relationship — the frozen `Job` is untouched; added
/// to `SchemaV1.models`, a non-breaking change). A job can hold many attempts (multiple recipients).
/// A special `not_pursuing` marker (no recipient) records the per-job "not pursuing a referral" decision.
@Model
public final class ReferralAttempt {
    @Attribute(.unique) public var id: String
    public var jobID: String
    public var recipientName: String
    /// A stable contact identifier — LinkedIn profile URL, email, etc. — used for duplicate detection.
    public var recipientIdentifier: String?
    public var channel: String?
    public var note: String?
    public var requestedAt: Date
    /// One of `ReferralOutcome` raw values: requested / referred / declined / not_pursuing.
    public var outcome: String

    public init(
        id: String = UUID().uuidString, jobID: String, recipientName: String,
        recipientIdentifier: String? = nil, channel: String? = nil, note: String? = nil,
        requestedAt: Date = Date(), outcome: String
    ) {
        self.id = id
        self.jobID = jobID
        self.recipientName = recipientName
        self.recipientIdentifier = recipientIdentifier
        self.channel = channel
        self.note = note
        self.requestedAt = requestedAt
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
    public let outcome: String

    public init(
        id: String? = nil, jobID: String, recipientName: String, recipientIdentifier: String? = nil,
        channel: String? = nil, note: String? = nil, requestedAt: Date = Date(), outcome: String
    ) {
        self.id = id
        self.jobID = jobID
        self.recipientName = recipientName
        self.recipientIdentifier = recipientIdentifier
        self.channel = channel
        self.note = note
        self.requestedAt = requestedAt
        self.outcome = outcome
    }
}
