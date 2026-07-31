import Foundation

// MARK: - JobDetailProjection

//
// Typed read model derived from a Job's raw extracted JSON and manual overrides.
// Centralizes all JSON parsing so SwiftUI views never touch extractedJSON directly.

public struct JobDetailProjection {
    public let summary: String?
    public let requirements: [String]
    public let niceToHaves: [String]
    public let skills: [String]

    public init(job: Job) {
        let dict = Self.parseJSON(job.extractedJSON)
        summary = dict?["summary"] as? String
        requirements = (dict?["requirements"] as? [String]) ?? []
        niceToHaves = (dict?["nice_to_have"] as? [String])
            ?? (dict?["nice_to_haves"] as? [String]) ?? []

        // Non-empty manual overrides take precedence over extracted skills.
        // An empty array "[]" is the default and means "no overrides yet — use extracted."
        if let data = job.manualOverridesJSON.data(using: .utf8),
           let arr = try? JSONSerialization.jsonObject(with: data) as? [String],
           !arr.isEmpty {
            skills = arr
        } else {
            skills = (dict?["skills"] as? [String]) ?? []
        }
    }

    private static func parseJSON(_ json: String?) -> [String: Any]? {
        guard let json,
              let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return dict
    }
}

// MARK: - FitScoreProjection

//
// Typed read model derived from a JobFitScore's raw fitScoreJSON.

public struct FitDimension: Sendable {
    public let name: String
    public let score: Int
    public let rationale: String?
}

/// One job qualification evaluated against a resume (TASK-490). `status` is "met" / "partial" /
/// "missing". Because the requirement list is extracted once per job, every resume is assessed
/// against the identical set — the gaps are consistent across resumes.
public struct RequirementAssessment: Sendable, Hashable {
    public let requirement: String
    /// "required" / "preferred" — whether the job listed this under required vs nice-to-have
    /// qualifications. "unknown" for legacy fit scores written before `kind` was captured.
    public let kind: String
    public let status: String
    public let evidence: String
    public var isMet: Bool {
        status == "met"
    }

    public var isPreferred: Bool {
        kind == "preferred"
    }

    /// Plain-English meaning of this row, for a tooltip.
    ///
    /// The icon and the "Preferred" tag encode two INDEPENDENT things — how well the résumé matches
    /// (met / partial / missing) and how the job weighted the requirement (required / preferred) — so
    /// the same "!" legitimately appears on both a required and a preferred row. Nothing on screen
    /// said so, which made the icons look arbitrary. This spells out both axes in one sentence.
    public var matchExplanation: String {
        switch status {
        case "met": "Met — your résumé shows clear evidence of this."
        case "partial": "Partially met — there's related evidence, but not a direct match."
        default: "Not met — no evidence of this in your résumé."
        }
    }

    /// How the job weighted it. Empty for legacy scores written before `kind` was captured, so an
    /// old score never claims a requirement was required when that wasn't recorded.
    public var weightExplanation: String {
        switch kind {
        case "preferred": "The job lists it as preferred (nice-to-have)."
        case "required": "The job lists it as required."
        default: ""
        }
    }

    /// Combined tooltip: what the icon means, then what the tag means.
    public var explanation: String {
        let weight = weightExplanation
        return weight.isEmpty ? matchExplanation : "\(matchExplanation) \(weight)"
    }
}

public struct FitScoreProjection {
    public let requirementsMet: [String]
    public let requirementsNotMet: [String]
    /// Structured per-requirement assessments (TASK-490). Empty for legacy fit scores that predate it.
    public let requirementAssessments: [RequirementAssessment]
    public let dimensions: [FitDimension]

    public init(fitScore: JobFitScore) {
        let dict = Self.parseJSON(fitScore.fitScoreJSON)

        let assessments = (dict?["requirement_assessments"] as? [[String: Any]])?
            .compactMap { a -> RequirementAssessment? in
                guard let requirement = a["requirement"] as? String,
                      let status = a["status"] as? String else { return nil }
                return RequirementAssessment(
                    requirement: requirement,
                    kind: a["kind"] as? String ?? "unknown",
                    status: status,
                    evidence: a["evidence"] as? String ?? ""
                )
            } ?? []
        requirementAssessments = assessments

        if assessments.isEmpty {
            // Legacy fit scores: read the old free-form arrays.
            requirementsMet = (dict?["requirements_met"] as? [String]) ?? []
            requirementsNotMet = (dict?["requirements_not_met"] as? [String]) ?? []
        } else {
            // Derive the met/not-met splits from the structured assessments (met vs partial+missing).
            requirementsMet = assessments.filter(\.isMet).map(\.requirement)
            requirementsNotMet = assessments.filter { !$0.isMet }.map(\.requirement)
        }

        dimensions = (dict?["dimensions"] as? [[String: Any]])?.compactMap { d in
            guard let name = d["name"] as? String else { return nil }
            let score: Int
            if let dbl = d["score"] as? Double {
                // LLM-produced score is untrusted (prompt-injectable): a non-finite or out-of-range
                // value would trap `Int(_:)` and abort the app. Clamp to the 0–100 fit scale (CWE-190).
                guard dbl.isFinite else { return nil }
                score = Int(min(100, max(0, dbl.rounded())))
            } else if let int = d["score"] as? Int {
                score = int
            } else {
                return nil
            }
            return FitDimension(name: name, score: score, rationale: d["rationale"] as? String)
        } ?? []
    }

    private static func parseJSON(_ json: String?) -> [String: Any]? {
        guard let json,
              let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return dict
    }
}

// MARK: - Salary display

public enum SalaryDisplay {
    /// Formats salary fields into a compact display string, e.g. "$120k–$160k".
    /// Returns nil when both min and max are absent.
    public static func text(min: Int?, max: Int?, currency: String?) -> String? {
        let sym: String
        switch currency ?? "USD" {
        case "GBP": sym = "£"
        case "EUR": sym = "€"
        default: sym = "$"
        }
        let k: (Int) -> String = { v in v >= 1000 ? "\(v / 1000)k" : "\(v)" }
        if let lo = min, let hi = max { return "\(sym)\(k(lo))–\(sym)\(k(hi))" }
        if let lo = min { return "\(sym)\(k(lo))+" }
        if let hi = max { return "up to \(sym)\(k(hi))" }
        return nil
    }
}

// MARK: - MCP Read Models

//
// Plain Sendable structs used by Core service query methods so route handlers
// only perform auth, request decoding, and response encoding — no FetchDescriptors.

public struct JobListRecord: Sendable {
    public let id: String
    public let jobNumber: Int?
    public let status: JobStatus
    public let extractionStatus: ExtractionStatus
    public let company: String?
    public let title: String?
    public let location: String?
    public let remoteType: RemoteType?
    public let salaryMin: Int?
    public let salaryMax: Int?
    public let salaryNote: String?
    public let rating: Int?
    public let pageTitle: String?
    public let sourceURL: String?
    public let capturedAt: Date?
    public let createdAt: Date
    // TASK-464: re-added MCP jobs_list payload fields dropped vs Electron.
    public let employmentType: String?
    public let seniority: String?
    public let duplicateOfJobID: String?
    /// Denormalized overall fit against the active résumés — the number the Jobs list shows.
    /// Absent from the MCP payload entirely until now, so score-based triage wasn't possible.
    public let fitScore: Int?
    public let fitStatus: FitStatus
    /// Exposed alongside the amounts: `salaryMin`/`salaryMax` without it read as USD, so a EUR or
    /// CAD posting was silently reported as dollars.
    public let salaryCurrency: String?
    public let salaryHourlyMin: Double?
    public let salaryHourlyMax: Double?
    /// The requirements verdict (location + salary + fit floors) the Jobs list filters on.
    public let meetsCriteria: Bool?
    public let appliedAt: Date?
    public let updatedAt: Date
    public let unread: Bool

    init(job: Job) {
        id = job.id
        jobNumber = job.jobNumber
        status = job.status
        extractionStatus = job.extractionStatus
        company = job.company
        title = job.title
        location = job.location
        remoteType = job.remoteType
        salaryMin = job.salaryMin
        salaryMax = job.salaryMax
        salaryNote = job.salaryNote
        rating = job.rating
        pageTitle = job.capture?.pageTitle
        sourceURL = JobURLPolicy.sourceURL(job: job)
        capturedAt = job.capture?.capturedAt ?? job.capture?.createdAt
        createdAt = job.createdAt
        employmentType = job.employmentType
        seniority = job.seniority
        duplicateOfJobID = job.duplicateOfJobID
        fitScore = job.fitScore
        fitStatus = job.fitStatus
        salaryCurrency = job.salaryCurrency
        salaryHourlyMin = job.salaryHourlyMin
        salaryHourlyMax = job.salaryHourlyMax
        meetsCriteria = job.meetsCriteria
        appliedAt = job.appliedAt
        updatedAt = job.updatedAt
        unread = job.unread
    }
}

/// A filtered, offset-paged slice of the job list, with the totals a caller needs to know whether
/// it has seen everything.
///
/// The list API previously returned a bare array capped at 200 with no offset, so any status with
/// more rows was partly unreachable and the truncation was invisible — an "analysis of all archived
/// jobs" silently ran against the 200 most recent of 474.
public struct JobListPage: Sendable {
    /// The records for this page.
    public let records: [JobListRecord]
    /// Total matching the filters, ignoring offset/limit.
    public let total: Int
    public let offset: Int
    /// The limit actually applied, which may be lower than the one requested.
    public let limit: Int

    public init(records: [JobListRecord], total: Int, offset: Int, limit: Int) {
        self.records = records
        self.total = total
        self.offset = offset
        self.limit = limit
    }

    public var hasMore: Bool {
        offset + records.count < total
    }

    public var nextOffset: Int? {
        hasMore ? offset + records.count : nil
    }
}

/// Filters for `JobService.listJobs`. All are optional and combine with AND.
public struct JobQuery: Sendable {
    public var status: String?
    /// Case-insensitive substring matched against title, company, page title, location and the
    /// cleaned description — so a corpus-wide keyword question ("SOC 2") doesn't require paging
    /// every record to the caller.
    public var query: String?
    public var company: String?
    public var capturedAfter: Date?
    /// Keeps jobs whose salary ceiling reaches this figure; jobs with no salary are excluded only
    /// when this is set.
    public var minSalary: Int?
    /// Keeps jobs scoring at least this against the active résumés. Unscored jobs are excluded when
    /// set — a job with no score can't be shown to clear a threshold.
    public var minScore: Int?
    public var offset: Int
    public var limit: Int

    public init(
        status: String? = nil,
        query: String? = nil,
        company: String? = nil,
        capturedAfter: Date? = nil,
        minSalary: Int? = nil,
        minScore: Int? = nil,
        offset: Int = 0,
        limit: Int = 50
    ) {
        self.status = status
        self.query = query
        self.company = company
        self.capturedAfter = capturedAfter
        self.minSalary = minSalary
        self.minScore = minScore
        self.offset = offset
        self.limit = limit
    }
}

/// Full read model returned by the MCP `job_get` tool and the HTTP `/api/jobs/:number` endpoint.
///
/// **Privacy note:** `selectedText` and `visibleText` are the raw text captured from the job
/// posting page. Including them by default is intentional — local agent workflows (Claude MCP,
/// Cursor, etc.) need access to source text for summarization and re-extraction. The MCP
/// endpoint is local-only (127.0.0.1) and requires a per-device bearer token, so this data
/// is only reachable by processes on the user's own machine that hold the token.
///
/// If this record is ever exposed over a network boundary, `selectedText`/`visibleText` should
/// be moved behind an explicit opt-in parameter.
public struct JobDetailRecord: Sendable {
    public let id: String
    public let jobNumber: Int?
    public let status: JobStatus
    public let extractionStatus: ExtractionStatus
    public let extractionError: String?
    public let company: String?
    public let title: String?
    public let location: String?
    public let remoteType: RemoteType?
    public let salaryMin: Int?
    public let salaryMax: Int?
    public let salaryNote: String?
    public let rating: Int?
    public let pageTitle: String?
    public let sourceURL: String?
    public let capturedAt: Date?
    public let createdAt: Date
    public let selectedText: String?
    public let visibleText: String?
    // TASK-464: re-added MCP payload fields dropped vs Electron.
    public let employmentType: String?
    public let seniority: String?
    public let duplicateOfJobID: String?
    public let events: [JobEventRecord]
    /// Every stored fit analysis, one per résumé — the structured breakdown the app shows in the Fit
    /// tab. Previously computed and stored but unreachable through the MCP.
    public let fitScores: [JobFitScoreRecord]
    /// Denormalized overall fit (active résumés only), matching `JobListRecord`.
    public let fitScore: Int?
    public let fitStatus: FitStatus
    public let salaryCurrency: String?
    public let salaryHourlyMin: Double?
    public let salaryHourlyMax: Double?
    public let meetsCriteria: Bool?
    public let appliedAt: Date?
    public let updatedAt: Date
    public let unread: Bool
    public let lastOpenedAt: Date?
    public let applicationURL: String?
    /// The text the extractor and the search actually read — far more useful than the raw page dump,
    /// and previously unreachable even though `query` searches it.
    public let cleanedDescription: String?
    public let userNote: String?
    public let canonicalURL: String?
    /// Structured extraction output: summary, requirements, nice-to-haves, skills.
    public let summary: String?
    public let requirements: [String]
    public let niceToHaves: [String]
    public let skills: [String]
    public let extractedAt: Date?
    public let extractionModel: String?
    public let extractionConfidence: Double?
    /// Field names the user edited by hand. Those values are authoritative; the rest are the model's.
    public let manuallyOverriddenFields: [String]
    public let duplicateConfidence: Double?

    init(job: Job) {
        id = job.id
        jobNumber = job.jobNumber
        status = job.status
        extractionStatus = job.extractionStatus
        extractionError = job.extractionError
        company = job.company
        title = job.title
        location = job.location
        remoteType = job.remoteType
        salaryMin = job.salaryMin
        salaryMax = job.salaryMax
        salaryNote = job.salaryNote
        rating = job.rating
        pageTitle = job.capture?.pageTitle
        sourceURL = JobURLPolicy.sourceURL(job: job)
        capturedAt = job.capture?.capturedAt ?? job.capture?.createdAt
        createdAt = job.createdAt
        selectedText = job.capture?.selectedText
        visibleText = job.capture?.visibleText
        employmentType = job.employmentType
        seniority = job.seniority
        duplicateOfJobID = job.duplicateOfJobID
        events = job.events
            .sorted { $0.occurredAt < $1.occurredAt }
            .map { JobEventRecord(eventType: $0.eventType, note: $0.note, occurredAt: $0.occurredAt) }
        fitScore = job.fitScore
        fitStatus = job.fitStatus
        salaryCurrency = job.salaryCurrency
        salaryHourlyMin = job.salaryHourlyMin
        salaryHourlyMax = job.salaryHourlyMax
        meetsCriteria = job.meetsCriteria
        appliedAt = job.appliedAt
        updatedAt = job.updatedAt
        unread = job.unread
        lastOpenedAt = job.lastOpenedAt
        applicationURL = job.applicationURL
        cleanedDescription = job.capture?.cleanedDescription
        userNote = job.capture?.userNote
        canonicalURL = job.capture?.canonicalURL
        let projection = JobDetailProjection(job: job)
        summary = projection.summary
        requirements = projection.requirements
        niceToHaves = projection.niceToHaves
        skills = projection.skills
        extractedAt = job.extractedAt
        extractionModel = job.extractionModel
        extractionConfidence = job.extractionConfidence
        manuallyOverriddenFields = Self.overriddenFields(job.manualFieldOverridesJSON)
        duplicateConfidence = job.duplicateConfidence
        fitScores = job.fitScores
            .sorted { ($0.fitScore ?? -1) > ($1.fitScore ?? -1) }
            .map { JobFitScoreRecord(fitScore: $0) }
    }

    /// `manualFieldOverridesJSON` is a JSON array of field names the user edited by hand.
    private static func overriddenFields(_ json: String?) -> [String] {
        guard let json, let data = json.data(using: .utf8),
              let names = try? JSONSerialization.jsonObject(with: data) as? [String] else { return [] }
        return names
    }
}

/// One résumé's fit analysis, flattened for MCP callers so they don't have to parse `fitScoreJSON`.
public struct JobFitScoreRecord: Sendable {
    public let resumeID: String?
    public let resumeName: String?
    /// Only active résumés feed the job's headline score, so a caller can tell why a stored
    /// analysis isn't reflected in `fitScore`.
    public let resumeActive: Bool
    public let score: Int?
    public let status: FitStatus
    public let model: String?
    public let scoredAt: Date?
    /// True when the résumé has been edited since this was scored, so the analysis describes older
    /// text (see `JobFitScore.reflectsPreviousResumeVersion`).
    public let reflectsPreviousResumeVersion: Bool
    public let dimensions: [FitDimension]
    public let requirementAssessments: [RequirementAssessment]

    init(fitScore: JobFitScore) {
        let projection = FitScoreProjection(fitScore: fitScore)
        resumeID = fitScore.resume?.id
        resumeName = fitScore.resume?.name
        resumeActive = fitScore.resume?.active ?? false
        score = fitScore.fitScore
        status = fitScore.fitStatus
        model = fitScore.model
        scoredAt = fitScore.scoredAt
        reflectsPreviousResumeVersion = fitScore.reflectsPreviousResumeVersion
        dimensions = projection.dimensions
        requirementAssessments = projection.requirementAssessments
    }
}

/// Sendable projection of a job timeline event for MCP payloads (TASK-464).
public struct JobEventRecord: Sendable {
    public let eventType: String
    public let note: String?
    public let occurredAt: Date
}

public struct SiteListRecord: Sendable {
    public let id: String
    public let url: String
    public let companyName: String?
    public let state: SiteState
    public let intervalDays: Int
    public let note: String
    public let createdAt: Date
    public let nextReviewAt: Date?
    public let lastReviewedAt: Date?

    init(site: Site) {
        id = site.id
        url = site.url
        companyName = site.companyName
        state = site.state
        intervalDays = site.intervalDays
        note = site.note
        createdAt = site.createdAt
        nextReviewAt = site.nextReviewAt
        lastReviewedAt = site.lastReviewedAt
    }
}

public struct WorkflowSnapshot: Sendable {
    public let jobsTotal: Int
    public let sitesTotal: Int
    public let statusCounts: [String: Int]
    public let sitesDue: Int
    public let extractionStatusCounts: [String: Int]

    public init(
        jobsTotal: Int,
        sitesTotal: Int,
        statusCounts: [String: Int],
        sitesDue: Int = 0,
        extractionStatusCounts: [String: Int] = [:]
    ) {
        self.jobsTotal = jobsTotal
        self.sitesTotal = sitesTotal
        self.statusCounts = statusCounts
        self.sitesDue = sitesDue
        self.extractionStatusCounts = extractionStatusCounts
    }
}
