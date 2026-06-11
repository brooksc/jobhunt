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
