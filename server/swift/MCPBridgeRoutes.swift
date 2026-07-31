#if !MAS_BUILD
    import Foundation
    import JobhuntCore
    import SwiftData

    /// Shared by both MCP route files, so timestamps are formatted identically.
    let mcpISOFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    // MARK: - MCP request/response types

    /// Internal, not private: decoded by the extracted job_get route.
    struct MCPJobGetRequest: Decodable {
        let jobNumber: Int?
        let jobId: String?
        let includeRawText: Bool?
        enum CodingKeys: String, CodingKey {
            case jobNumber = "job_number"
            case jobId = "job_id"
            case includeRawText = "include_raw_text"
        }
    }

    private struct MCPJobUpdateRequest: Decodable {
        let jobNumber: Int?
        let jobId: String?
        let company: String?
        let title: String?
        let location: String?
        let salaryMin: Int?
        let salaryMax: Int?
        let salaryCurrency: String?
        let salaryNote: String?
        enum CodingKeys: String, CodingKey {
            case jobNumber = "job_number"
            case jobId = "job_id"
            case company, title, location
            case salaryMin = "salary_min"
            case salaryMax = "salary_max"
            case salaryCurrency = "salary_currency"
            case salaryNote = "salary_note"
        }
    }

    private struct MCPJobStatusRequest: Decodable {
        let jobNumber: Int?
        let jobId: String?
        let status: String
        enum CodingKeys: String, CodingKey {
            case jobNumber = "job_number"
            case jobId = "job_id"
            case status
        }
    }

    private struct MCPJobNoteRequest: Decodable {
        let jobNumber: Int?
        let jobId: String?
        let note: String
        enum CodingKeys: String, CodingKey {
            case jobNumber = "job_number"
            case jobId = "job_id"
            case note
        }
    }

    private struct MCPJobRerunRequest: Decodable {
        let jobNumber: Int?
        let jobId: String?
        enum CodingKeys: String, CodingKey {
            case jobNumber = "job_number"
            case jobId = "job_id"
        }
    }

    private struct MCPSiteAddRequest: Decodable {
        let url: String
        let name: String?
        // TASK-464: Electron parity — richer add_site fields.
        let state: String?
        let intervalDays: Int?
        let note: String?
        let companyWebsite: String?
        let jobsURL: String?
        let companyDescription: String?
        enum CodingKeys: String, CodingKey {
            case url, name, state, note
            case intervalDays = "interval_days"
            case companyWebsite = "company_website"
            case jobsURL = "jobs_url"
            case companyDescription = "company_description"
        }
    }

    private struct MCPSiteUpdateRequest: Decodable {
        let id: String
        let name: String?
        let state: String?
        let intervalDays: Int?
        let note: String?
        let companyWebsite: String?
        let jobsURL: String?
        let companyDescription: String?
        enum CodingKeys: String, CodingKey {
            case id, name, state, note
            case intervalDays = "interval_days"
            case companyWebsite = "company_website"
            case jobsURL = "jobs_url"
            case companyDescription = "company_description"
        }
    }

    private struct MCPSiteDeleteRequest: Decodable {
        let id: String
    }

    private struct MCPOKResponse: Encodable {
        let ok: Bool
    }

    /// Internal, not private: the extracted jobs-list route builds these.
    struct MCPJobSummary: Encodable {
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
        let employmentType: String?
        let seniority: String?
        let duplicateOfJobID: String?
        let fitScore: Int?
        let fitStatus: String?
        let salaryCurrency: String?
        let salaryHourlyMin: Double?
        let salaryHourlyMax: Double?
        /// The stored LOCATION-ONLY verdict. Kept for continuity but rarely what a caller wants:
        /// it reads false for a posting that merely never stated its arrangement, and true for one
        /// that fails the salary floor. Prefer `requirements`.
        let meetsCriteria: Bool?
        /// The composite verdict across location, salary floor and fit floor. Named distinctly from
        /// the extracted `requirements` list, which is a different thing entirely.
        let requirementsVerdict: String?
        let appliedAt: String?
        let updatedAt: String?
        let unread: Bool?

        enum CodingKeys: String, CodingKey {
            case jobNumber = "job_number"
            case jobID = "job_id"
            case status
            case extractionStatus = "extraction_status"
            case fitScore = "fit_score"
            case fitStatus = "fit_status"
            case salaryCurrency = "salary_currency"
            case salaryHourlyMin = "salary_hourly_min"
            case salaryHourlyMax = "salary_hourly_max"
            case meetsCriteria = "meets_criteria"
            case requirementsVerdict = "requirements_verdict"
            case appliedAt = "applied_at"
            case updatedAt = "updated_at"
            case unread
            case company, title, location
            case employmentType = "employment_type"
            case seniority
            case duplicateOfJobID = "duplicate_of_job_id"
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
        let sitesDue: Int
        let statusCounts: [String: Int]
        let extractionStatusCounts: [String: Int]

        enum CodingKeys: String, CodingKey {
            case jobsTotal = "jobs_total"
            case sitesTotal = "sites_total"
            case sitesDue = "sites_due"
            case statusCounts = "status_counts"
            case extractionStatusCounts = "extraction_status_counts"
        }
    }

    // MARK: - MCP bridge routing (extends JobhuntServer routing)

    /// Call this from JobhuntServer.routeRequest to handle /mcp/* endpoints.
    /// Returns nil if the path is not a recognised MCP route.
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
        // Reject missing or wrong tokens. Use a constant-time compare so a timing side-channel
        // can't leak the token's length/prefix (TASK-474).
        let provided = request.headers["x-mcp-token"] ?? ""
        guard !provided.isEmpty, constantTimeEquals(provided, mcpToken) else {
            return HTTPResponse.error("Unauthorized", code: 401)
        }

        // TASK-434: every /mcp/* tool call is a POST (the MCP helper sets httpMethod = "POST" for
        // all routes). Reject any other method with a 405 + safe JSON error, so the route surface
        // matches the helper contract.
        guard request.method == "POST" else {
            return HTTPResponse.error("Method not allowed; MCP routes require POST", code: 405)
        }

        switch request.path {
        case "/mcp/jobs/list":
            return await handleMCPJobsList(request, jobService: jobService, store: store)
        case "/mcp/jobs/get":
            return await handleMCPJobGet(request, jobService: jobService, store: store)
        case "/mcp/captures/add":
            return await handleMCPCaptureAdd(request, jobService: jobService)
        case "/mcp/jobs/update":
            return await handleMCPJobUpdate(request, jobService: jobService, store: store)
        case "/mcp/jobs/status":
            return await handleMCPJobStatus(request, jobService: jobService, store: store)
        case "/mcp/jobs/note":
            return await handleMCPJobNote(request, jobService: jobService, store: store)
        case "/mcp/jobs/mark-applied":
            return await handleMCPMarkApplied(request, jobService: jobService)
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

    func formatDate(_ date: Date?) -> String? {
        guard let date else { return nil }
        return mcpISOFormatter.string(from: date)
    }

    func formatDate(_ date: Date) -> String {
        mcpISOFormatter.string(from: date)
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

        // Resolve structured data from either the typed `structured_data_json` field or the raw
        // `structured_data` array on the body — one shared policy with /captures (TASK-559) so MCP
        // clients sending the extension's capture shape don't silently lose structured metadata.
        let structuredJSON = CaptureRequestParsing.resolveStructuredDataJSON(
            typed: req.structuredDataJSON, rawBody: request.body
        )

        let payload = CapturePayload(
            url: url,
            pageTitle: pageTitle,
            selectedText: req.selectedText,
            visibleText: req.visibleText,
            userNote: req.userNote,
            canonicalURL: req.canonicalURL,
            structuredDataJSON: structuredJSON
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
            return captureIngestionErrorResponse(error, context: "handleMCPCaptureAdd")
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
            let jobID = try await resolveJob(jobNumber: req.jobNumber, jobId: req.jobId, store: store)?.id
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
            let jobID = try await resolveJob(jobNumber: req.jobNumber, jobId: req.jobId, store: store)?.id
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
            let jobID = try await resolveJob(jobNumber: req.jobNumber, jobId: req.jobId, store: store)?.id
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
            let jobID = try await resolveJob(jobNumber: req.jobNumber, jobId: req.jobId, store: store)?.id
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
        if let stateStr = req.state, SiteState(rawValue: stateStr) == nil {
            let valid = SiteState.allCases.map(\.rawValue).joined(separator: ", ")
            return HTTPResponse.error("Unknown site state: '\(stateStr)'; valid values: \(valid)", code: 400)
        }

        do {
            let interval = req.intervalDays.map { max(1, min(365, $0)) }
            let siteID = try await siteService.createSite(
                url: req.url, name: req.name, intervalDays: interval ?? 14
            )
            // Apply the richer fields (state/note/company_website/jobs_url/company_description) via
            // the same update path update_site uses — TASK-464.
            let state = req.state.flatMap { SiteState(rawValue: $0) }
            if state != nil || req.note != nil || req.companyWebsite != nil
                || req.jobsURL != nil || req.companyDescription != nil {
                try await siteService.updateSite(
                    id: siteID,
                    excludeState: state,
                    note: req.note,
                    companyWebsite: req.companyWebsite,
                    jobsURL: req.jobsURL,
                    companyDescription: req.companyDescription
                )
            }
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
                intervalDays: boundedIntervalDays,
                note: req.note,
                companyWebsite: req.companyWebsite,
                jobsURL: req.jobsURL,
                companyDescription: req.companyDescription
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
                sitesDue: snap.sitesDue,
                statusCounts: snap.statusCounts,
                extractionStatusCounts: snap.extractionStatusCounts
            )
            return HTTPResponse.ok(response)
        } catch {
            return HTTPResponse.error(safeServerError(error, context: "handleMCPSnapshot"), code: 500)
        }
    }

    // MARK: - Helpers

    /// Resolve a job by `job_id` (internal id string — Electron back-compat) or `job_number`
    /// (preferred), returning both identifiers (TASK-464). Returns nil if neither is given or no
    /// job matches.
    private func resolveJob(jobNumber: Int?, jobId: String?, store: BackgroundStore) async throws
        -> (id: String, number: Int?)? {
        if let jobId, !jobId.isEmpty {
            let jobs = try await store.fetch(FetchDescriptor<Job>(predicate: #Predicate { $0.id == jobId }))
            return jobs.first.map { ($0.id, $0.jobNumber) }
        }
        if let jobNumber {
            let jobs = try await store.fetch(FetchDescriptor<Job>(predicate: #Predicate { $0.jobNumber == jobNumber }))
            return jobs.first.map { ($0.id, $0.jobNumber) }
        }
        return nil
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

    /// Constant-time equality for the MCP token (TASK-474). Accumulates byte differences without an
    /// early exit so comparison time doesn't reveal the token's length or matching prefix.
    private func constantTimeEquals(_ a: String, _ b: String) -> Bool {
        let aBytes = Array(a.utf8)
        let bBytes = Array(b.utf8)
        var diff = aBytes.count ^ bBytes.count
        let maxLen = max(aBytes.count, bBytes.count)
        for i in 0 ..< maxLen {
            let av = i < aBytes.count ? aBytes[i] : 0
            let bv = i < bBytes.count ? bBytes[i] : 0
            diff |= Int(av ^ bv)
        }
        return diff == 0
    }

#endif // !MAS_BUILD
