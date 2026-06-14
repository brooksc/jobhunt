import Foundation
import JobhuntCore
import SwiftData

// MARK: - Migration Summary

struct MigrationSummary {
    var captures = 0
    var jobs = 0
    var events = 0
    var siteReviews = 0
    var duplicateDecisions = 0
    var settings = 0
    var jobActions = 0
    var dataQualityReviews = 0
    var sites = 0
    var resumes = 0
    var jobFitScores = 0
    var llmRequests = 0
    var llmRequestAttempts = 0
    var contacts = 0
    var coverLetters = 0
    // Per-table orphan skip counts.
    // Policy: skip rows whose parent job is absent rather than importing dangling references.
    var skippedOrphanEvents = 0
    var skippedOrphanActions = 0
    var skippedOrphanDataQualityReviews = 0
    var skippedOrphanFitScores = 0
    var skippedOrphanLLMRequests = 0
    var skippedOrphanLLMRequestAttempts = 0
    var skippedOrphanContacts = 0
    var skippedOrphanCoverLetters = 0
    // Total orphans skipped across all tables.
    var skippedOrphans: Int {
        skippedOrphanEvents + skippedOrphanActions + skippedOrphanDataQualityReviews +
        skippedOrphanFitScores + skippedOrphanLLMRequests + skippedOrphanLLMRequestAttempts +
        skippedOrphanContacts + skippedOrphanCoverLetters
    }
    // True when the destination store already contained data — migration was skipped
    // to avoid creating duplicate records (no @Attribute(.unique) DB constraint exists).
    // Callers must ensure the destination context is empty before calling migrate().
    var skippedNonEmpty = false
}

// MARK: - Migration Logic

func migrate(src: DBHandle, context: ModelContext) -> MigrationSummary {
    var s = MigrationSummary()

    // Guard: refuse to run on a non-empty store to prevent duplicate records.
    // Capture.rawHash IS marked @Attribute(.unique) — a second migration run would
    // conflict on duplicate raw hashes (SwiftData silently merges or throws).
    // Job.id is NOT marked @Attribute(.unique) — without this guard a second run
    // would silently create duplicate job rows rather than failing safely.
    let existingCaptures = (try? context.fetch(FetchDescriptor<Capture>())) ?? []
    if !existingCaptures.isEmpty {
        s.skippedNonEmpty = true
        return s
    }

    // captures
    if tableExists(src, "captures") {
        for row in queryRows(src, "SELECT * FROM captures") {
            guard let id = row.str("id"), let rawHash = row.str("raw_hash") else { continue }
            let c = Capture(
                id: id,
                url: row.req("url"),
                canonicalURL: row.str("canonical_url"),
                pageTitle: row.req("page_title"),
                selectedText: row.str("selected_text"),
                visibleText: row.str("visible_text"),
                cleanedDescription: row.str("cleaned_description"),
                structuredDataJSON: row.str("structured_data_json"),
                userNote: row.str("user_note"),
                rawHash: rawHash,
                cleanedHash: row.str("cleaned_hash"),
                capturedAt: row.dateOrNow("captured_at"),
                createdAt: row.dateOrNow("created_at")
            )
            context.insert(c)
            s.captures += 1
        }
    }

    // Build capture lookup for linking jobs
    var captureMap: [String: Capture] = [:]
    if let all = try? context.fetch(FetchDescriptor<Capture>()) {
        for c in all { captureMap[c.id] = c }
    }

    // jobs
    var jobMap: [String: Job] = [:]
    if tableExists(src, "jobs") {
        for row in queryRows(src, "SELECT * FROM jobs") {
            guard let id = row.str("id") else { continue }
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
            if let capId = row.str("capture_id"), let cap = captureMap[capId] {
                j.capture = cap
                j.capturedAtDenormalized = cap.capturedAt
            }
            context.insert(j)
            jobMap[id] = j
            s.jobs += 1
        }
    }

    // jobMap is accumulated above during insertion rather than rebuilt via context.fetch.
    // A no-predicate fetch mid-transaction (before save) does not reliably return pending
    // inserts; relying on it previously left the lookup empty and caused every event and
    // other job-linked row to be skipped as an orphan.

    // events (legacy table name is "events", mapped to JobEvent)
    if tableExists(src, "events") {
        for row in queryRows(src, "SELECT * FROM events") {
            guard let id = row.str("id"), let jobId = row.str("job_id") else { continue }
            let ev = JobEvent(
                id: id,
                eventType: row.req("event_type"),
                note: row.str("note"),
                occurredAt: row.dateOrNow("occurred_at"),
                createdAt: row.dateOrNow("created_at")
            )
            guard let parentJob = jobMap[jobId] else { s.skippedOrphanEvents += 1; continue }
            ev.job = parentJob
            context.insert(ev)
            s.events += 1
        }
    }

    // site_reviews
    if tableExists(src, "site_reviews") {
        for row in queryRows(src, "SELECT * FROM site_reviews") {
            guard let id = row.str("id") else { continue }
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
        }
    }

    // duplicate_decisions
    if tableExists(src, "duplicate_decisions") {
        for row in queryRows(src, "SELECT * FROM duplicate_decisions") {
            guard let hash = row.str("cleaned_hash") else { continue }
            let dd = DuplicateDecision(
                cleanedHash: hash,
                decision: row.req("decision"),
                keepJobID: row.str("keep_job_id"),
                note: row.str("note"),
                decidedAt: row.dateOrNow("decided_at"),
                createdAt: row.dateOrNow("created_at")
            )
            context.insert(dd)
            s.duplicateDecisions += 1
        }
    }

    // settings
    if tableExists(src, "settings") {
        for row in queryRows(src, "SELECT * FROM settings") {
            guard let key = row.str("key"), let value = row.str("value") else { continue }
            let setting = Setting(
                key: key,
                value: value,
                updatedAt: row.dateOrNow("updated_at")
            )
            context.insert(setting)
            s.settings += 1
        }
    }

    // job_actions
    if tableExists(src, "job_actions") {
        for row in queryRows(src, "SELECT * FROM job_actions") {
            guard let id = row.str("id"), let jobId = row.str("job_id") else { continue }
            let ja = JobAction(
                id: id,
                note: row.req("note"),
                dueDate: row.dateOrNow("due_date"),
                completedAt: row.date("completed_at"),
                snoozedUntil: row.date("snoozed_until"),
                createdAt: row.dateOrNow("created_at"),
                updatedAt: row.dateOrNow("updated_at")
            )
            guard let parentJob = jobMap[jobId] else { s.skippedOrphanActions += 1; continue }
            ja.job = parentJob
            context.insert(ja)
            s.jobActions += 1
        }
    }

    // data_quality_reviews
    if tableExists(src, "data_quality_reviews") {
        for row in queryRows(src, "SELECT * FROM data_quality_reviews") {
            guard let jobId = row.str("job_id") else { continue }
            let dqr = DataQualityReview(
                reviewedAt: row.dateOrNow("reviewed_at"),
                note: row.req("note")
            )
            guard let parentJob = jobMap[jobId] else { s.skippedOrphanDataQualityReviews += 1; continue }
            dqr.job = parentJob
            context.insert(dqr)
            s.dataQualityReviews += 1
        }
    }

    // sites
    if tableExists(src, "sites") {
        let cols = columnNames(src, "sites")
        for row in queryRows(src, "SELECT * FROM sites") {
            guard let id = row.str("id") else { continue }
            let addedAt = cols.contains("added_at") ? row.dateOrNow("added_at") : row.dateOrNow("created_at")
            let site = Site(
                id: id,
                origin: row.req("origin"),
                url: row.req("url"),
                companyName: row.str("company_name"),
                companyWebsite: row.str("company_website"),
                jobsURL: row.str("jobs_url"),
                companyDescription: row.req("company_description"),
                pageTitle: row.req("page_title"),
                intervalDays: row.int("interval_days") ?? 14,
                lastReviewedAt: row.date("last_reviewed_at"),
                nextReviewAt: row.date("next_review_at"),
                note: row.req("note"),
                state: row.str("state").flatMap { SiteState(rawValue: $0) } ?? .notReviewed,
                addedAt: addedAt,
                createdAt: row.dateOrNow("created_at"),
                updatedAt: row.dateOrNow("updated_at")
            )
            context.insert(site)
            s.sites += 1
        }
    }

    // resumes
    var resumeMap: [String: Resume] = [:]
    if tableExists(src, "resumes") {
        for row in queryRows(src, "SELECT * FROM resumes") {
            guard let id = row.str("id") else { continue }
            let resume = Resume(
                id: id,
                name: row.req("name"),
                filename: row.str("filename"),
                text: row.req("text"),
                charCount: row.int("char_count") ?? 0,
                active: row.bool("active"),
                sortOrder: row.int("sort_order") ?? 0,
                createdAt: row.dateOrNow("created_at"),
                updatedAt: row.dateOrNow("updated_at")
            )
            context.insert(resume)
            resumeMap[id] = resume
            s.resumes += 1
        }
    }

    // job_fit_scores
    if tableExists(src, "job_fit_scores") {
        for row in queryRows(src, "SELECT * FROM job_fit_scores") {
            guard let jobId = row.str("job_id") else { continue }
            let jfs = JobFitScore(
                fitScore: row.int("fit_score"),
                fitStatus: row.str("fit_status").flatMap { FitStatus(rawValue: $0) } ?? .none,
                fitScoreJSON: row.str("fit_score_json"),
                model: row.str("model"),
                scoredAt: row.date("scored_at"),
                createdAt: row.dateOrNow("created_at"),
                updatedAt: row.dateOrNow("updated_at")
            )
            guard let parentJob = jobMap[jobId] else { s.skippedOrphanFitScores += 1; continue }
            jfs.job = parentJob
            if let resumeId = row.str("resume_id") {
                jfs.resume = resumeMap[resumeId]
            }
            context.insert(jfs)
            s.jobFitScores += 1
        }
    }

    // llm_requests
    var llmRequestMap: [String: LLMRequest] = [:]
    if tableExists(src, "llm_requests") {
        for row in queryRows(src, "SELECT * FROM llm_requests") {
            guard let id = row.str("id"), let jobId = row.str("job_id") else { continue }
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
            guard let parentJob = jobMap[jobId] else { s.skippedOrphanLLMRequests += 1; continue }
            req.job = parentJob
            if let resumeId = row.str("resume_id") {
                req.resume = resumeMap[resumeId]
            }
            context.insert(req)
            llmRequestMap[id] = req
            s.llmRequests += 1
        }
    }

    // llm_request_attempts
    if tableExists(src, "llm_request_attempts") {
        for row in queryRows(src, "SELECT * FROM llm_request_attempts") {
            guard let id = row.str("id"),
                  let requestId = row.str("request_id"),
                  let jobId = row.str("job_id") else { continue }
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
            guard let parentJob = jobMap[jobId] else { s.skippedOrphanLLMRequestAttempts += 1; continue }
            attempt.request = llmRequestMap[requestId]
            attempt.job = parentJob
            context.insert(attempt)
            s.llmRequestAttempts += 1
        }
    }

    // contacts
    if tableExists(src, "contacts") {
        for row in queryRows(src, "SELECT * FROM contacts") {
            guard let id = row.str("id"), let jobId = row.str("job_id") else { continue }
            let contact = Contact(
                id: id,
                name: row.req("name"),
                role: row.str("role"),
                email: row.str("email"),
                linkedinURL: row.str("linkedin_url"),
                phone: row.str("phone"),
                notes: row.str("notes"),
                createdAt: row.dateOrNow("created_at"),
                updatedAt: row.dateOrNow("updated_at")
            )
            guard let parentJob = jobMap[jobId] else { s.skippedOrphanContacts += 1; continue }
            contact.job = parentJob
            context.insert(contact)
            s.contacts += 1
        }
    }

    // cover_letters
    if tableExists(src, "cover_letters") {
        for row in queryRows(src, "SELECT * FROM cover_letters") {
            guard let id = row.str("id"), let jobId = row.str("job_id") else { continue }
            let cl = CoverLetter(
                id: id,
                content: row.req("content"),
                instructions: row.str("instructions"),
                model: row.str("model"),
                createdAt: row.dateOrNow("created_at")
            )
            guard let parentJob = jobMap[jobId] else { s.skippedOrphanCoverLetters += 1; continue }
            cl.job = parentJob
            context.insert(cl)
            s.coverLetters += 1
        }
    }

    return s
}
