import Foundation
import SwiftData

@Model
public final class JobFitScore {
    public var fitScore: Int?
    public var fitStatus: FitStatus
    public var fitScoreJSON: String?
    public var model: String?
    public var scoredAt: Date?
    /// Fingerprint of the résumé text this score was computed against.
    ///
    /// Editing a résumé used to DELETE every score computed from it — correct in spirit (a score
    /// against the old text is a stale claim) but brutal in practice: a one-line tweak destroyed
    /// hundreds of scores and hundreds of dollars of LLM work, with no way back. Recording which text
    /// produced the score means the claim can be marked stale instead of the evidence being thrown
    /// away, and the user chooses when to spend money re-scoring. Nil on rows written before this
    /// existed — treated as "unknown version", not stale.
    public var resumeTextHash: String?
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

public extension JobFitScore {
    /// True when this score was computed against a different résumé text than the résumé holds now.
    ///
    /// A nil `resumeTextHash` means the row predates version tracking — treated as *unknown*, not
    /// stale, so historic scores aren't all suddenly labelled wrong.
    var reflectsPreviousResumeVersion: Bool {
        guard let resume, let resumeTextHash else { return false }
        return resumeTextHash != ResumeFingerprint.hash(resume.text)
    }
}
