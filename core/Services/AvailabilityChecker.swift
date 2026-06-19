// swiftlint:disable line_length cyclomatic_complexity function_body_length large_tuple type_body_length
import Foundation
import SwiftData

// MARK: - Result type

public enum URLAvailabilityResult: Sendable {
    case available
    case gone(reason: String)
    case error(Error)
}

// MARK: - Domain events

public extension Notification.Name {
    static let jobUnavailable = Notification.Name("jobhunt.jobUnavailable")
}

/// Keys for jobUnavailable notification userInfo.
public enum JobUnavailableKey {
    public static let jobID = "jobID"
    public static let jobNumber = "jobNumber"
    public static let title = "title"
    public static let reason = "reason"
}

// MARK: - GoneJobResult

/// A job found to be unavailable during a check. Returned to the caller for user confirmation
/// before any status change is made.
public struct GoneJobResult: Sendable {
    public let jobID: String
    public let jobNumber: Int?
    public let company: String?
    public let title: String
    public let url: URL
    public let reason: String
}

// MARK: - AvailabilityChecker

/// Ports server/availability.js: URL liveness detection + stale-job scheduler.
public enum AvailabilityChecker {
    // MARK: - Constants (mirroring JS)

    static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
    static let goneStatusCodes: Set<Int> = [404, 410]
    static let goneBodyPatterns: [String] = [
        "page not found", "job not found", "job no longer available",
        "this job is no longer", "position is no longer available", "position has been filled",
        "posting has expired", "job posting has expired", "no longer accepting applications",
        "job listing has expired", "this position has been filled", "this role is no longer",
        "opening is no longer", "requisition is no longer", "job has been closed",
        "this job has been removed"
    ]
    static let timeoutSeconds: TimeInterval = 12

    // MARK: - URL normalization helpers

    /// Strips fragment, sorts query params, removes trailing slash from path.
    /// Returns nil if the URL has no scheme or host (i.e. is not an absolute HTTP URL).
    static func normalizedURL(_ rawURL: String) -> URL? {
        guard var components = URLComponents(string: rawURL),
              let scheme = components.scheme, !scheme.isEmpty,
              let host = components.host, !host.isEmpty else { return nil }
        components.fragment = nil
        if let items = components.queryItems {
            components.queryItems = items.sorted { $0.name < $1.name }
        }
        var path = components.path
        while path.hasSuffix("/") && path.count > 1 {
            path = String(path.dropLast())
        }
        if path.isEmpty { path = "/" }
        components.path = path
        return components.url
    }

    /// True when `title` has ≥3 meaningful words (mirrors isMeaningfulTitle).
    static func isMeaningfulTitle(_ title: String) -> Bool {
        normalizedText(title).split(separator: " ").count(where: { !$0.isEmpty }) >= 3
    }

    static func normalizedText(_ value: String) -> String {
        let lower = value.lowercased()
        let cleaned = lower.unicodeScalars.map { scalar -> Character in
            let codePoint = scalar.value
            if (codePoint >= 97 && codePoint <= 122) ||
                (codePoint >= 48 && codePoint <= 57) { return Character(scalar) } // a-z, 0-9
            return " "
        }
        return String(cleaned).split(separator: " ").joined(separator: " ")
    }

    /// True when body contains the normalized title (mirrors bodyContainsTitle — skips short titles).
    static func bodyContainsTitle(_ body: String, title: String) -> Bool {
        guard isMeaningfulTitle(title) else { return true }
        return normalizedText(body).contains(normalizedText(title))
    }

    /// True when a redirect went from a job URL to a non-job page on the same domain.
    /// Cross-domain redirects return false (not classified as gone by this heuristic).
    static func redirectedToNonJobPage(originalURLString: String, finalURLString: String) -> Bool {
        guard let orig = normalizedURL(originalURLString),
              let final = normalizedURL(finalURLString) else { return false }
        // If URLs are effectively identical, no redirect.
        if orig.absoluteString == final.absoluteString { return false }

        guard let origComponents = URLComponents(url: orig, resolvingAgainstBaseURL: false),
              let finalComponents = URLComponents(url: final, resolvingAgainstBaseURL: false) else {
            return false
        }

        // Cross-domain redirects: not classified as non-job by this heuristic.
        guard origComponents.host == finalComponents.host else { return false }

        let path = (finalComponents.path.lowercased() as NSString).standardizingPath
        let trimmedPath = path.hasSuffix("/") ? String(path.dropLast()) : path
        let origPath = (origComponents.path.lowercased() as NSString).standardizingPath

        // Redirected to root or generic jobs/careers root.
        if trimmedPath == "" || trimmedPath == "/" || trimmedPath == "/jobs" || trimmedPath == "/careers" {
            return true
        }
        // Redirected to a company page.
        if trimmedPath.contains("/company/") || trimmedPath.contains("/companies/") {
            return true
        }
        // Redirected to a search/listings page (different path ending in /search, /jobs, /careers, /openings).
        if trimmedPath != origPath {
            let suffixes = ["/search", "/jobs", "/careers", "/openings"]
            if suffixes.contains(where: { trimmedPath.hasSuffix($0) }) {
                return true
            }
        }
        return false
    }

    /// True when a URL is a login / auth wall or an aggregator's "can't show this posting without
    /// login" fallback. Some sites (notably LinkedIn) redirect an un-authenticated availability
    /// check to such a page instead of the posting — that is NOT evidence the job is gone, so the
    /// redirect heuristics must be skipped to avoid false-positive expirations.
    static func isAuthWallURL(_ urlString: String) -> Bool {
        guard let comps = URLComponents(string: urlString) else { return false }
        let host = (comps.host ?? "").lowercased()
        let path = comps.path.lowercased()
        // Generic login / auth-wall paths (applies to any site).
        let authFragments = [
            "/login", "/signin", "/sign-in", "/authwall", "/uas/login",
            "/checkpoint", "/account/login", "/sso/", "/auth/realms"
        ]
        if authFragments.contains(where: { path.contains($0) }) { return true }
        // LinkedIn serves a generic "collections / similar jobs" page when a specific posting
        // can't be viewed without login — ambiguous, so treat it as indeterminate, not gone.
        if host.contains("linkedin.com"),
           path.contains("/jobs/collections") || path.contains("/jobs/search") {
            return true
        }
        return false
    }

    // MARK: - checkURL

    /// Checks whether a single job URL is still live. Mirrors checkUrl() in availability.js.
    /// - Parameters:
    ///   - url: The job posting URL.
    ///   - title: The job title (used for redirect/title heuristics).
    ///   - session: URLSession to use (injectable for testing).
    /// - Returns: `.available`, `.gone(reason:)`, or `.error(_)`.
    public static func checkURL(
        _ url: URL,
        title: String,
        session: URLSession = .shared
    ) async -> URLAvailabilityResult {
        var request = URLRequest(url: url, timeoutInterval: timeoutSeconds)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .available
            }
            let finalURLString = http.url?.absoluteString ?? url.absoluteString
            let statusCode = http.statusCode

            // 1. Gone status codes.
            if goneStatusCodes.contains(statusCode) {
                return .gone(reason: "HTTP \(statusCode)")
            }

            // 2. Body pattern matching.
            let body = String(data: data, encoding: .utf8)?.lowercased() ?? ""
            for pattern in goneBodyPatterns where body.contains(pattern) {
                return .gone(reason: "body: \(pattern)")
            }

            // 2.5 Login / auth wall (e.g. LinkedIn redirecting an un-authenticated check to a
            // collections or login page). We can't determine availability behind a login, so don't
            // flag as gone — the redirect heuristics below would otherwise false-positive.
            if isAuthWallURL(finalURLString) {
                return .available
            }

            // 3. Redirect to non-job page.
            if redirectedToNonJobPage(originalURLString: url.absoluteString, finalURLString: finalURLString) {
                return .gone(reason: "redirected to non-job page: \(finalURLString)")
            }

            // 4. Redirect with missing title.
            let origNorm = normalizedURL(url.absoluteString)?.absoluteString ?? url.absoluteString
            let finalNorm = normalizedURL(finalURLString)?.absoluteString ?? finalURLString
            if origNorm != finalNorm && !bodyContainsTitle(body, title: title) {
                return .gone(reason: "redirected page missing title: \(finalURLString)")
            }

            return .available
        } catch let error as URLError where error.code == .timedOut || error.code == .cancelled {
            // Timeout treated as available (mirrors AbortError → available/timeout in JS).
            return .available
        } catch {
            // Network errors treated as available (mirrors non-AbortError → available/error in JS).
            return .error(error)
        }
    }

    // MARK: - findGoneJobs

    /// Checks the URLs of pursuing jobs and returns those that appear to be gone,
    /// WITHOUT modifying any job records. Call this to gather candidates, then show
    /// a confirmation UI before marking them expired.
    public static func findGoneJobs(
        _ jobs: [Job],
        session: URLSession = .shared
    ) async -> [GoneJobResult] {
        let eligible = jobs.filter { $0.status == .pursuing }
        guard !eligible.isEmpty else { return [] }

        struct JobSpec: Sendable {
            let id: String; let jobNumber: Int?; let company: String?; let title: String; let url: URL
        }
        let specs: [JobSpec] = eligible.compactMap { job in
            let urlString = JobURLPolicy.availabilityCheckURL(job: job) ?? ""
            guard !urlString.isEmpty, let url = URL(string: urlString) else { return nil }
            return JobSpec(id: job.id, jobNumber: job.jobNumber, company: job.company, title: job.title ?? "", url: url)
        }
        guard !specs.isEmpty else { return [] }

        var results: [GoneJobResult] = []
        await withTaskGroup(of: GoneJobResult?.self) { group in
            var inFlight = 0
            for spec in specs {
                if inFlight >= 10 {
                    if let r = await group.next() {
                        if let r { results.append(r) }
                        inFlight -= 1
                    }
                }
                let (id, jobNumber, company, title, url) = (spec.id, spec.jobNumber, spec.company, spec.title, spec.url)
                inFlight += 1
                group.addTask {
                    let result = await checkURL(url, title: title, session: session)
                    if case let .gone(reason) = result {
                        return GoneJobResult(
                            jobID: id, jobNumber: jobNumber, company: company,
                            title: title, url: url, reason: reason
                        )
                    }
                    return nil
                }
            }
            for await r in group {
                if let r { results.append(r) }
            }
        }
        return results
    }

    // MARK: - checkJobs

    /// Lightweight value type for communicating check results across async boundaries.
    private struct CheckedJob {
        let jobID: String
        let jobNumber: Int?
        let title: String
        let url: URL
        let result: URLAvailabilityResult
    }

    /// Checks actively-pursued jobs in parallel (max 10 concurrent).
    /// Auto-expiry is restricted to pursuing jobs only — applied/interview/offer/rejected/duplicate
    /// jobs are protected from automatic status changes.
    /// Jobs found gone are marked `.expired` and a `jobUnavailable` notification is posted.
    public static func checkJobs(
        _ jobs: [Job],
        store: BackgroundStore,
        session: URLSession = .shared
    ) async -> (checked: Int, unavailable: Int, marked: Int, failed: Int) {
        let eligible = jobs.filter { $0.status == .pursuing }
        guard !eligible.isEmpty else { return (0, 0, 0, 0) }

        // Extract lightweight metadata before entering async task group (avoids sending Job across actors).
        struct JobSpec: Sendable {
            let id: String
            let jobNumber: Int?
            let title: String
            let url: URL
        }
        let specs: [JobSpec] = eligible.compactMap { job in
            let urlString = JobURLPolicy.availabilityCheckURL(job: job) ?? ""
            guard !urlString.isEmpty, let url = URL(string: urlString) else { return nil }
            return JobSpec(id: job.id, jobNumber: job.jobNumber, title: job.title ?? "", url: url)
        }
        guard !specs.isEmpty else { return (0, 0, 0, 0) }

        var checkedJobs: [CheckedJob] = []

        await withTaskGroup(of: CheckedJob.self) { group in
            var inFlight = 0
            let maxConcurrent = 10

            for spec in specs {
                // Wait for one result if at the concurrency limit.
                if inFlight >= maxConcurrent {
                    if let nextResult = await group.next() {
                        checkedJobs.append(nextResult)
                        inFlight -= 1
                    }
                }
                let id = spec.id
                let jobNumber = spec.jobNumber
                let title = spec.title
                let url = spec.url
                inFlight += 1
                group.addTask {
                    let checkResult = await checkURL(url, title: title, session: session)
                    return CheckedJob(jobID: id, jobNumber: jobNumber, title: title, url: url, result: checkResult)
                }
            }

            // Drain remaining tasks.
            for await groupResult in group {
                checkedJobs.append(groupResult)
            }
        }

        // Mark gone jobs.
        var markedCount = 0
        var failedCount = 0
        let unavailableCount = checkedJobs.count(where: { if case .gone = $0.result { return true }; return false })

        for checked in checkedJobs {
            if case let .gone(reason) = checked.result {
                do {
                    let idToMatch = checked.jobID
                    try await store.update(Job.self, predicate: #Predicate { $0.id == idToMatch }) { job in
                        job.status = .expired
                        job.updatedAt = Date()
                    }
                    markedCount += 1
                    // Record audit event for the auto-expiry.
                    let matchedJobs = try await store
                        .fetch(FetchDescriptor<Job>(predicate: #Predicate { $0.id == idToMatch }))
                    if let job = matchedJobs.first {
                        let event = JobEvent(
                            eventType: "availability",
                            note: "Auto-expired: \(reason). Checked: \(checked.url.absoluteString)"
                        )
                        event.job = job
                        try await store.insert(event)
                    }
                    NotificationCenter.default.post(
                        name: .jobUnavailable,
                        object: nil,
                        userInfo: [
                            JobUnavailableKey.jobID: checked.jobID,
                            JobUnavailableKey.jobNumber: checked.jobNumber as Any,
                            JobUnavailableKey.title: checked.title,
                            JobUnavailableKey.reason: reason
                        ]
                    )
                } catch {
                    // A gone job we failed to mark/record is NOT a successful check — count it and
                    // log it instead of silently dropping it, so callers can surface the failure.
                    failedCount += 1
                    NSLog("AvailabilityChecker: failed to mark job \(checked.jobID) expired: \(error)")
                }
            }
        }

        return (checked: checkedJobs.count, unavailable: unavailableCount, marked: markedCount, failed: failedCount)
    }

    // MARK: - checkStaleJobs

    /// Checks jobs that haven't been touched in `staleDays` days, up to `limit` per run.
    /// Throws if the underlying store fetch fails — callers must treat that as a failed check
    /// (not a zero-result success), or future checks get suppressed for the interval.
    public static func checkStaleJobs(
        store: BackgroundStore,
        staleDays: Int = 21,
        limit: Int = 25,
        session: URLSession = .shared
    ) async throws -> (checked: Int, unavailable: Int, marked: Int, failed: Int) {
        let cutoff = Date().addingTimeInterval(-Double(max(1, staleDays)) * 86400)

        // Use capturedAtDenormalized (populated on insert since TASK-216) to sort jobs
        // oldest-first at the DB level, bounding the query with fetchLimit.
        // Status and date are still filtered in-memory (enum predicates unsupported; optional
        // date comparison in predicates requires force-unwrap which SwiftData doesn't support).
        // A fetch failure propagates (do NOT swallow it as an empty result).
        var descriptor = FetchDescriptor<Job>(
            predicate: #Predicate { $0.capturedAtDenormalized != nil },
            sortBy: [SortDescriptor(\Job.capturedAtDenormalized, order: .forward)]
        )
        descriptor.fetchLimit = limit * 4 // over-fetch to allow for in-memory status filter
        let newStyleRows = try await store.fetch(descriptor)

        // Legacy rows with nil capturedAtDenormalized: fetch separately, filter via relationship
        var legacyDescriptor = FetchDescriptor<Job>(
            predicate: #Predicate { $0.capturedAtDenormalized == nil },
            sortBy: [SortDescriptor(\Job.createdAt, order: .forward)]
        )
        legacyDescriptor.fetchLimit = limit * 2
        let legacyRows = try await store.fetch(legacyDescriptor)

        let all = newStyleRows + legacyRows
        let jobs = all.filter { job in
            guard job.status != .passed, job.status != .archived,
                  job.status != .closed, job.status != .expired else { return false }
            let ageDate = job.capturedAtDenormalized ?? job.capture?.capturedAt ?? job.createdAt
            return ageDate <= cutoff
        }.prefix(limit).map(\.self)

        return await checkJobs(jobs, store: store, session: session)
    }

    // MARK: - maybeRunStaleCheck

    /// Runs stale availability check if enabled and the check interval has elapsed.
    /// - Parameter onAutoCheckCompleted: called with the completion time ONLY after a valid pass, so
    ///   the caller can persist `availabilityLastAutoCheckAt` through an explicit dependency rather
    ///   than a global notification (TASK-428). Not called when the check is skipped or the fetch
    ///   fails, so the interval gate never advances without real work.
    public static func maybeRunStaleCheck(
        store: BackgroundStore,
        settings: SettingsStore,
        session: URLSession = .shared,
        onAutoCheckCompleted: (@Sendable (Date) async -> Void)? = nil
    ) async -> (skipped: Bool, reason: String?, checked: Int, unavailable: Int, marked: Int, failed: Int) {
        // Check if auto-check is enabled.
        guard settings.bool(forKey: SettingsKey.availabilityAutoCheckEnabled) else {
            return (skipped: true, reason: "disabled", checked: 0, unavailable: 0, marked: 0, failed: 0)
        }

        // Check interval gate.
        let intervalDays = max(1, settings.int(forKey: SettingsKey.availabilityAutoCheckIntervalDays))
        let lastCheckStr = settings.string(forKey: SettingsKey.availabilityLastAutoCheckAt)
        if !lastCheckStr.isEmpty, let lastCheck = ISO8601DateFormatter().date(from: lastCheckStr) {
            let elapsed = Date().timeIntervalSince(lastCheck)
            if elapsed < Double(intervalDays) * 86400 {
                return (skipped: true, reason: "interval", checked: 0, unavailable: 0, marked: 0, failed: 0)
            }
        }

        let staleDays = max(1, settings.int(forKey: SettingsKey.availabilityStaleDays))
        let result: (checked: Int, unavailable: Int, marked: Int, failed: Int)
        do {
            result = try await checkStaleJobs(store: store, staleDays: staleDays, limit: 25, session: session)
        } catch {
            // Fetch failed — no valid check ran. Do NOT invoke onAutoCheckCompleted, or the app
            // layer would advance the last-check timestamp and suppress checks for the whole interval
            // despite nothing being checked. Surface as a failed (not skipped) result.
            NSLog("AvailabilityChecker: stale check fetch failed: \(error)")
            return (skipped: false, reason: "fetch-error", checked: 0, unavailable: 0, marked: 0, failed: 0)
        }

        // Only after a valid pass: hand the completion time to the caller so it can persist
        // `availabilityLastAutoCheckAt` (TASK-428). The caller hops to the main actor as needed —
        // the checker no longer depends on a global notification observer being registered.
        await onAutoCheckCompleted?(Date())

        return (
            skipped: false,
            reason: nil,
            checked: result.checked,
            unavailable: result.unavailable,
            marked: result.marked,
            failed: result.failed
        )
    }
}

// swiftlint:enable line_length cyclomatic_complexity function_body_length large_tuple type_body_length
