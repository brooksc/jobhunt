import Foundation
import SwiftData

@Model
public final class LLMRequest {
    public var id: String
    public var requestType: LLMRequestType
    public var status: LLMRequestStatus
    public var attempt: Int
    public var model: String?
    public var error: String?
    public var createdAt: Date
    public var startedAt: Date?
    public var finishedAt: Date?

    public var job: Job?

    /// resume is optional (only for fit-scoring requests)
    public var resume: Resume?

    @Relationship(deleteRule: .cascade, inverse: \LLMRequestAttempt.request)
    public var attempts: [LLMRequestAttempt]

    public init(
        id: String = UUID().uuidString,
        requestType: LLMRequestType = .extract,
        status: LLMRequestStatus = .queued,
        attempt: Int = 1,
        model: String? = nil,
        error: String? = nil,
        createdAt: Date = Date(),
        startedAt: Date? = nil,
        finishedAt: Date? = nil
    ) {
        self.id = id
        self.requestType = requestType
        self.status = status
        self.attempt = attempt
        self.model = model
        self.error = error
        self.createdAt = createdAt
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        attempts = []
    }
}
