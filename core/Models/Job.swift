import Foundation
import SwiftData

@Model
public final class Job {
    public var id: String
    // Safe to mark unique on fresh installs. For existing stores with duplicate jobNumber rows,
    // deduplicate before opening the store with this constraint active.
    @Attribute(.unique) public var jobNumber: Int?
    public var company: String?
    public var title: String?
    public var location: String?
    public var remoteType: RemoteType?
    public var salaryMin: Int?
    public var salaryMax: Int?
    public var salaryHourlyMin: Double?
    public var salaryHourlyMax: Double?
    public var salaryCurrency: String?
    public var salaryNote: String?
    public var employmentType: String?
    public var seniority: String?
    public var status: JobStatus
    public var manualOverridesJSON: String
    /// Field-level manual overrides: a JSON array of extracted-field names the user has edited.
    /// Extraction skips these fields so it won't clobber user edits. Nil = no overrides.
    public var manualFieldOverridesJSON: String?
    public var extractedJSON: String?
    public var extractionStatus: ExtractionStatus
    public var extractionError: String?
    public var fitScore: Int?
    public var fitStatus: FitStatus
    public var fitScoreJSON: String?
    /// Canonical duplicate signal. When non-nil, `status` must also be `.duplicate`.
    /// Use `JobService.markDuplicate` / `unmarkDuplicate` to maintain this invariant.
    public var duplicateOfJobID: String?
    public var duplicateConfidence: Double?
    public var extractedAt: Date?
    public var rating: Int?
    public var extractionModel: String?
    public var applicationURL: String?
    public var extractionConfidence: Double?
    /// Whether the job passed the user's location/remote criteria at extraction time (TASK-464,
    /// Electron `meets_criteria`). Nil for jobs extracted before this field / when not computed.
    public var meetsCriteria: Bool?
    public var lastOpenedAt: Date?
    /// When the job's status first became `.applied` (TASK-504). Stamped once by `setJobStatus` and
    /// never overwritten on re-apply; nil for jobs applied before this field existed (optional, so it's
    /// a lightweight in-place addition, not a SchemaV2 change). Surfaced as "Applied {date}".
    public var appliedAt: Date?
    public var unread: Bool
    public var createdAt: Date
    public var updatedAt: Date
    public var rawTextBytes: Int?
    public var cleanedTextBytes: Int?
    /// Denormalized copy of `capture.capturedAt` for use in store-level predicates.
    /// Nil on rows ingested before this field was added; fall back to `createdAt` when nil.
    public var capturedAtDenormalized: Date?

    @Relationship(deleteRule: .cascade)
    public var capture: Capture?

    @Relationship(deleteRule: .cascade, inverse: \JobEvent.job)
    public var events: [JobEvent]

    @Relationship(deleteRule: .cascade, inverse: \JobAction.job)
    public var actions: [JobAction]

    @Relationship(deleteRule: .cascade, inverse: \Contact.job)
    public var contacts: [Contact]

    @Relationship(deleteRule: .cascade, inverse: \CoverLetter.job)
    public var coverLetters: [CoverLetter]

    @Relationship(deleteRule: .cascade, inverse: \JobFitScore.job)
    public var fitScores: [JobFitScore]

    @Relationship(deleteRule: .cascade, inverse: \LLMRequest.job)
    public var llmRequests: [LLMRequest]

    @Relationship(deleteRule: .cascade, inverse: \DataQualityReview.job)
    public var qualityReview: DataQualityReview?

    public init(
        id: String = UUID().uuidString,
        jobNumber: Int? = nil,
        company: String? = nil,
        title: String? = nil,
        location: String? = nil,
        remoteType: RemoteType? = nil,
        salaryMin: Int? = nil,
        salaryMax: Int? = nil,
        salaryHourlyMin: Double? = nil,
        salaryHourlyMax: Double? = nil,
        salaryCurrency: String? = nil,
        salaryNote: String? = nil,
        employmentType: String? = nil,
        seniority: String? = nil,
        status: JobStatus = .new,
        manualOverridesJSON: String = "[]",
        manualFieldOverridesJSON: String? = nil,
        extractedJSON: String? = nil,
        extractionStatus: ExtractionStatus = .pending,
        extractionError: String? = nil,
        fitScore: Int? = nil,
        fitStatus: FitStatus = .none,
        fitScoreJSON: String? = nil,
        duplicateOfJobID: String? = nil,
        duplicateConfidence: Double? = nil,
        extractedAt: Date? = nil,
        rating: Int? = nil,
        extractionModel: String? = nil,
        applicationURL: String? = nil,
        extractionConfidence: Double? = nil,
        meetsCriteria: Bool? = nil,
        lastOpenedAt: Date? = nil,
        appliedAt: Date? = nil,
        unread: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.jobNumber = jobNumber
        self.company = company
        self.title = title
        self.location = location
        self.remoteType = remoteType
        self.salaryMin = salaryMin
        self.salaryMax = salaryMax
        self.salaryHourlyMin = salaryHourlyMin
        self.salaryHourlyMax = salaryHourlyMax
        self.salaryCurrency = salaryCurrency
        self.salaryNote = salaryNote
        self.employmentType = employmentType
        self.seniority = seniority
        self.status = status
        self.manualOverridesJSON = manualOverridesJSON
        self.manualFieldOverridesJSON = manualFieldOverridesJSON
        self.extractedJSON = extractedJSON
        self.extractionStatus = extractionStatus
        self.extractionError = extractionError
        self.fitScore = fitScore
        self.fitStatus = fitStatus
        self.fitScoreJSON = fitScoreJSON
        self.duplicateOfJobID = duplicateOfJobID
        self.duplicateConfidence = duplicateConfidence
        self.extractedAt = extractedAt
        self.rating = rating
        self.extractionModel = extractionModel
        self.applicationURL = applicationURL
        self.extractionConfidence = extractionConfidence
        self.meetsCriteria = meetsCriteria
        self.lastOpenedAt = lastOpenedAt
        self.appliedAt = appliedAt
        self.unread = unread
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        events = []
        actions = []
        contacts = []
        coverLetters = []
        fitScores = []
        llmRequests = []
    }
}

// MARK: - Manual field-override helpers

/// Decode the set of extracted-field names the user has manually overridden.
func manualFieldOverrideSet(_ json: String?) -> Set<String> {
    guard let json, let data = json.data(using: .utf8),
          let arr = try? JSONSerialization.jsonObject(with: data) as? [String] else { return [] }
    return Set(arr)
}

/// Encode a set of overridden field names back to JSON (nil when empty).
func manualFieldOverrideJSON(_ set: Set<String>) -> String? {
    guard !set.isEmpty, let data = try? JSONSerialization.data(withJSONObject: Array(set).sorted())
    else { return nil }
    return String(data: data, encoding: .utf8)
}

/// Clear every extraction-owned field on a job so a stale value can't show as current while
/// extraction is pending — used by both the explicit reset and the same-URL recapture requeue so the
/// two can't drift (TASK-517). Fields the user manually overrode are PRESERVED: re-extraction also
/// skips overridden fields, so clearing them here would silently lose the edit. Salary-hourly,
/// employment type, seniority, and criteria have no manual-edit path and are always cleared. The
/// caller sets `extractionStatus`/`extractionError`/`updatedAt`.
func clearExtractionOwnedFields(_ job: Job) {
    let overrides = manualFieldOverrideSet(job.manualFieldOverridesJSON)
    job.extractedAt = nil
    job.extractedJSON = nil
    job.extractionModel = nil
    job.extractionConfidence = nil
    if !overrides.contains("company") { job.company = nil }
    if !overrides.contains("title") { job.title = nil }
    if !overrides.contains("location") { job.location = nil }
    if !overrides.contains("remoteType") { job.remoteType = nil }
    if !overrides.contains("salaryMin") { job.salaryMin = nil }
    if !overrides.contains("salaryMax") { job.salaryMax = nil }
    if !overrides.contains("salaryCurrency") { job.salaryCurrency = nil }
    if !overrides.contains("salaryNote") { job.salaryNote = nil }
    if !overrides.contains("applicationURL") { job.applicationURL = nil }
    job.salaryHourlyMin = nil
    job.salaryHourlyMax = nil
    job.employmentType = nil
    job.seniority = nil
    job.meetsCriteria = nil
}
