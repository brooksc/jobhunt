#if !MAS_BUILD
    import Foundation
    import JobhuntCore
    import SwiftData

    private struct MCPMarkAppliedRequest: Decodable {
        let url: String
        let company: String?
        let title: String?
        let pageTitle: String?
        let applicationURL: String?
        let note: String?
        enum CodingKeys: String, CodingKey {
            case url, company, title, note
            case pageTitle = "page_title"
            case applicationURL = "application_url"
        }
    }

    /// Mark a posting Applied by URL, creating a minimal record when it was never captured (TASK-618).
    func handleMCPMarkApplied(_ request: HTTPRequest, jobService: JobService) async -> HTTPResponse {
        guard let req = try? request.decodeBody(as: MCPMarkAppliedRequest.self) else {
            return HTTPResponse.error("Invalid JSON body")
        }
        struct MarkAppliedResponse: Encodable {
            let ok: Bool
            let jobId: String
            let jobNumber: Int?
            let company: String?
            let title: String?
            let previousStatus: String
            let status: String
            let created: Bool
            let alreadyApplied: Bool
            let laterStage: Bool
            let matchedURL: String?
            let appliedAt: String?
            enum CodingKeys: String, CodingKey {
                case ok, company, title, status, created
                case jobId = "job_id"
                case jobNumber = "job_number"
                case previousStatus = "previous_status"
                case alreadyApplied = "already_applied"
                case laterStage = "later_stage"
                case matchedURL = "matched_url"
                case appliedAt = "applied_at"
            }
        }
        do {
            let result = try await jobService.markJobApplied(
                url: req.url, company: req.company, title: req.title, pageTitle: req.pageTitle,
                applicationURL: req.applicationURL, note: req.note
            )
            return HTTPResponse.ok(MarkAppliedResponse(
                ok: true, jobId: result.jobID, jobNumber: result.jobNumber, company: result.company,
                title: result.title, previousStatus: result.previousStatus, status: result.status,
                created: result.created, alreadyApplied: result.alreadyApplied, laterStage: result.laterStage,
                matchedURL: result.matchedURL,
                appliedAt: result.appliedAt.map { ISO8601DateFormatter().string(from: $0) }
            ))
        } catch let error as JobService.MarkAppliedError {
            return HTTPResponse.error(error.localizedDescription)
        } catch {
            return HTTPResponse.error(safeServerError(error, context: "handleMCPMarkApplied"))
        }
    }
#endif
