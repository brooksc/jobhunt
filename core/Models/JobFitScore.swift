import Foundation
import SwiftData

@Model
public final class JobFitScore {
    public var fitScore: Int?
    public var fitStatus: FitStatus
    public var fitScoreJSON: String?
    public var model: String?
    public var scoredAt: Date?
    public var createdAt: Date
    public var updatedAt: Date

    public var job: Job?
    public var resume: Resume?

    public init(
        fitScore: Int? = nil,
        fitStatus: FitStatus = .none,
        fitScoreJSON: String? = nil,
        model: String? = nil,
        scoredAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.fitScore = fitScore
        self.fitStatus = fitStatus
        self.fitScoreJSON = fitScoreJSON
        self.model = model
        self.scoredAt = scoredAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
