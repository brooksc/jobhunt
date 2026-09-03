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
    /// Set when the quoted evidence for this row appears in no résumé the user has had. `nil` is the
    /// normal case, and also covers every score written before the check existed — absence means
    /// "not checked", never "checked and clean".
    public let evidenceSupport: EvidenceCheck.Support?
    /// The quotes that couldn't be found, so the warning can point at the words rather than asking
    /// the user to take it on faith.
    public let unsupportedEvidence: [String]

    public init(
        requirement: String,
        kind: String,
        status: String,
        evidence: String,
        evidenceSupport: EvidenceCheck.Support? = nil,
        unsupportedEvidence: [String] = []
    ) {
        self.requirement = requirement
        self.kind = kind
        self.status = status
        self.evidence = evidence
        self.evidenceSupport = evidenceSupport
        self.unsupportedEvidence = unsupportedEvidence
    }

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
    /// The overall score **with the user's corrections applied**, recomputed from the stored analysis.
    ///
    /// The rows and the number used to run on two different clocks: the rows came from this
    /// projection and updated the instant a correction was saved, while the ring read the persisted
    /// `JobFitScore.fitScore`, which only moved once the background recompute finished. So a
    /// requirement would jump from Gaps to Requirements met while the headline number sat unchanged —
    /// which reads as the correction not having worked. Views should prefer this over the stored
    /// value; the recompute then persists the same number it already shows.
    ///
    /// `nil` for a stored analysis that can't be rescored (legacy rows with no dimensions), in which
    /// case the caller falls back to the persisted score.
    public let overallScore: Int?

    /// `feedback` is applied here as well as when gaps are built, or the two disagree: flagging
    /// "I don't have this" moved the score while the row still displayed a green tick.
    public init(fitScore: JobFitScore, feedback: [ScoringFeedback] = [], jobNumber: Int? = nil) {
        let dict = Self.parseJSON(fitScore.fitScoreJSON)

        let assessments = (dict?["requirement_assessments"] as? [[String: Any]])?
            .compactMap { a -> RequirementAssessment? in
                guard let requirement = a["requirement"] as? String,
                      var status = a["status"] as? String else { return nil }
                // Dropped from the READ MODEL, not just from the penalty: "Experience with, or
                // capacity to learn, JIRA" showing under Gaps is noise even at zero cost — it reads
                // as something to fix when there is nothing to fix (job #718).
                guard !FitScorer.isExcludedFromScoring(requirement: requirement) else { return nil }
                // A correction replaces the model's verdict, so the model's evidence no longer
                // describes what the row now says. Left in place, an `alwaysCredit` row showed a green
                // tick above "Not evidenced — a reader of this resume would not credit it." Say who
                // decided instead.
                var evidence = a["evidence"] as? String ?? ""
                switch feedback.verdict(forRequirement: requirement, jobNumber: jobNumber) {
                case .forceMissing:
                    status = "missing"
                    evidence = "You marked this as something you don't have."
                case .forceMet:
                    status = "met"
                    evidence = "You marked this as something you have."
                case .ignore: return nil
                case .none: break
                }
                return RequirementAssessment(
                    requirement: requirement,
                    kind: a["kind"] as? String ?? "unknown",
                    status: status,
                    evidence: evidence,
                    evidenceSupport: (a[EvidenceCheck.supportKey] as? String)
                        .flatMap(EvidenceCheck.Support.init(rawValue:)),
                    unsupportedEvidence: (a[EvidenceCheck.unsupportedSpansKey] as? [String]) ?? []
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

        // Same call the background recompute makes, so the number shown now is the number stored
        // later — not an approximation of it.
        overallScore = fitScore.fitScoreJSON.flatMap {
            FitScorer.rescoreFromJSON($0, feedback: feedback, jobNumber: jobNumber)?.overall
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

/// A job's number, as an identifier rather than a quantity.
///
/// `Text("#\(number)")` interpolates into a `LocalizedStringKey`, which formats an `Int` with the
/// locale's grouping separator — so job 1349 rendered as **#1,349**. A job number is a label, not a
/// count; nobody groups the digits of an invoice number. Passing a pre-built `String` also picks
/// SwiftUI's non-localizing `Text` overload, which is what an identifier wants.
public enum JobNumberDisplay {
    public static func label(_ number: Int) -> String {
        "#\(number)"
    }
}

public enum SalaryDisplay {
    /// Formats salary fields into a compact display string, e.g. "$120k–$160k".
    /// Returns nil when both min and max are absent.
    ///
    /// **A currency is never assumed.** This read `currency ?? "USD"` and defaulted every unknown
    /// code to `$`, so a Swedish posting extracted at 996,819–1,196,182 SEK — about $95k — was shown
    /// as **$996k–$1196k**, and CAD rows were shown as USD. A salary is the field most likely to
    /// decide whether a job is worth opening, so a wrong currency is worse than a missing one:
    ///
    /// - A code we have a symbol for prints the symbol.
    /// - Any other code prints the code itself ("SEK 996k"), which is unambiguous.
    /// - No code at all prints the bare number, because inventing one is how the bug above happened.
    public static func text(min: Int?, max: Int?, currency: String?) -> String? {
        let code = (currency ?? "").trimmingCharacters(in: .whitespaces).uppercased()
        let symbols = ["USD": "$", "GBP": "£", "EUR": "€", "JPY": "¥"]
        // A prefix, so it composes the same way whether it is a symbol, a code, or nothing.
        let unit = symbols[code] ?? (code.isEmpty ? "" : "\(code) ")
        let k: (Int) -> String = { v in v >= 1000 ? "\(v / 1000)k" : "\(v)" }
        if let lo = min, let hi = max { return "\(unit)\(k(lo))–\(unit)\(k(hi))" }
        if let lo = min { return "\(unit)\(k(lo))+" }
        if let hi = max { return "up to \(unit)\(k(hi))" }
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
    // TASK-464: MCP jobs_list payload fields that had gone missing — an AI client can't triage on
    // employment type, seniority or duplicate status if the list never carries them.
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
    // TASK-464: MCP payload fields that had gone missing — see `JobListRecord` above.
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
    /// The weighted dimension score before penalties. "90 base, −16 penalty" is far more
    /// interpretable than "74", and lets a consumer re-weight without re-deriving.
    public let base: Int?
    public let penalty: Int?
    public let penaltyReasons: [String]
    /// Which scoring prompt produced this assessment. Scores from different versions are different
    /// measurements — a threshold filter that mixes them is comparing unlike things.
    public let assessmentPromptVersion: Int
    /// When the résumé record was last changed. `reflectsPreviousResumeVersion` compares hashes of
    /// the text stored IN the app, so editing the source file without re-importing leaves it false
    /// while the score is stale; exposing this alongside `scoredAt` lets a consumer judge for itself.
    public let resumeUpdatedAt: Date?

    init(fitScore: JobFitScore) {
        let projection = FitScoreProjection(fitScore: fitScore)
        let stored = Self.storedFields(fitScore.fitScoreJSON)
        base = stored.base
        penalty = stored.penalty
        penaltyReasons = stored.reasons
        assessmentPromptVersion = stored.promptVersion
        resumeUpdatedAt = fitScore.resume?.updatedAt
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

    /// Fields the scorer merges into `fitScoreJSON` but no projection surfaced.
    private static func storedFields(
        _ json: String?
    ) -> (base: Int?, penalty: Int?, reasons: [String], promptVersion: Int) {
        guard let json, let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return (nil, nil, [], 1) }
        let penalty = dict["penalty"] as? Int
        // From the stored breakdown rather than `overall + penalty`: the overall is floored at 0, so
        // adding the penalty back would report a base the scorer never produced (base 30 with a 60
        // penalty stores 0, which would read back as 60). Uses the scorer's own arithmetic — an
        // independent reimplementation here disagreed by a point on the very first job.
        let base = (dict["breakdown"] as? [String: Double]).map(FitScorer.baseScore(breakdown:))
        let reasons = (dict["penaltyReasons"] as? [String]) ?? []
        let version = (dict["assessment_prompt_version"] as? Int) ?? 1
        return (base, penalty, reasons, version)
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
