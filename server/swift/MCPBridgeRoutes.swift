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
        enum CodingKeys: String, CodingKey {
            case jobNumber = "job_number"
        }
    }

    private struct MCPJobUpdateRequest: Decodable {
        let jobNumber: Int
        let company: String?
        let title: String?
        let location: String?
        let salaryMin: Int?
        let salaryMax: Int?
        let salaryNote: String?
        enum CodingKeys: String, CodingKey {
            case jobNumber = "job_number"
            case company, title, location
            case salaryMin = "salary_min"
            case salaryMax = "salary_max"
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

        enum CodingKeys: String, CodingKey {
            case id, url, name, state, note
            case intervalDays = "interval_days"
            case createdAt = "created_at"
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

        // Authenticate via X-MCP-Token header
        let provided = request.headers["x-mcp-token"] ?? ""
        guard provided == mcpToken else {
            return HTTPResponse.error("Unauthorized", code: 401)
        }

        switch request.path {
        case "/mcp/jobs/list":
            return await handleMCPJobsList(request, store: store)
        case "/mcp/jobs/get":
            return await handleMCPJobGet(request, store: store)
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
            return await handleMCPSitesList(request, store: store)
        case "/mcp/sites/add":
            return await handleMCPSiteAdd(request, siteService: siteService)
        case "/mcp/sites/update":
            return await handleMCPSiteUpdate(request, siteService: siteService)
        case "/mcp/sites/delete":
            return await handleMCPSiteDelete(request, siteService: siteService)
        case "/mcp/snapshot":
            return await handleMCPSnapshot(request, store: store)
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

    private func handleMCPJobsList(_ request: HTTPRequest, store: BackgroundStore) async -> HTTPResponse {
        let req = try? request.decodeBody(as: MCPJobsListRequest.self)
        let limit = req?.limit ?? 50
        let statusFilter = req?.status

        do {
            let jobs: [Job]
            if let statusFilter, let jobStatus = JobStatus(rawValue: statusFilter) {
                let descriptor = FetchDescriptor<Job>(
                    predicate: #Predicate { $0.status == jobStatus },
                    sortBy: [SortDescriptor(\Job.createdAt, order: .reverse)]
                )
                jobs = try await store.fetch(descriptor)
            } else {
                var descriptor = FetchDescriptor<Job>(
                    sortBy: [SortDescriptor(\Job.createdAt, order: .reverse)]
                )
                descriptor.fetchLimit = limit
                jobs = try await store.fetch(descriptor)
            }

            let summaries = Array(jobs.prefix(limit)).map { job in
                MCPJobSummary(
                    jobNumber: job.jobNumber,
                    jobID: job.id,
                    status: job.status.rawValue,
                    extractionStatus: job.extractionStatus.rawValue,
                    company: job.company,
                    title: job.title,
                    location: job.location,
                    remoteType: job.remoteType?.rawValue,
                    salaryMin: job.salaryMin,
                    salaryMax: job.salaryMax,
                    salaryNote: job.salaryNote,
                    rating: job.rating,
                    pageTitle: job.capture?.pageTitle,
                    sourceURL: job.capture?.url,
                    capturedAt: formatDate(job.capture?.createdAt),
                    createdAt: formatDate(job.createdAt)
                )
            }
            return HTTPResponse.ok(summaries)
        } catch {
            return HTTPResponse.error(error.localizedDescription, code: 500)
        }
    }

    private func handleMCPJobGet(_ request: HTTPRequest, store: BackgroundStore) async -> HTTPResponse {
        guard let req = try? request.decodeBody(as: MCPJobGetRequest.self) else {
            return HTTPResponse.error("job_number required")
        }

        do {
            let jobNumber = req.jobNumber
            let descriptor = FetchDescriptor<Job>(
                predicate: #Predicate { $0.jobNumber == jobNumber }
            )
            let jobs = try await store.fetch(descriptor)
            guard let job = jobs.first else {
                return HTTPResponse.error("job not found", code: 404)
            }

            let detail = MCPJobDetail(
                jobNumber: job.jobNumber,
                jobID: job.id,
                status: job.status.rawValue,
                extractionStatus: job.extractionStatus.rawValue,
                extractionError: job.extractionError,
                company: job.company,
                title: job.title,
                location: job.location,
                remoteType: job.remoteType?.rawValue,
                salaryMin: job.salaryMin,
                salaryMax: job.salaryMax,
                salaryNote: job.salaryNote,
                rating: job.rating,
                pageTitle: job.capture?.pageTitle,
                sourceURL: job.capture?.url,
                capturedAt: formatDate(job.capture?.createdAt),
                createdAt: formatDate(job.createdAt),
                selectedText: job.capture?.selectedText,
                visibleText: job.capture?.visibleText
            )
            return HTTPResponse.ok(detail)
        } catch {
            return HTTPResponse.error(error.localizedDescription, code: 500)
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
            return HTTPResponse.error(error.localizedDescription, code: 500)
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
                location: req.location.map { Optional($0) } ?? .none
            )
            return HTTPResponse.ok(MCPOKResponse(ok: true))
        } catch {
            return HTTPResponse.error(error.localizedDescription, code: 500)
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
            return HTTPResponse.error(error.localizedDescription, code: 500)
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
            return HTTPResponse.error(error.localizedDescription, code: 500)
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
            return HTTPResponse.error(error.localizedDescription, code: 500)
        }
    }

    private func handleMCPSitesList(_: HTTPRequest, store: BackgroundStore) async -> HTTPResponse {
        do {
            let sites = try await store.fetch(FetchDescriptor<Site>(
                sortBy: [SortDescriptor(\Site.createdAt, order: .reverse)]
            ))
            let summaries = sites.map { site in
                MCPSiteSummary(
                    id: site.id,
                    url: site.url,
                    name: site.companyName,
                    state: site.state.rawValue,
                    intervalDays: site.intervalDays,
                    note: site.note,
                    createdAt: formatDate(site.createdAt)
                )
            }
            return HTTPResponse.ok(summaries)
        } catch {
            return HTTPResponse.error(error.localizedDescription, code: 500)
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
            return HTTPResponse.error(error.localizedDescription, code: 500)
        }
    }

    private func handleMCPSiteUpdate(_ request: HTTPRequest, siteService: SiteService) async -> HTTPResponse {
        guard let req = try? request.decodeBody(as: MCPSiteUpdateRequest.self) else {
            return HTTPResponse.error("Invalid JSON body")
        }

        let state: SiteState? = if let stateStr = req.state {
            SiteState(rawValue: stateStr)
        } else {
            nil
        }

        do {
            try await siteService.updateSite(
                id: req.id,
                name: req.name,
                excludeState: state,
                intervalDays: req.intervalDays
            )
            return HTTPResponse.ok(MCPOKResponse(ok: true))
        } catch {
            return HTTPResponse.error(error.localizedDescription, code: 500)
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
            return HTTPResponse.error(error.localizedDescription, code: 500)
        }
    }

    private func handleMCPSnapshot(_: HTTPRequest, store: BackgroundStore) async -> HTTPResponse {
        do {
            let jobs = try await store.fetch(FetchDescriptor<Job>())
            let sites = try await store.fetch(FetchDescriptor<Site>())

            var statusCounts: [String: Int] = [:]
            for job in jobs {
                let key = job.status.rawValue
                statusCounts[key, default: 0] += 1
            }

            let snapshot = MCPSnapshotResponse(
                jobsTotal: jobs.count,
                sitesTotal: sites.count,
                statusCounts: statusCounts
            )
            return HTTPResponse.ok(snapshot)
        } catch {
            return HTTPResponse.error(error.localizedDescription, code: 500)
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
