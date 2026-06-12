// swiftlint:disable file_length
#if !MAS_BUILD
    import Foundation
    import JobhuntCore
    import SwiftData

    // MARK: - MCP request/response types

    private struct MCPJobsListRequest: Decodable {
        let status: String?
        let limit: Int?
    }

    private struct MCPJobGetRequest: Decodable {
        let jobNumber: Int
        let includeRawText: Bool?
        enum CodingKeys: String, CodingKey {
            case jobNumber = "job_number"
            case includeRawText = "include_raw_text"
        }
    }

    private struct MCPJobUpdateRequest: Decodable {
        let jobNumber: Int
        let company: String?
        let title: String?
        let location: String?
        let salaryMin: Int?
        let salaryMax: Int?
        let salaryCurrency: String?
        let salaryNote: String?
        enum CodingKeys: String, CodingKey {
            case jobNumber = "job_number"
            case company, title, location
            case salaryMin = "salary_min"
            case salaryMax = "salary_max"
            case salaryCurrency = "salary_currency"
            case salaryNote = "salary_note"
        }
    }

    private struct MCPJobStatusRequest: Decodable {
        let jobNumber: Int
        let status: String
        enum CodingKeys: String, CodingKey {
            case jobNumber = "job_number"
            case status
        }
    }

    private struct MCPJobNoteRequest: Decodable {
        let jobNumber: Int
        let note: String
        enum CodingKeys: String, CodingKey {
            case jobNumber = "job_number"
            case note
        }
    }

    private struct MCPJobRerunRequest: Decodable {
        let jobNumber: Int
        enum CodingKeys: String, CodingKey {
            case jobNumber = "job_number"
        }
    }

    private struct MCPSiteAddRequest: Decodable {
        let url: String
        let name: String?
    }

    private struct MCPSiteUpdateRequest: Decodable {
        let id: String
        let name: String?
        let state: String?
        let intervalDays: Int?
        enum CodingKeys: String, CodingKey {
            case id, name, state
            case intervalDays = "interval_days"
        }
    }

    private struct MCPSiteDeleteRequest: Decodable {
        let id: String
    }

    private struct MCPOKResponse: Encodable {
        let ok: Bool
    }

    private struct MCPJobSummary: Encodable {
        let jobNumber: Int?
        let jobID: String
        let status: String
        let extractionStatus: String
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

        enum CodingKeys: String, CodingKey {
            case jobNumber = "job_number"
            case jobID = "job_id"
            case status
            case extractionStatus = "extraction_status"
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
        }
    }

    private struct MCPSiteSummary: Encodable {
        let id: String
        let url: String
        let name: String?
        let state: String
        let intervalDays: Int
        let note: String
        let createdAt: String
        let nextReviewAt: String?
        let lastReviewedAt: String?

        enum CodingKeys: String, CodingKey {
            case id, url, name, state, note
            case intervalDays = "interval_days"
            case createdAt = "created_at"
            case nextReviewAt = "next_review_at"
            case lastReviewedAt = "last_reviewed_at"
        }
    }

    private struct MCPSnapshotResponse: Encodable {
        let jobsTotal: Int
        let sitesTotal: Int
        let statusCounts: [String: Int]

        enum CodingKeys: String, CodingKey {
            case jobsTotal = "jobs_total"
            case sitesTotal = "sites_total"
            case statusCounts = "status_counts"
        }
    }

    // MARK: - MCP bridge routing (extends JobhuntServer routing)

    // Call this from JobhuntServer.routeRequest to handle /mcp/* endpoints.
    // Returns nil if the path is not a recognised MCP route.
    // swiftlint:disable:next cyclomatic_complexity
    func routeMCPRequest(
        _ request: HTTPRequest,
        jobService: JobService,
        siteService: SiteService,
        store: BackgroundStore,
        mcpToken: String
    ) async -> HTTPResponse? {
        // Only handle /mcp/ paths
        guard request.path.hasPrefix("/mcp/") else { return nil }

        // Fail closed: an empty server token means MCP is not yet configured.
        guard !mcpToken.isEmpty else {
            return HTTPResponse.error("MCP not configured", code: 503)
        }
        // Reject missing or wrong tokens.
        let provided = request.headers["x-mcp-token"] ?? ""
        guard !provided.isEmpty, provided == mcpToken else {
            return HTTPResponse.error("Unauthorized", code: 401)
        }

        switch request.path {
        case "/mcp/jobs/list":
            return await handleMCPJobsList(request, jobService: jobService)
        case "/mcp/jobs/get":
            return await handleMCPJobGet(request, jobService: jobService)
        case "/mcp/captures/add":
            return await handleMCPCaptureAdd(request, jobService: jobService)
        case "/mcp/jobs/update":
            return await handleMCPJobUpdate(request, jobService: jobService, store: store)
        case "/mcp/jobs/status":
            return await handleMCPJobStatus(request, jobService: jobService, store: store)
        case "/mcp/jobs/note":
            return await handleMCPJobNote(request, jobService: jobService, store: store)
        case "/mcp/jobs/rerun":
            return await handleMCPJobRerun(request, jobService: jobService, store: store)
        case "/mcp/sites/list":
            return await handleMCPSitesList(request, siteService: siteService)
        case "/mcp/sites/add":
            return await handleMCPSiteAdd(request, siteService: siteService)
        case "/mcp/sites/update":
            return await handleMCPSiteUpdate(request, siteService: siteService)
        case "/mcp/sites/delete":
            return await handleMCPSiteDelete(request, siteService: siteService)
        case "/mcp/snapshot":
            return await handleMCPSnapshot(request, jobService: jobService)
        default:
            return HTTPResponse.error("MCP route not found", code: 404)
        }
    }

    // MARK: - Route handlers

    private let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private func formatDate(_ date: Date?) -> String? {
        guard let date else { return nil }
        return isoFormatter.string(from: date)
    }

    private func formatDate(_ date: Date) -> String {
        isoFormatter.string(from: date)
    }

    private let mcpJobsListMinLimit = 1
    private let mcpJobsListMaxLimit = 200
    private let mcpJobsListDefaultLimit = 50

    private func handleMCPJobsList(_ request: HTTPRequest, jobService: JobService) async -> HTTPResponse {
        let req = try? request.decodeBody(as: MCPJobsListRequest.self)
        let rawLimit = req?.limit ?? mcpJobsListDefaultLimit
        guard rawLimit >= mcpJobsListMinLimit else {
            return HTTPResponse.error("limit must be at least \(mcpJobsListMinLimit)", code: 400)
        }
        let limit = min(rawLimit, mcpJobsListMaxLimit)
        let statusFilter = req?.status

        if let statusRaw = statusFilter, JobStatus(rawValue: statusRaw) == nil {
            let valid = JobStatus.allCases.map { $0.rawValue }.joined(separator: ", ")
            return HTTPResponse.error("invalid status '\(statusRaw)'; valid values: \(valid)", code: 400)
        }

        do {
            let records = try await jobService.listJobs(status: statusFilter, limit: limit)
            let summaries = records.map { r in
                MCPJobSummary(
                    jobNumber: r.jobNumber,
                    jobID: r.id,
                    status: r.status.rawValue,
                    extractionStatus: r.extractionStatus.rawValue,
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
                    createdAt: formatDate(r.createdAt)
                )
            }
            return HTTPResponse.ok(summaries)
        } catch {
            return HTTPResponse.error(safeServerError(error, context: "handleMCPJobsList"), code: 500)
        }
    }

    private func handleMCPJobGet(_ request: HTTPRequest, jobService: JobService) async -> HTTPResponse {
        guard let req = try? request.decodeBody(as: MCPJobGetRequest.self) else {
            return HTTPResponse.error("job_number required")
        }

        do {
            guard let r = try await jobService.getJob(byNumber: req.jobNumber) else {
                return HTTPResponse.error("job not found", code: 404)
            }

            let detail = MCPJobDetail(
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
                selectedText: req.includeRawText == true ? r.selectedText : nil,
                visibleText: req.includeRawText == true ? r.visibleText : nil
            )
            return HTTPResponse.ok(detail)
        } catch {
            return HTTPResponse.error(safeServerError(error, context: "handleMCPJobGet"), code: 500)
        }
    }

    private func handleMCPCaptureAdd(_ request: HTTPRequest, jobService: JobService) async -> HTTPResponse {
        guard let req = try? request.decodeBody(as: MCPCaptureIngestRequest.self) else {
            return HTTPResponse.error("Invalid JSON body")
        }

        let url = req.url.trimmingCharacters(in: .whitespaces)
        let pageTitle = req.pageTitle.trimmingCharacters(in: .whitespaces)
        if url.isEmpty || pageTitle.isEmpty {
            return HTTPResponse.error("url and page_title required")
        }

        let payload = CapturePayload(
            url: url,
            pageTitle: pageTitle,
            selectedText: req.selectedText,
            visibleText: req.visibleText,
            userNote: req.userNote,
            canonicalURL: req.canonicalURL,
            structuredDataJSON: req.structuredDataJSON
        )

        do {
            let result = try await jobService.ingestCapture(payload)
            struct CaptureResult: Encodable {
                let ok: Bool
                let captureID: String
                let jobNumber: Int
                let duplicate: Bool
                enum CodingKeys: String, CodingKey {
                    case ok
                    case captureID = "capture_id"
                    case jobNumber = "job_number"
                    case duplicate
                }
            }
            return HTTPResponse.ok(CaptureResult(
                ok: true,
                captureID: result.captureID,
                jobNumber: result.jobNumber,
                duplicate: result.isDuplicate
            ))
        } catch {
            return HTTPResponse.error(safeServerError(error, context: "handleMCPCaptureAdd"), code: 500)
        }
    }

    private func handleMCPJobUpdate(
        _ request: HTTPRequest,
        jobService: JobService,
        store: BackgroundStore
    ) async -> HTTPResponse {
        guard let req = try? request.decodeBody(as: MCPJobUpdateRequest.self) else {
            return HTTPResponse.error("Invalid JSON body")
        }

        do {
            let jobID = try await resolveJobID(jobNumber: req.jobNumber, store: store)
            guard let jobID else {
                return HTTPResponse.error("job not found", code: 404)
            }
            try await jobService.updateJobFields(
                jobID: jobID,
                company: req.company.map { Optional($0) } ?? .none,
                title: req.title.map { Optional($0) } ?? .none,
                location: req.location.map { Optional($0) } ?? .none,
                salaryMin: req.salaryMin.map { Optional($0) } ?? .none,
                salaryMax: req.salaryMax.map { Optional($0) } ?? .none,
                salaryCurrency: req.salaryCurrency.map { Optional($0) } ?? .none,
                salaryNote: req.salaryNote.map { Optional($0) } ?? .none
            )
            return HTTPResponse.ok(MCPOKResponse(ok: true))
        } catch {
            return HTTPResponse.error(safeServerError(error, context: "handleMCPJobUpdate"), code: 500)
        }
    }

    private func handleMCPJobStatus(
        _ request: HTTPRequest,
        jobService: JobService,
        store: BackgroundStore
    ) async -> HTTPResponse {
        guard let req = try? request.decodeBody(as: MCPJobStatusRequest.self) else {
            return HTTPResponse.error("Invalid JSON body")
        }
        guard let status = JobStatus(rawValue: req.status) else {
            return HTTPResponse.error("invalid status value")
        }

        do {
            let jobID = try await resolveJobID(jobNumber: req.jobNumber, store: store)
            guard let jobID else {
                return HTTPResponse.error("job not found", code: 404)
            }
            try await jobService.setStatus(status, for: jobID)
            return HTTPResponse.ok(MCPOKResponse(ok: true))
        } catch {
            return HTTPResponse.error(safeServerError(error, context: "handleMCPJobStatus"), code: 500)
        }
    }

    private func handleMCPJobNote(
        _ request: HTTPRequest,
        jobService: JobService,
        store: BackgroundStore
    ) async -> HTTPResponse {
        guard let req = try? request.decodeBody(as: MCPJobNoteRequest.self) else {
            return HTTPResponse.error("Invalid JSON body")
        }

        do {
            let jobID = try await resolveJobID(jobNumber: req.jobNumber, store: store)
            guard let jobID else {
                return HTTPResponse.error("job not found", code: 404)
            }
            try await jobService.addNote(req.note, to: jobID)
            return HTTPResponse.ok(MCPOKResponse(ok: true))
        } catch {
            return HTTPResponse.error(safeServerError(error, context: "handleMCPJobNote"), code: 500)
        }
    }

    private func handleMCPJobRerun(
        _ request: HTTPRequest,
        jobService: JobService,
        store: BackgroundStore
    ) async -> HTTPResponse {
        guard let req = try? request.decodeBody(as: MCPJobRerunRequest.self) else {
            return HTTPResponse.error("Invalid JSON body")
        }

        do {
            let jobID = try await resolveJobID(jobNumber: req.jobNumber, store: store)
            guard let jobID else {
                return HTTPResponse.error("job not found", code: 404)
            }
            try await jobService.resetExtraction(jobID: jobID)
            return HTTPResponse.ok(MCPOKResponse(ok: true))
        } catch {
            return HTTPResponse.error(safeServerError(error, context: "handleMCPJobRerun"), code: 500)
        }
    }

    private func handleMCPSitesList(_: HTTPRequest, siteService: SiteService) async -> HTTPResponse {
        do {
            let records = try await siteService.listSites()
            let summaries = records.map { r in
                MCPSiteSummary(
                    id: r.id,
                    url: r.url,
                    name: r.companyName,
                    state: r.state.rawValue,
                    intervalDays: r.intervalDays,
                    note: r.note,
                    createdAt: formatDate(r.createdAt),
                    nextReviewAt: r.nextReviewAt.map { formatDate($0) } ?? nil,
                    lastReviewedAt: r.lastReviewedAt.map { formatDate($0) } ?? nil
                )
            }
            return HTTPResponse.ok(summaries)
        } catch {
            return HTTPResponse.error(safeServerError(error, context: "handleMCPSitesList"), code: 500)
        }
    }

    private func handleMCPSiteAdd(_ request: HTTPRequest, siteService: SiteService) async -> HTTPResponse {
        guard let req = try? request.decodeBody(as: MCPSiteAddRequest.self) else {
            return HTTPResponse.error("Invalid JSON body")
        }
        guard !req.url.trimmingCharacters(in: .whitespaces).isEmpty else {
            return HTTPResponse.error("url required")
        }

        do {
            let siteID = try await siteService.createSite(url: req.url, name: req.name)
            struct AddResult: Encodable {
                let ok: Bool
                let id: String
            }
            return HTTPResponse.ok(AddResult(ok: true, id: siteID))
        } catch {
            return HTTPResponse.error(safeServerError(error, context: "handleMCPSiteAdd"), code: 500)
        }
    }

    private func handleMCPSiteUpdate(_ request: HTTPRequest, siteService: SiteService) async -> HTTPResponse {
        guard let req = try? request.decodeBody(as: MCPSiteUpdateRequest.self) else {
            return HTTPResponse.error("Invalid JSON body")
        }

        if let stateStr = req.state, SiteState(rawValue: stateStr) == nil {
            let valid = SiteState.allCases.map(\.rawValue).joined(separator: ", ")
            return HTTPResponse.error("Unknown site state: '\(stateStr)'; valid values: \(valid)", code: 400)
        }
        let state: SiteState? = req.state.flatMap { SiteState(rawValue: $0) }
        let boundedIntervalDays: Int? = req.intervalDays.map { max(1, min(365, $0)) }

        do {
            try await siteService.updateSite(
                id: req.id,
                name: req.name,
                excludeState: state,
                intervalDays: boundedIntervalDays
            )
            return HTTPResponse.ok(MCPOKResponse(ok: true))
        } catch {
            return HTTPResponse.error(safeServerError(error, context: "handleMCPSiteUpdate"), code: 500)
        }
    }

    private func handleMCPSiteDelete(_ request: HTTPRequest, siteService: SiteService) async -> HTTPResponse {
        guard let req = try? request.decodeBody(as: MCPSiteDeleteRequest.self) else {
            return HTTPResponse.error("Invalid JSON body")
        }

        do {
            try await siteService.deleteSite(id: req.id)
            return HTTPResponse.ok(MCPOKResponse(ok: true))
        } catch {
            return HTTPResponse.error(safeServerError(error, context: "handleMCPSiteDelete"), code: 500)
        }
    }

    private func handleMCPSnapshot(_: HTTPRequest, jobService: JobService) async -> HTTPResponse {
        do {
            let snap = try await jobService.workflowSnapshot()
            let response = MCPSnapshotResponse(
                jobsTotal: snap.jobsTotal,
                sitesTotal: snap.sitesTotal,
                statusCounts: snap.statusCounts
            )
            return HTTPResponse.ok(response)
        } catch {
            return HTTPResponse.error(safeServerError(error, context: "handleMCPSnapshot"), code: 500)
        }
    }

    // MARK: - Helpers

    private func resolveJobID(jobNumber: Int, store: BackgroundStore) async throws -> String? {
        let descriptor = FetchDescriptor<Job>(
            predicate: #Predicate { $0.jobNumber == jobNumber }
        )
        let jobs = try await store.fetch(descriptor)
        return jobs.first?.id
    }

    /// Capture ingestion request body for MCP bridge (mirrors CapturePayload fields).
    private struct MCPCaptureIngestRequest: Decodable {
        let url: String
        let pageTitle: String
        let selectedText: String?
        let visibleText: String?
        let userNote: String?
        let canonicalURL: String?
        let structuredDataJSON: String?

        enum CodingKeys: String, CodingKey {
            case url
            case pageTitle = "page_title"
            case selectedText = "selected_text"
            case visibleText = "visible_text"
            case userNote = "user_note"
            case canonicalURL = "canonical_url"
            case structuredDataJSON = "structured_data_json"
        }
    }

#endif // !MAS_BUILD
