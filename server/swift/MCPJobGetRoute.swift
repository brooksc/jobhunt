#if !MAS_BUILD
    import Foundation
    import JobhuntCore
    import SwiftData

    /// The MCP `job_get` route and its payload types, including the fit analysis.
    ///
    /// Split out of MCPBridgeRoutes.swift, which the additions pushed past the file-length limit.
    /// Module scope, matching that file — these are free functions, not members of a type.
    /// The stored fit analysis for one résumé, flattened for MCP callers. JobHunt computed and
    /// stored all of this but returned none of it, so score-based questions couldn't be answered.
    private struct MCPFitScore: Encodable {
        struct Dimension: Encodable {
            let name: String
            let score: Int
            let rationale: String?
        }

        struct Requirement: Encodable {
            let requirement: String
            /// "required" / "preferred" — how the job weighted it ("unknown" on legacy scores).
            let kind: String
            /// "met" / "partial" / "missing".
            let status: String
            let evidence: String
        }

        let resumeID: String?
        let resumeName: String?
        let resumeActive: Bool
        let score: Int?
        let status: String
        let model: String?
        let scoredAt: String?
        let reflectsPreviousResumeVersion: Bool
        let dimensions: [Dimension]
        let requirements: [Requirement]

        enum CodingKeys: String, CodingKey {
            case score, status, model, dimensions, requirements
            case resumeID = "resume_id"
            case resumeName = "resume_name"
            case resumeActive = "resume_active"
            case scoredAt = "scored_at"
            case reflectsPreviousResumeVersion = "reflects_previous_resume_version"
        }
    }

    private struct MCPJobDetail: Encodable {
        let jobNumber: Int?
        let jobID: String
        let status: String
        let extractionStatus: String
        let extractionError: String?
        let company: String?
        let title: String?
        let location: String?
        let remoteType: String?
        let salaryMin: Int?
        let salaryMax: Int?
        let salaryNote: String?
        let rating: Int?
        let pageTitle: String?
        let sourceURL: String?
        let capturedAt: String?
        let createdAt: String
        let selectedText: String?
        let visibleText: String?
        let employmentType: String?
        let seniority: String?
        let duplicateOfJobID: String?
        let events: [MCPJobEvent]
        let fitScore: Int?
        let fitStatus: String?
        let fitScores: [MCPFitScore]
        let salaryCurrency: String?
        let salaryHourlyMin: Double?
        let salaryHourlyMax: Double?
        let meetsCriteria: Bool?
        let appliedAt: String?
        let updatedAt: String?
        let unread: Bool
        let lastOpenedAt: String?
        let applicationURL: String?
        let cleanedDescription: String?
        let userNote: String?
        let canonicalURL: String?
        let summary: String?
        let requirements: [String]
        let niceToHaves: [String]
        let skills: [String]
        let extractedAt: String?
        let extractionModel: String?
        let extractionConfidence: Double?
        let manuallyOverriddenFields: [String]
        let duplicateConfidence: Double?

        struct MCPJobEvent: Encodable {
            let eventType: String
            let note: String?
            let occurredAt: String
            enum CodingKeys: String, CodingKey {
                case eventType = "event_type"
                case note
                case occurredAt = "occurred_at"
            }
        }

        enum CodingKeys: String, CodingKey {
            case jobNumber = "job_number"
            case jobID = "job_id"
            case status
            case extractionStatus = "extraction_status"
            case extractionError = "extraction_error"
            case company, title, location
            case remoteType = "remote_type"
            case salaryMin = "salary_min"
            case salaryMax = "salary_max"
            case salaryNote = "salary_note"
            case rating
            case pageTitle = "page_title"
            case sourceURL = "source_url"
            case capturedAt = "captured_at"
            case createdAt = "created_at"
            case selectedText = "selected_text"
            case visibleText = "visible_text"
            case employmentType = "employment_type"
            case seniority
            case duplicateOfJobID = "duplicate_of_job_id"
            case events
            case fitScore = "fit_score"
            case fitStatus = "fit_status"
            case fitScores = "fit_scores"
            case salaryCurrency = "salary_currency"
            case salaryHourlyMin = "salary_hourly_min"
            case salaryHourlyMax = "salary_hourly_max"
            case meetsCriteria = "meets_criteria"
            case appliedAt = "applied_at"
            case updatedAt = "updated_at"
            case unread
            case lastOpenedAt = "last_opened_at"
            case applicationURL = "application_url"
            case cleanedDescription = "cleaned_description"
            case userNote = "user_note"
            case canonicalURL = "canonical_url"
            case summary, requirements, skills
            case niceToHaves = "nice_to_haves"
            case extractedAt = "extracted_at"
            case extractionModel = "extraction_model"
            case extractionConfidence = "extraction_confidence"
            case manuallyOverriddenFields = "manually_overridden_fields"
            case duplicateConfidence = "duplicate_confidence"
        }
    }

    /// Builds the full job payload. Split from the route so the handler stays inside the
    /// function-length limit as the exposed metadata grew.
    private func jobDetailPayload(_ r: JobDetailRecord, includeRawText: Bool) -> MCPJobDetail {
        MCPJobDetail(
            jobNumber: r.jobNumber,
            jobID: r.id,
            status: r.status.rawValue,
            extractionStatus: r.extractionStatus.rawValue,
            extractionError: r.extractionError,
            company: r.company,
            title: r.title,
            location: r.location,
            remoteType: r.remoteType?.rawValue,
            salaryMin: r.salaryMin,
            salaryMax: r.salaryMax,
            salaryNote: r.salaryNote,
            rating: r.rating,
            pageTitle: r.pageTitle,
            sourceURL: r.sourceURL,
            capturedAt: formatDate(r.capturedAt),
            createdAt: formatDate(r.createdAt),
            selectedText: includeRawText ? r.selectedText : nil,
            visibleText: includeRawText ? r.visibleText : nil,
            employmentType: r.employmentType,
            seniority: r.seniority,
            duplicateOfJobID: r.duplicateOfJobID,
            events: r.events.map {
                MCPJobDetail.MCPJobEvent(
                    eventType: $0.eventType, note: $0.note, occurredAt: formatDate($0.occurredAt)
                )
            },
            fitScore: r.fitScore,
            fitStatus: r.fitStatus.rawValue,
            fitScores: r.fitScores.map { fit in
                MCPFitScore(
                    resumeID: fit.resumeID,
                    resumeName: fit.resumeName,
                    resumeActive: fit.resumeActive,
                    score: fit.score,
                    status: fit.status.rawValue,
                    model: fit.model,
                    scoredAt: formatDate(fit.scoredAt),
                    reflectsPreviousResumeVersion: fit.reflectsPreviousResumeVersion,
                    dimensions: fit.dimensions.map {
                        MCPFitScore.Dimension(name: $0.name, score: $0.score, rationale: $0.rationale)
                    },
                    requirements: fit.requirementAssessments.map {
                        MCPFitScore.Requirement(
                            requirement: $0.requirement, kind: $0.kind,
                            status: $0.status, evidence: $0.evidence
                        )
                    }
                )
            },
            salaryCurrency: r.salaryCurrency,
            salaryHourlyMin: r.salaryHourlyMin,
            salaryHourlyMax: r.salaryHourlyMax,
            meetsCriteria: r.meetsCriteria,
            appliedAt: formatDate(r.appliedAt),
            updatedAt: formatDate(r.updatedAt as Date?),
            unread: r.unread,
            lastOpenedAt: formatDate(r.lastOpenedAt),
            applicationURL: r.applicationURL,
            cleanedDescription: r.cleanedDescription,
            userNote: r.userNote,
            canonicalURL: r.canonicalURL,
            summary: r.summary,
            requirements: r.requirements,
            niceToHaves: r.niceToHaves,
            skills: r.skills,
            extractedAt: formatDate(r.extractedAt),
            extractionModel: r.extractionModel,
            extractionConfidence: r.extractionConfidence,
            manuallyOverriddenFields: r.manuallyOverriddenFields,
            duplicateConfidence: r.duplicateConfidence
        )
    }

    func handleMCPJobGet(_ request: HTTPRequest, jobService: JobService) async -> HTTPResponse {
        guard let req = try? request.decodeBody(as: MCPJobGetRequest.self) else {
            return HTTPResponse.error("job_number or job_id required")
        }

        do {
            // TASK-464: resolve by job_id (back-compat) or job_number (preferred).
            let record: JobDetailRecord?
            if let jobId = req.jobId, !jobId.isEmpty {
                record = try await jobService.getJob(byID: jobId)
            } else if let num = req.jobNumber {
                record = try await jobService.getJob(byNumber: num)
            } else {
                return HTTPResponse.error("job_number or job_id required")
            }
            guard let r = record else {
                return HTTPResponse.error("job not found", code: 404)
            }

            let detail = jobDetailPayload(r, includeRawText: req.includeRawText == true)
            return HTTPResponse.ok(detail)
        } catch {
            return HTTPResponse.error(safeServerError(error, context: "handleMCPJobGet"), code: 500)
        }
    }
#endif
