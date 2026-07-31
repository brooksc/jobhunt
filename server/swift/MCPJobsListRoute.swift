#if !MAS_BUILD
    import Foundation
    import JobhuntCore
    import SwiftData

    /// The MCP `jobs_list` route: filtering, offset pagination and the compact projection.
    ///
    /// Split out of MCPBridgeRoutes.swift, which the additions pushed past the file-length limit.
    /// Module scope, matching that file — these are free functions, not members of a type.
    private struct MCPJobsListRequest: Decodable {
        let status: String?
        let limit: Int?
        let offset: Int?
        let query: String?
        let company: String?
        let capturedAfter: String?
        let minSalary: Int?
        let minScore: Int?
        /// "meets" / "not_stated" / "does_not_meet" — the composite verdict, not the stored
        /// location-only flag.
        let requirementsVerdict: String?
        let summary: Bool?
        enum CodingKeys: String, CodingKey {
            case status, limit, offset, query, company, summary
            case requirementsVerdict = "requirements_verdict"
            case capturedAfter = "captured_after"
            case minSalary = "min_salary"
            case minScore = "min_score"
        }
    }

    /// Compact per-job projection for `summary: true`. Full records run ~700 bytes each, so 200 of
    /// them overflow the tool-output budget; this is small enough to page thousands of rows.
    private struct MCPJobSummaryCompact: Encodable {
        let jobNumber: Int?
        let company: String?
        let title: String?
        let status: String
        let location: String?
        let salaryMin: Int?
        let salaryMax: Int?
        let sourceURL: String?
        let fitScore: Int?
        /// Without this the amounts read as USD — four postings in the corpus are EUR/CAD.
        let salaryCurrency: String?
        /// The composite verdict across location, salary floor and fit floor.
        let requirementsVerdict: String?
        enum CodingKeys: String, CodingKey {
            case jobNumber = "job_number"
            case company, title, status, location
            case salaryMin = "salary_min"
            case salaryMax = "salary_max"
            case sourceURL = "source_url"
            case fitScore = "fit_score"
            case salaryCurrency = "salary_currency"
            case requirementsVerdict = "requirements_verdict"
        }
    }

    /// Paged envelope. The bare array this replaces had no way to say "there is more" — a caller
    /// couldn't tell a complete answer from a silently truncated one.
    private struct MCPJobsListResponse<Row: Encodable>: Encodable {
        let jobs: [Row]
        let total: Int
        let offset: Int
        let limit: Int
        let hasMore: Bool
        let nextOffset: Int?
        /// Set when the requested limit exceeded the maximum, so the clamp is never silent.
        let notice: String?
        enum CodingKeys: String, CodingKey {
            case jobs, total, offset, limit, notice
            case hasMore = "has_more"
            case nextOffset = "next_offset"
        }
    }

    private let mcpJobsListMinLimit = 1
    /// Full records are large; 200 already overflows a tool-output budget.
    private let mcpJobsListMaxLimit = 200
    /// The compact projection is roughly an order of magnitude smaller per row, so it can page far
    /// more at once — which is what makes a corpus-wide question answerable in a few calls.
    private let mcpJobsListMaxSummaryLimit = 1000
    private let mcpJobsListDefaultLimit = 50

    func handleMCPJobsList(
        _ request: HTTPRequest, jobService: JobService, store: BackgroundStore
    ) async -> HTTPResponse {
        let req = try? request.decodeBody(as: MCPJobsListRequest.self)
        let rawLimit = req?.limit ?? mcpJobsListDefaultLimit
        guard rawLimit >= mcpJobsListMinLimit else {
            return HTTPResponse.error("limit must be at least \(mcpJobsListMinLimit)", code: 400)
        }
        let offset = req?.offset ?? 0
        guard offset >= 0 else {
            return HTTPResponse.error("offset must be 0 or greater", code: 400)
        }
        let wantsSummary = req?.summary == true
        let maxLimit = wantsSummary ? mcpJobsListMaxSummaryLimit : mcpJobsListMaxLimit
        let limit = min(rawLimit, maxLimit)
        // The old behaviour clamped silently, so a caller asking for 480 got 200 and no indication
        // that it hadn't seen everything.
        let notice = rawLimit > maxLimit
            ? "limit was reduced from \(rawLimit) to \(maxLimit)"
            + (wantsSummary ? "" : "; pass summary: true to page up to \(mcpJobsListMaxSummaryLimit)")
            : nil

        var capturedAfter: Date?
        if let raw = req?.capturedAfter, !raw.isEmpty {
            guard let parsed = parseFlexibleDate(raw) else {
                return HTTPResponse.error("captured_after must be an ISO-8601 date (e.g. 2026-07-01)", code: 400)
            }
            capturedAfter = parsed
        }

        let query = JobQuery(
            status: req?.status,
            query: req?.query,
            company: req?.company,
            capturedAfter: capturedAfter,
            minSalary: req?.minSalary,
            minScore: req?.minScore,
            offset: offset,
            limit: limit
        )

        // The composite verdict isn't stored, so it can't be a JobQuery predicate — filter after
        // fetching and report a total that reflects the filter rather than the unfiltered set.
        var wantedBucket: JobFilterRules.CriteriaBucket?
        if let raw = req?.requirementsVerdict, !raw.isEmpty {
            guard let bucket = JobFilterRules.CriteriaBucket(wireName: raw) else {
                return HTTPResponse.error(
                    "invalid requirements_verdict '\(raw)'; valid: meets, not_stated, does_not_meet", code: 400
                )
            }
            wantedBucket = bucket
        }

        do {
            let thresholds = await requirementThresholds(store)
            if let wantedBucket {
                // Page over everything, keep the matches, then slice — the alternative is a filtered
                // page whose `total` describes a different set than the rows returned.
                var all = query
                all.offset = 0
                all.limit = Int.max
                let everything = try await jobService.listJobs(all)
                let matching = everything.records.filter {
                    requirementsVerdict($0, thresholds: thresholds)?.bucket == wantedBucket
                }
                let slice = Array(matching.dropFirst(offset).prefix(limit))
                let page = JobListPage(records: slice, total: matching.count, offset: offset, limit: limit)
                return respond(page: page, thresholds: thresholds, summary: wantsSummary, notice: notice)
            }
            let page = try await jobService.listJobs(query)
            return respond(page: page, thresholds: thresholds, summary: wantsSummary, notice: notice)
        } catch let error as JobServiceError {
            return HTTPResponse.error(error.errorDescription ?? "invalid request", code: 400)
        } catch {
            return HTTPResponse.error(safeServerError(error, context: "handleMCPJobsList"), code: 500)
        }
    }

    private func respond(
        page: JobListPage,
        thresholds: JobRequirements.Thresholds,
        summary: Bool,
        notice: String?
    ) -> HTTPResponse {
        if summary {
            return HTTPResponse.ok(MCPJobsListResponse(
                jobs: page.records.map { compactRow($0, thresholds: thresholds) }, total: page.total,
                offset: page.offset, limit: page.limit, hasMore: page.hasMore,
                nextOffset: page.nextOffset, notice: notice
            ))
        }
        return HTTPResponse.ok(MCPJobsListResponse(
            jobs: page.records.map { fullRow($0, thresholds: thresholds) }, total: page.total,
            offset: page.offset, limit: page.limit, hasMore: page.hasMore,
            nextOffset: page.nextOffset, notice: notice
        ))
    }

    private func compactRow(_ r: JobListRecord, thresholds: JobRequirements.Thresholds) -> MCPJobSummaryCompact {
        MCPJobSummaryCompact(
            jobNumber: r.jobNumber, company: r.company, title: r.title,
            status: r.status.rawValue, location: r.location,
            salaryMin: r.salaryMin, salaryMax: r.salaryMax, sourceURL: r.sourceURL,
            fitScore: r.fitScore, salaryCurrency: r.salaryCurrency,
            requirementsVerdict: requirementsVerdict(r, thresholds: thresholds)?.bucket.wireName
        )
    }

    private func fullRow(_ r: JobListRecord, thresholds: JobRequirements.Thresholds) -> MCPJobSummary {
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
            createdAt: formatDate(r.createdAt),
            employmentType: r.employmentType,
            seniority: r.seniority,
            duplicateOfJobID: r.duplicateOfJobID,
            fitScore: r.fitScore,
            fitStatus: r.fitStatus.rawValue,
            salaryCurrency: r.salaryCurrency,
            salaryHourlyMin: r.salaryHourlyMin,
            salaryHourlyMax: r.salaryHourlyMax,
            meetsCriteria: r.meetsCriteria,
            requirementsVerdict: requirementsVerdict(r, thresholds: thresholds)?.bucket.wireName,
            appliedAt: formatDate(r.appliedAt),
            updatedAt: formatDate(r.updatedAt as Date?),
            unread: r.unread
        )
    }

    /// The user's configured floors, read from the settings rows the app writes.
    ///
    /// The composite verdict is computed at read time in the app (thresholds are settings, so a
    /// change re-filters instantly with no stored state). Computing it here too means MCP consumers
    /// can both SEE and FILTER on it — exposing a field that couldn't be queried would be worse than
    /// not exposing it.
    func requirementThresholds(_ store: BackgroundStore) async -> JobRequirements.Thresholds {
        guard let settings = try? await store.fetch(FetchDescriptor<Setting>()) else {
            return .none
        }
        let byKey = Dictionary(settings.map { ($0.key, $0.value) }, uniquingKeysWith: { first, _ in first })
        return JobRequirements.Thresholds(
            minSalary: Int(byKey[SettingsKey.minSalary] ?? "0") ?? 0,
            minFitScore: Int(byKey[SettingsKey.minFitScore] ?? "0") ?? 0
        )
    }

    func requirementsVerdict(
        _ record: JobListRecord, thresholds: JobRequirements.Thresholds
    ) -> JobRequirements.Verdict? {
        JobRequirements.evaluate(
            meetsCriteria: record.meetsCriteria, remoteType: record.remoteType,
            salaryMin: record.salaryMin, salaryMax: record.salaryMax,
            salaryCurrency: record.salaryCurrency, fitScore: record.fitScore,
            thresholds: thresholds
        )
    }

    /// Accepts a full ISO-8601 timestamp or a bare `YYYY-MM-DD`, which is what a caller filtering by
    /// date will reach for first.
    private func parseFlexibleDate(_ raw: String) -> Date? {
        if let date = mcpISOFormatter.date(from: raw) { return date }
        let dayOnly = DateFormatter()
        dayOnly.calendar = Calendar(identifier: .gregorian)
        dayOnly.timeZone = TimeZone(secondsFromGMT: 0)
        dayOnly.locale = Locale(identifier: "en_US_POSIX")
        dayOnly.dateFormat = "yyyy-MM-dd"
        return dayOnly.date(from: raw)
    }
#endif
