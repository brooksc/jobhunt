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
