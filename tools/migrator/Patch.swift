import Foundation
import JobhuntCore
import SwiftData

// MARK: - Patch Summary

struct PatchSummary {
    var jobsInserted = 0
    var siteReviews = 0
    var llmRequests = 0
    var llmRequestAttempts = 0
    var events = 0
    var savedSearches = 0
    var settings = 0
    var recleanedCaptures = 0
    var skipped = 0
}

// MARK: - Helpers

/// Parses a capture's structured_data JSON into the shape cleanDescription() expects.
func parseStructuredData(_ json: String?) -> [[String: Any]] {
    guard let json, let data = json.data(using: .utf8),
          let parsed = try? JSONSerialization.jsonObject(with: data) else { return [] }
    if let arr = parsed as? [[String: Any]] { return arr }
    if let dict = parsed as? [String: Any] { return [dict] }
    return []
}

/// Best-effort map of a legacy saved_views rule tree to a SavedSearch free-text query:
/// returns the value of the first company/title/location "contains" rule, else "".
func savedViewSearchText(_ ruleTreeJSON: String?) -> String {
    guard let ruleTreeJSON, let data = ruleTreeJSON.data(using: .utf8),
          let tree = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let rules = tree["rules"] as? [[String: Any]] else { return "" }
    for rule in rules {
        guard let field = rule["field"] as? String,
              ["company", "title", "location"].contains(field),
              let value = rule["value"] as? String else { continue }
        return value
    }
    return ""
}

// MARK: - Patch Logic

func patch(src: DBHandle, context: ModelContext) -> PatchSummary {
    var s = PatchSummary()

    // ── Jobs: import any SQLite jobs not yet in SwiftData ─────────────────────
    let existingJobIDs = Set((try? context.fetch(FetchDescriptor<Job>()))?.map(\.id) ?? [])
    var captureMap: [String: Capture] = [:]
    if let all = try? context.fetch(FetchDescriptor<Capture>()) {
        for c in all { captureMap[c.id] = c }
    }
    if tableExists(src, "jobs") {
        for row in queryRows(src, "SELECT * FROM jobs") {
            guard let id = row.str("id") else { continue }
            if existingJobIDs.contains(id) { continue }
            let j = Job(
                id: id,
                jobNumber: row.int("job_number"),
                company: row.str("company"),
                title: row.str("title"),
                location: row.str("location"),
                remoteType: row.str("remote_type").flatMap { RemoteType(rawValue: $0) },
                salaryMin: row.int("salary_min"),
                salaryMax: row.int("salary_max"),
                salaryCurrency: row.str("salary_currency"),
                salaryNote: row.str("salary_note"),
                employmentType: row.str("employment_type"),
                seniority: row.str("seniority"),
                status: row.str("status").flatMap { JobStatus(rawValue: $0) } ?? .pursuing,
                manualOverridesJSON: row.req("manual_overrides", fallback: "[]"),
                extractedJSON: row.str("extracted_json"),
                extractionStatus: row.str("extraction_status").flatMap { ExtractionStatus(rawValue: $0) } ?? .pending,
                extractionError: row.str("extraction_error"),
                fitScore: row.int("fit_score"),
                fitStatus: row.str("fit_status").flatMap { FitStatus(rawValue: $0) } ?? .none,
                fitScoreJSON: row.str("fit_score_json"),
                duplicateOfJobID: row.str("duplicate_of_job_id"),
                duplicateConfidence: row.dbl("duplicate_confidence"),
                extractedAt: row.date("extracted_at"),
                rating: row.int("rating"),
                extractionModel: row.str("extraction_model"),
                applicationURL: row.str("application_url"),
                extractionConfidence: row.dbl("extraction_confidence"),
                lastOpenedAt: row.date("last_opened_at"),
                unread: row.bool("unread"),
                createdAt: row.dateOrNow("created_at"),
                updatedAt: row.dateOrNow("updated_at")
            )
            context.insert(j)
            let capId = row.str("capture_id")
            let jobNum = row.int("job_number")
            let jobLabel = jobNum.map { "#\($0)" } ?? id
            let jobTitle = row.str("title") ?? "?"
            let jobCompany = row.str("company") ?? "?"
            // Save first so the job gets a persistent ID before linking relationships
            do { try context.save() } catch {
                // TASK-476: abort rather than continue — a partially-patched store is worse than a
                // clear failure the operator can retry after fixing the cause.
                fputs("Error: failed to save new job \(jobLabel) — aborting patch to avoid a partial store: \(error)\n", stderr)
                exit(1)
            }
            if let capId, let cap = captureMap[capId] {
                j.capture = cap
                j.capturedAtDenormalized = cap.capturedAt
            }
            s.jobsInserted += 1
            print("  job \(jobLabel) (\(jobTitle) @ \(jobCompany)) → inserted")
        }
        if s.jobsInserted > 0 {
            // Final save to persist capture relationships set after each job's initial save
            do { try context.save() } catch {
                fputs("Error: failed to save job relationships — aborting patch to avoid a partial store: \(error)\n", stderr)
                exit(1)
            }
        }
    }

    // Build existing ID sets to detect what's already there
    let existingSiteReviewIDs = Set((try? context.fetch(FetchDescriptor<SiteReview>()))?.map(\.id) ?? [])
    let existingLLMRequestIDs = Set((try? context.fetch(FetchDescriptor<LLMRequest>()))?.map(\.id) ?? [])
    let existingAttemptIDs    = Set((try? context.fetch(FetchDescriptor<LLMRequestAttempt>()))?.map(\.id) ?? [])

    // Job and resume maps for linking
    let allJobs    = (try? context.fetch(FetchDescriptor<Job>())) ?? []
    let allResumes = (try? context.fetch(FetchDescriptor<Resume>())) ?? []
    let jobMap     = Dictionary(uniqueKeysWithValues: allJobs.map { ($0.id, $0) })
    let resumeMap  = Dictionary(uniqueKeysWithValues: allResumes.map { ($0.id, $0) })

    // site_reviews
    if tableExists(src, "site_reviews") {
        for row in queryRows(src, "SELECT * FROM site_reviews") {
            guard let id = row.str("id") else { continue }
            if existingSiteReviewIDs.contains(id) { s.skipped += 1; continue }
            let sr = SiteReview(
                id: id,
                siteURL: row.req("site_url"),
                siteOrigin: row.req("site_origin"),
                pageTitle: row.str("page_title"),
                reviewedAt: row.dateOrNow("reviewed_at"),
                nextReviewAt: row.date("next_review_at"),
                note: row.str("note"),
                createdAt: row.dateOrNow("created_at")
            )
            context.insert(sr)
            s.siteReviews += 1
            print("  site_review \(id.prefix(20))… → inserted")
        }
    }

    // llm_requests
    var newRequestMap: [String: LLMRequest] = [:]
    if tableExists(src, "llm_requests") {
        for row in queryRows(src, "SELECT * FROM llm_requests") {
            guard let id = row.str("id") else { continue }
            if existingLLMRequestIDs.contains(id) { s.skipped += 1; continue }
            guard let jobId = row.str("job_id") else { continue }
            let req = LLMRequest(
                id: id,
                requestType: row.str("request_type").flatMap { LLMRequestType(rawValue: $0) } ?? .extract,
                status: row.str("status").flatMap { LLMRequestStatus(rawValue: $0) } ?? .queued,
                attempt: row.int("attempt") ?? 1,
                model: row.str("model"),
                error: row.str("error"),
                createdAt: row.dateOrNow("created_at"),
                startedAt: row.date("started_at"),
                finishedAt: row.date("finished_at")
            )
            req.job = jobMap[jobId]
            if let resumeId = row.str("resume_id") { req.resume = resumeMap[resumeId] }
            context.insert(req)
            newRequestMap[id] = req
            s.llmRequests += 1
        }
        print("  llm_requests: \(s.llmRequests) inserted, \(s.skipped) already present")
    }

    // Combine with existing requests for attempt linking
    let allRequests = (try? context.fetch(FetchDescriptor<LLMRequest>())) ?? []
    let fullRequestMap = Dictionary(uniqueKeysWithValues: allRequests.map { ($0.id, $0) })

    // llm_request_attempts
    if tableExists(src, "llm_request_attempts") {
        for row in queryRows(src, "SELECT * FROM llm_request_attempts") {
            guard let id = row.str("id"),
                  let requestId = row.str("request_id"),
                  let jobId = row.str("job_id") else { continue }
            if existingAttemptIDs.contains(id) { continue }
            let attempt = LLMRequestAttempt(
                id: id,
                requestType: row.str("request_type").flatMap { LLMRequestType(rawValue: $0) } ?? .extract,
                attempt: row.int("attempt") ?? 1,
                status: row.str("status").flatMap { LLMRequestStatus(rawValue: $0) } ?? .queued,
                modelRequested: row.str("model_requested"),
                modelReturned: row.str("model_returned"),
                responseFormat: row.str("response_format"),
                baseURL: row.str("base_url"),
                startedAt: row.dateOrNow("started_at"),
                finishedAt: row.date("finished_at"),
                durationMs: row.int("duration_ms"),
                error: row.str("error"),
                responsePreview: row.str("response_preview"),
                promptChars: row.int("prompt_chars"),
                responseChars: row.int("response_chars")
            )
            attempt.request = fullRequestMap[requestId]
            attempt.job = jobMap[jobId]
            context.insert(attempt)
            s.llmRequestAttempts += 1
        }
        print("  llm_request_attempts: \(s.llmRequestAttempts) inserted")
    }

    // events → JobEvent  (jobMap is fetched from the already-saved store, so linking is reliable)
    if tableExists(src, "events") {
        let existingEventIDs = Set((try? context.fetch(FetchDescriptor<JobEvent>()))?.map(\.id) ?? [])
        for row in queryRows(src, "SELECT * FROM events") {
            guard let id = row.str("id"), let jobId = row.str("job_id") else { continue }
            if existingEventIDs.contains(id) { s.skipped += 1; continue }
            guard let parentJob = jobMap[jobId] else { continue }
            let ev = JobEvent(
                id: id,
                eventType: row.req("event_type"),
                note: row.str("note"),
                occurredAt: row.dateOrNow("occurred_at"),
                createdAt: row.dateOrNow("created_at")
            )
            ev.job = parentJob
            context.insert(ev)
            s.events += 1
        }
        print("  events: \(s.events) inserted")
    }

    // saved_views → SavedSearch (best-effort: legacy rule tree → discrete fields)
    if tableExists(src, "saved_views") {
        let existingNames = Set((try? context.fetch(FetchDescriptor<SavedSearch>()))?.map(\.name) ?? [])
        for row in queryRows(src, "SELECT * FROM saved_views") {
            guard let name = row.str("name") else { continue }
            if (row.str("page") ?? "jobs") != "jobs" { continue }   // only job-scoped views map
            if existingNames.contains(name) { s.skipped += 1; continue }
            let search = SavedSearch(name: name, searchText: savedViewSearchText(row.str("rule_tree")))
            if let id = row.str("id") { search.id = id }
            if let created = row.date("created_at") { search.createdAt = created }
            context.insert(search)
            s.savedSearches += 1
            print("  saved_view '\(name)' → SavedSearch (searchText=\(search.searchText))")
        }
    }

    // settings (non-secret only — API keys must live in Keychain, never SwiftData)
    if tableExists(src, "settings") {
        let existingKeys = Set((try? context.fetch(FetchDescriptor<Setting>()))?.map(\.key) ?? [])
        for row in queryRows(src, "SELECT * FROM settings") {
            guard let key = row.str("key"), let value = row.str("value") else { continue }
            if SettingsKey.keychainKeys.contains(key) { continue }
            if existingKeys.contains(key) { s.skipped += 1; continue }
            let setting = Setting(key: key, value: value, updatedAt: row.dateOrNow("updated_at"))
            context.insert(setting)
            s.settings += 1
            print("  setting '\(key)' → inserted")
        }
    }

    // Re-clean captures whose cleaned description is trivial boilerplate but whose raw page
    // text is substantial. The old JS cleaner used selected-text-only, so a stray "$" selection
    // produced a 1-char cleaned description that hid the full JD (still present in visible_text).
    let allCaptures = (try? context.fetch(FetchDescriptor<Capture>())) ?? []
    for cap in allCaptures {
        let current = cap.cleanedDescription ?? ""
        let visible = cap.visibleText ?? ""
        guard current.count < 8, visible.count > 200 else { continue }
        let structured = parseStructuredData(cap.structuredDataJSON)
        // Drop the junk selected text — re-clean from visible text + JSON-LD only.
        let recleaned = cleanDescription(selectedText: "", visibleText: visible, structuredData: structured)
        guard recleaned.count >= 100 else { continue }
        cap.cleanedDescription = recleaned
        cap.cleanedHash = DuplicateDetector.cleanedHash(from: recleaned)
        s.recleanedCaptures += 1
        print("  re-cleaned capture \(cap.id.prefix(16))… (\(current.count)→\(recleaned.count) chars)")
    }

    do {
        try context.save()
    } catch {
        fputs("Error saving patch: \(error)\n", stderr)
    }
    return s
}
