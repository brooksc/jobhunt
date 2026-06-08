import Foundation
import SwiftData

@Model
public final class Job {
    public var id: String
    public var jobNumber: Int?
    public var company: String?
    public var title: String?
    public var location: String?
    public var remoteType: RemoteType?
    public var salaryMin: Int?
    public var salaryMax: Int?
    public var salaryCurrency: String?
    public var salaryNote: String?
    public var employmentType: String?
    public var seniority: String?
    public var status: JobStatus
    public var manualOverridesJSON: String
    public var extractedJSON: String?
    public var extractionStatus: ExtractionStatus
    public var extractionError: String?
    public var fitScore: Int?
    public var fitStatus: FitStatus
    public var fitScoreJSON: String?
    public var duplicateOfJobID: String?
    public var duplicateConfidence: Double?
    public var extractedAt: Date?
    public var rating: Int?
    public var extractionModel: String?
    public var applicationURL: String?
    public var extractionConfidence: Double?
    public var lastOpenedAt: Date?
    public var unread: Bool
    public var createdAt: Date
    public var updatedAt: Date

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
        salaryCurrency: String? = nil,
        salaryNote: String? = nil,
        employmentType: String? = nil,
        seniority: String? = nil,
        status: JobStatus = .saved,
        manualOverridesJSON: String = "[]",
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
        lastOpenedAt: Date? = nil,
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
        self.salaryCurrency = salaryCurrency
        self.salaryNote = salaryNote
        self.employmentType = employmentType
        self.seniority = seniority
        self.status = status
        self.manualOverridesJSON = manualOverridesJSON
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
        self.lastOpenedAt = lastOpenedAt
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
