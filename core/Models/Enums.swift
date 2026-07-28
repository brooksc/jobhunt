import Foundation

// Raw values must match legacy SQLite string values exactly for CSV/MCP/extension parity.

public enum JobStatus: String, Codable, CaseIterable, Sendable {
    case new
    case pursuing
    case applied
    case interview
    case offer
    case rejected
    case passed
    case archived
    case closed
    case duplicate
    case expired

    /// Statuses whose unread jobs are still awaiting a first review — what the dock badge counts.
    /// Everything else has either already been triaged (applied/interview/offer/rejected) or set
    /// aside (archived/expired/duplicate/…), and counting those made the badge report 144 against
    /// 56 jobs actually needing attention.
    public var awaitsReview: Bool {
        switch self {
        case .new, .pursuing: true
        case .applied, .interview, .offer, .rejected, .passed, .archived, .closed, .duplicate,
             .expired: false
        }
    }

    /// Statuses where the job is no longer an active pursuit, so it shouldn't surface actionable
    /// follow-ups (TASK-577). `rejected` is intentionally NOT terminal here — a user may still want a
    /// follow-up (e.g. ask for feedback). Used by `FollowUpVisibility`.
    public var isTerminal: Bool {
        switch self {
        case .passed, .archived, .closed, .duplicate, .expired: true
        case .new, .pursuing, .applied, .interview, .offer, .rejected: false
        }
    }
}

public enum ExtractionStatus: String, Codable, CaseIterable, Sendable {
    case pending
    case running
    case succeeded
    case failed
    case skipped
}

public enum FitStatus: String, Codable, CaseIterable, Sendable {
    case none
    case pending
    case running
    case succeeded
    case failed
}

public enum RemoteType: String, Codable, CaseIterable, Sendable {
    case remote
    case hybrid
    case onsite
    case unknown
}

public enum SiteState: String, Codable, CaseIterable, Sendable {
    case notReviewed = "not_reviewed"
    case reviewed
    case exclude
}

public enum LLMRequestType: String, Codable, CaseIterable, Sendable {
    case extract
    case fit
}

public enum LLMRequestStatus: String, Codable, CaseIterable, Sendable {
    case queued
    case running
    case succeeded
    case failed
    case retryExhausted = "retry_exhausted"
    case cancelled
}
