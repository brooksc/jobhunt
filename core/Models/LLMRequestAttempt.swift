import Foundation
import SwiftData

@Model
public final class LLMRequestAttempt {
    public var id: String
    public var requestType: LLMRequestType
    public var attempt: Int
    public var status: LLMRequestStatus
    public var modelRequested: String?
    public var modelReturned: String?
    public var responseFormat: String?
    public var baseURL: String?
    public var startedAt: Date
    public var finishedAt: Date?
    public var durationMs: Int?
    public var error: String?
    public var responsePreview: String?
    public var promptChars: Int?
    public var responseChars: Int?
    /// Actual provider-reported token usage when available (TASK-538). Char counts above remain the
    /// fallback for providers that don't report usage.
    public var promptTokens: Int?
    public var completionTokens: Int?

    public var request: LLMRequest?
    public var job: Job?

    public init(
        id: String = UUID().uuidString,
        requestType: LLMRequestType,
        attempt: Int,
        status: LLMRequestStatus,
        modelRequested: String? = nil,
        modelReturned: String? = nil,
        responseFormat: String? = nil,
        baseURL: String? = nil,
        startedAt: Date = Date(),
        finishedAt: Date? = nil,
        durationMs: Int? = nil,
        error: String? = nil,
        responsePreview: String? = nil,
        promptChars: Int? = nil,
        responseChars: Int? = nil,
        promptTokens: Int? = nil,
        completionTokens: Int? = nil
    ) {
        self.id = id
        self.requestType = requestType
        self.attempt = attempt
        self.status = status
        self.modelRequested = modelRequested
        self.modelReturned = modelReturned
        self.responseFormat = responseFormat
        self.baseURL = baseURL
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.durationMs = durationMs
        self.error = error
        self.responsePreview = responsePreview
        self.promptChars = promptChars
        self.responseChars = responseChars
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
    }
}
