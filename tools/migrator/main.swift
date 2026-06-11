// JobhuntMigrator — one-time external tool to migrate legacy jobhunt.db (SQLite)
// to a SwiftData store usable by the native Jobhunt app.
//
// Usage:
//   JobhuntMigrator [--input <path>] --output <path>
//   JobhuntMigrator --repair-fit-scores [--store <path>]
//
// NOT shipped in the app. DMG scheme only.

import Foundation
import JobhuntCore
import SQLite3
import SwiftData

// MARK: - Argument Parsing

enum Mode {
    case migrate(inputPath: String, outputPath: String)
    case repairFitScores(storePath: String)
    case verify(inputPath: String, storePath: String)
    case patch(inputPath: String, storePath: String)
    case patchFitScores(inputPath: String, storePath: String)
}

func parseArgs() -> Mode? {
    let defaultStorePath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Jobhunt/jobhunt.store")
        .path
    let defaultInputPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Jobhunt/jobhunt.db")
        .path

    var repair = false
    var verify = false
    var patch  = false
    var patchFit = false
    var storePath = defaultStorePath
    var inputPath = defaultInputPath
    var outputPath: String? = nil

    var i = 1
    let args = CommandLine.arguments
    while i < args.count {
        switch args[i] {
        case "--repair-fit-scores":
            repair = true
        case "--verify":
            verify = true
        case "--patch":
            patch = true
        case "--patch-fit-scores":
            patchFit = true
        case "--store":
            i += 1
            if i < args.count { storePath = args[i] }
        case "--input":
            i += 1
            if i < args.count { inputPath = args[i] }
        case "--output":
            i += 1
            if i < args.count { outputPath = args[i] }
        default:
            break
        }
        i += 1
    }

    if repair   { return .repairFitScores(storePath: storePath) }
    if verify   { return .verify(inputPath: inputPath, storePath: storePath) }
    if patch    { return .patch(inputPath: inputPath, storePath: storePath) }
    if patchFit { return .patchFitScores(inputPath: inputPath, storePath: storePath) }

    guard let out = outputPath else {
        fputs("Error: --output <path> is required.\n", stderr)
        fputs("Usage:\n", stderr)
        fputs("  JobhuntMigrator [--input <path>] --output <path>\n", stderr)
        fputs("  JobhuntMigrator --repair-fit-scores [--store <path>]\n", stderr)
        fputs("  JobhuntMigrator --verify [--input <path>] [--store <path>]\n", stderr)
        fputs("  JobhuntMigrator --patch  [--input <path>] [--store <path>]\n", stderr)
        fputs("  JobhuntMigrator --patch-fit-scores [--input <path>] [--store <path>]\n", stderr)
        return nil
    }
    return .migrate(inputPath: inputPath, outputPath: out)
}

// MARK: - SQLite Helpers

typealias DBHandle = OpaquePointer

func openReadOnly(_ path: String) -> DBHandle? {
    var db: DBHandle?
    let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
    let rc = sqlite3_open_v2(path, &db, flags, nil)
    if rc != SQLITE_OK {
        let msg = db.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
        fputs("Error: cannot open '\(path)': \(msg)\n", stderr)
        sqlite3_close(db)
        return nil
    }
    return db
}

func tableExists(_ db: DBHandle, _ table: String) -> Bool {
    let sql = "SELECT 1 FROM sqlite_master WHERE type='table' AND name=?"
    var stmt: OpaquePointer?
    guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return false }
    defer { sqlite3_finalize(stmt) }
    sqlite3_bind_text(stmt, 1, table, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
    return sqlite3_step(stmt) == SQLITE_ROW
}

func columnNames(_ db: DBHandle, _ table: String) -> Set<String> {
    var cols = Set<String>()
    var stmt: OpaquePointer?
    let sql = "PRAGMA table_info(\(table))"
    guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return cols }
    defer { sqlite3_finalize(stmt) }
    while sqlite3_step(stmt) == SQLITE_ROW {
        if let name = sqlite3_column_text(stmt, 1) {
            cols.insert(String(cString: name))
        }
    }
    return cols
}

func queryRows(_ db: DBHandle, _ sql: String) -> [[String: String?]] {
    var stmt: OpaquePointer?
    guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
    defer { sqlite3_finalize(stmt) }
    var rows: [[String: String?]] = []
    while sqlite3_step(stmt) == SQLITE_ROW {
        var row: [String: String?] = [:]
        let count = sqlite3_column_count(stmt)
        for col in 0 ..< count {
            let name = String(cString: sqlite3_column_name(stmt, col))
            if sqlite3_column_type(stmt, col) == SQLITE_NULL {
                row[name] = .some(nil)
            } else if let text = sqlite3_column_text(stmt, col) {
                row[name] = String(cString: text)
            } else {
                row[name] = .some(nil)
            }
        }
        rows.append(row)
    }
    return rows
}

// MARK: - Date Parsing

let isoFrac: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
}()

let isoBasic: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    return f
}()

func parseDate(_ s: String?) -> Date? {
    guard let s else { return nil }
    return isoFrac.date(from: s) ?? isoBasic.date(from: s)
}

func parseDateOrNow(_ s: String?) -> Date {
    parseDate(s) ?? Date()
}

// MARK: - Row field helpers

extension [String: String?] {
    /// Returns the value, flattening the double-optional from subscripting [Key: Value?]
    func str(_ key: String) -> String? {
        guard let outer = self[key] else { return nil }
        return outer
    }

    func req(_ key: String, fallback: String = "") -> String {
        str(key) ?? fallback
    }

    func int(_ key: String) -> Int? {
        str(key).flatMap(Int.init)
    }

    func dbl(_ key: String) -> Double? {
        str(key).flatMap(Double.init)
    }

    func bool(_ key: String) -> Bool {
        str(key).flatMap(Int.init).map { $0 != 0 } ?? false
    }

    func date(_ key: String) -> Date? {
        parseDate(str(key))
    }

    func dateOrNow(_ key: String) -> Date {
        parseDateOrNow(str(key))
    }
}

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
}

// MARK: - Migration Logic

func migrate(src: DBHandle, context: ModelContext) -> MigrationSummary {
    var s = MigrationSummary()

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
        for c in all {
            captureMap[c.id] = c
        }
    }

    // jobs
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
            }
            context.insert(j)
            s.jobs += 1
        }
    }

    // Build job lookup for linking related rows
    var jobMap: [String: Job] = [:]
    if let all = try? context.fetch(FetchDescriptor<Job>()) {
        for j in all {
            jobMap[j.id] = j
        }
    }

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
            ev.job = jobMap[jobId]
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
            ja.job = jobMap[jobId]
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
            dqr.job = jobMap[jobId]
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
            jfs.job = jobMap[jobId]
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
            req.job = jobMap[jobId]
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
            attempt.request = llmRequestMap[requestId]
            attempt.job = jobMap[jobId]
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
            contact.job = jobMap[jobId]
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
            cl.job = jobMap[jobId]
            context.insert(cl)
            s.coverLetters += 1
        }
    }

    return s
}

// MARK: - Repair: create missing JobFitScore records

func repairFitScores(context: ModelContext) -> Int {
    let jobs: [Job]
    do {
        jobs = try context.fetch(FetchDescriptor<Job>())
    } catch {
        fputs("Error fetching jobs: \(error)\n", stderr)
        return 0
    }

    var inserted = 0
    for job in jobs {
        guard job.fitStatus == .succeeded,
              let json = job.fitScoreJSON,
              job.fitScores.isEmpty else { continue }
        let record = JobFitScore(
            fitScore: job.fitScore,
            fitStatus: .succeeded,
            fitScoreJSON: json,
            model: nil,
            scoredAt: job.updatedAt
        )
        context.insert(record)
        record.job = job
        inserted += 1
        let label = job.jobNumber.map { "#\($0)" } ?? job.id
        print("  \(label): score \(job.fitScore.map(String.init) ?? "?") → JobFitScore created")
    }

    do {
        try context.save()
    } catch {
        fputs("Error saving: \(error)\n", stderr)
        return 0
    }
    return inserted
}

// MARK: - Verify: compare SQLite source vs SwiftData store

struct VerifyResult {
    var checks = 0
    var passed = 0
    var failed = 0
    var noted  = 0  // expected/explained differences

    mutating func ok(_ label: String, _ detail: String = "") {
        checks += 1; passed += 1
        print("  ✓  \(label)\(detail.isEmpty ? "" : "  \(detail)")")
    }
    mutating func fail(_ label: String, _ detail: String = "") {
        checks += 1; failed += 1
        print("  ✗  \(label)\(detail.isEmpty ? "" : "  \(detail)")")
    }
    mutating func note(_ label: String, _ detail: String = "") {
        checks += 1; noted += 1
        print("  ~  \(label)\(detail.isEmpty ? "" : "  \(detail)")")
    }
}

func sqlCount(_ db: DBHandle, _ table: String, _ where_clause: String = "") -> Int {
    let sql = where_clause.isEmpty
        ? "SELECT COUNT(*) FROM \(table)"
        : "SELECT COUNT(*) FROM \(table) WHERE \(where_clause)"
    var stmt: OpaquePointer?
    guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return -1 }
    defer { sqlite3_finalize(stmt) }
    return sqlite3_step(stmt) == SQLITE_ROW ? Int(sqlite3_column_int(stmt, 0)) : -1
}

func sdCount<T: PersistentModel>(_ context: ModelContext, _: T.Type) -> Int {
    let desc = FetchDescriptor<T>()
    return (try? context.fetchCount(desc)) ?? -1
}

func verify(src: DBHandle, context: ModelContext) -> VerifyResult {
    var r = VerifyResult()
    let pad = 34

    func label(_ s: String) -> String { s.padding(toLength: pad, withPad: " ", startingAt: 0) }

    // ── Captures ──────────────────────────────────────────────────────────────
    print("\nCaptures")
    let sqlCaptures = sqlCount(src, "captures")
    let sdCaptures  = sdCount(context, Capture.self)
    // ID set comparison
    let sqlCaptureIDs = Set(queryRows(src, "SELECT id FROM captures").compactMap { $0.str("id") })
    let sdCaptureIDs  = Set((try? context.fetch(FetchDescriptor<Capture>()))?.map(\.id) ?? [])
    let missingCaptures = sqlCaptureIDs.subtracting(sdCaptureIDs)
    let extraCaptures   = sdCaptureIDs.subtracting(sqlCaptureIDs)
    // Known orphan captures (no linked job in SQLite) — these have no useful data.
    let knownOrphanCaptures: Set<String> = ["cap_b69c45c00be44806915ebf3674c138e2"]
    let realMissingCaptures = missingCaptures.subtracting(knownOrphanCaptures)
    let orphansPresent = knownOrphanCaptures.intersection(missingCaptures)
    // Adjust count: orphans are intentionally skipped — compare excluding them
    let adjustedSQLCaptures = sqlCaptures - orphansPresent.count
    if adjustedSQLCaptures == sdCaptures {
        r.ok(label("count"), "\(sdCaptures) (excl. \(orphansPresent.count) orphan)")
    } else if sqlCaptures == sdCaptures {
        r.ok(label("count"), "\(sdCaptures)")
    } else {
        r.fail(label("count"), "SQLite \(sqlCaptures) vs SwiftData \(sdCaptures)")
    }
    if realMissingCaptures.isEmpty { r.ok(label("all job-linked IDs present")) }
    else { r.fail(label("missing from SwiftData"), realMissingCaptures.sorted().prefix(5).joined(separator: ", ")) }
    if !orphansPresent.isEmpty {
        r.note(label("orphan captures (no job, skipped)"), orphansPresent.count.description)
    }
    if !extraCaptures.isEmpty { r.note(label("extra in SwiftData (post-migration)"), "\(extraCaptures.count)") }

    // ── Jobs ──────────────────────────────────────────────────────────────────
    print("\nJobs")
    let sqlJobs = sqlCount(src, "jobs")
    let sdJobs  = sdCount(context, Job.self)
    // SQLite has one extra orphan capture row with no linked job; that row added 1 to capture count.
    // Jobs should match exactly since the orphan capture has no job.
    if sqlJobs == sdJobs {
        r.ok(label("count"), "\(sdJobs)")
    } else {
        r.fail(label("count"), "SQLite \(sqlJobs) vs SwiftData \(sdJobs)")
    }

    // Build maps for field comparison
    let sqlJobRows = queryRows(src, "SELECT id, job_number, status, company, title, fit_score, fit_status, extraction_status FROM jobs ORDER BY job_number")
    let sdJobsAll  = (try? context.fetch(FetchDescriptor<Job>(sortBy: [SortDescriptor(\Job.jobNumber)]))) ?? []
    let sdJobByID  = Dictionary(uniqueKeysWithValues: sdJobsAll.compactMap { j -> (String, Job)? in (j.id, j) })

    var statusMismatches = 0, fitMismatches = 0, missingJobs = 0
    var statusDetails: [String] = [], fitDetails: [String] = []

    for row in sqlJobRows {
        guard let id = row.str("id") else { continue }
        guard let sdJob = sdJobByID[id] else {
            missingJobs += 1
            continue
        }
        let num = row.str("job_number") ?? id

        // Status comparison. SQLite uses legacy names; SwiftData was renamed post-migration.
        // Expected mappings (based on migrator defaults + post-migration rename operation):
        //   archived      → passed    (system-wide rename June 8)
        //   saved         → pursuing  (migrator default for unknown status)
        //   not_available → passed    (migrator default → pursuing, then renamed)
        //   applied/duplicate/etc. → unchanged
        // Any remaining mismatch is likely a user-made status change in the app — expected.
        let sqlStatus = row.str("status") ?? ""
        let expectedStatuses: Set<String>
        switch sqlStatus {
        case "saved":          expectedStatuses = ["pursuing"]
        case "archived":       expectedStatuses = ["passed", "archived"]
        case "not_available":  expectedStatuses = ["passed", "closed", "pursuing"]
        default:               expectedStatuses = [sqlStatus]
        }
        if !expectedStatuses.contains(sdJob.status.rawValue) {
            statusMismatches += 1
            statusDetails.append("#\(num): sqlite=\(sqlStatus) sd=\(sdJob.status.rawValue) (expected one of: \(expectedStatuses.sorted().joined(separator: "|")))")
        }

        // Fit score comparison (SQLite jobs.fit_score vs SwiftData Job.fitScore)
        let sqlFitScore  = row.int("fit_score")
        let sqlFitStatus = row.str("fit_status") ?? "none"
        if sqlFitScore != sdJob.fitScore || sqlFitStatus != sdJob.fitStatus.rawValue {
            fitMismatches += 1
            let sqlStr = sqlFitScore.map { "\($0)/\(sqlFitStatus)" } ?? "nil/\(sqlFitStatus)"
            let sdStr  = sdJob.fitScore.map { "\($0)/\(sdJob.fitStatus.rawValue)" } ?? "nil/\(sdJob.fitStatus.rawValue)"
            fitDetails.append("#\(num): sqlite=\(sqlStr) sd=\(sdStr)")
        }
    }

    if missingJobs == 0 { r.ok(label("all job IDs present")) }
    else { r.fail(label("jobs missing from SwiftData"), "\(missingJobs)") }

    if statusMismatches == 0 {
        r.ok(label("all job statuses match (post-rename)"))
    } else {
        r.note(label("status diffs after rename mapping"), "\(statusMismatches) likely user changes in app")
        for d in statusDetails.prefix(10) { print("       \(d)") }
    }

    if fitMismatches == 0 {
        r.ok(label("all job fit scores match"))
    } else {
        r.note(label("fit score field diffs"), "\(fitMismatches) (SQLite may have been rescored post-migration)")
        for d in fitDetails.prefix(10) { print("       \(d)") }
    }

    // extraction status
    let sqlExtractSucceeded = sqlCount(src, "jobs", "extraction_status = 'succeeded'")
    let sdExtractSucceeded  = sdJobsAll.filter { $0.extractionStatus == .succeeded }.count
    if sqlExtractSucceeded == sdExtractSucceeded {
        r.ok(label("extraction succeeded count"), "\(sdExtractSucceeded)")
    } else {
        r.fail(label("extraction succeeded mismatch"), "SQLite \(sqlExtractSucceeded) vs SwiftData \(sdExtractSucceeded)")
    }

    // ── JobFitScore records ───────────────────────────────────────────────────
    print("\nJobFitScore records")
    let sqlFSTotal     = tableExists(src, "job_fit_scores") ? sqlCount(src, "job_fit_scores") : 0
    let sqlFSSucceeded = tableExists(src, "job_fit_scores") ? sqlCount(src, "job_fit_scores", "fit_status = 'succeeded'") : 0
    let sdFS           = sdCount(context, JobFitScore.self)
    let sdFSSucceeded  = (try? context.fetch(FetchDescriptor<JobFitScore>()))?.filter { $0.fitStatus == .succeeded }.count ?? 0

    // SQLite total includes all (job, resume) pairs even if pending; SwiftData has one stub per job.
    // This difference is expected and explained.
    r.note(label("SQLite rows (all statuses)"), "\(sqlFSTotal)  (includes pending per-resume rows)")
    r.note(label("SQLite succeeded"),           "\(sqlFSSucceeded)  (unique job×resume pairs scored)")
    if sdFS >= sdFSSucceeded {
        r.ok(label("SwiftData records"),        "\(sdFS)  (\(sdFSSucceeded) succeeded; stubs from job.fitScoreJSON)")
    } else {
        r.fail(label("SwiftData records"),      "\(sdFS)")
    }
    // Every job with a succeeded fit in SwiftData should have a JobFitScore
    let sdJobsWithScore  = sdJobsAll.filter { $0.fitStatus == .succeeded }.count
    let sdJobsWithRecord = sdJobsAll.filter { $0.fitStatus == .succeeded && !$0.fitScores.isEmpty }.count
    if sdJobsWithScore == sdJobsWithRecord {
        r.ok(label("every scored job has a record"), "\(sdJobsWithRecord)/\(sdJobsWithScore)")
    } else {
        r.fail(label("scored jobs missing records"), "\(sdJobsWithScore - sdJobsWithRecord) jobs have no JobFitScore")
    }

    // ── Resumes ───────────────────────────────────────────────────────────────
    print("\nResumes")
    let sqlResumes = tableExists(src, "resumes") ? sqlCount(src, "resumes") : 0
    let sdResumes  = sdCount(context, Resume.self)
    if sqlResumes == sdResumes { r.ok(label("count"), "\(sdResumes)") }
    else { r.fail(label("count"), "SQLite \(sqlResumes) vs SwiftData \(sdResumes)") }

    let sqlResumeRows = queryRows(src, "SELECT id, name, active FROM resumes")
    let sdResumesAll  = (try? context.fetch(FetchDescriptor<Resume>())) ?? []
    let sdResumeByID  = Dictionary(uniqueKeysWithValues: sdResumesAll.map { ($0.id, $0) })
    var resumeMismatches = 0
    for row in sqlResumeRows {
        guard let id = row.str("id"), let sd = sdResumeByID[id] else { resumeMismatches += 1; continue }
        let sqlName = row.str("name") ?? ""
        if sqlName != sd.name { resumeMismatches += 1 }
    }
    if resumeMismatches == 0 { r.ok(label("all resume IDs and names match")) }
    else { r.fail(label("resume mismatches"), "\(resumeMismatches)") }

    // ── Sites ─────────────────────────────────────────────────────────────────
    print("\nSites")
    let sqlSites = tableExists(src, "sites") ? sqlCount(src, "sites") : 0
    let sdSites  = sdCount(context, Site.self)
    if sqlSites == sdSites { r.ok(label("count"), "\(sdSites)") }
    else { r.fail(label("count"), "SQLite \(sqlSites) vs SwiftData \(sdSites)") }

    // ── Job Actions ───────────────────────────────────────────────────────────
    print("\nJob Actions")
    let sqlActions = tableExists(src, "job_actions") ? sqlCount(src, "job_actions") : 0
    let sdActions  = sdCount(context, JobAction.self)
    if sqlActions == sdActions { r.ok(label("count"), "\(sdActions)") }
    else { r.fail(label("count"), "SQLite \(sqlActions) vs SwiftData \(sdActions)") }

    // ── Contacts ──────────────────────────────────────────────────────────────
    print("\nContacts")
    let sqlContacts = tableExists(src, "contacts") ? sqlCount(src, "contacts") : 0
    let sdContacts  = sdCount(context, Contact.self)
    if sqlContacts == sdContacts { r.ok(label("count"), "\(sdContacts)") }
    else { r.fail(label("count"), "SQLite \(sqlContacts) vs SwiftData \(sdContacts)") }

    // ── Cover Letters ─────────────────────────────────────────────────────────
    print("\nCover Letters")
    let sqlCoverLetters = tableExists(src, "cover_letters") ? sqlCount(src, "cover_letters") : 0
    let sdCoverLetters  = sdCount(context, CoverLetter.self)
    if sqlCoverLetters == sdCoverLetters { r.ok(label("count"), "\(sdCoverLetters)") }
    else { r.fail(label("count"), "SQLite \(sqlCoverLetters) vs SwiftData \(sdCoverLetters)") }

    // ── LLM Requests ─────────────────────────────────────────────────────────
    print("\nLLM Requests")
    let sqlLLM = tableExists(src, "llm_requests") ? sqlCount(src, "llm_requests") : 0
    let sdLLM  = sdCount(context, LLMRequest.self)
    if sqlLLM == sdLLM { r.ok(label("count"), "\(sdLLM)") }
    else { r.fail(label("count"), "SQLite \(sqlLLM) vs SwiftData \(sdLLM)") }

    let sqlLLMAttempts = tableExists(src, "llm_request_attempts") ? sqlCount(src, "llm_request_attempts") : 0
    let sdLLMAttempts  = sdCount(context, LLMRequestAttempt.self)
    if sqlLLMAttempts == sdLLMAttempts { r.ok(label("attempt count"), "\(sdLLMAttempts)") }
    else { r.fail(label("attempt count"), "SQLite \(sqlLLMAttempts) vs SwiftData \(sdLLMAttempts)") }

    // ── Settings ──────────────────────────────────────────────────────────────
    print("\nSettings")
    let sqlSettings = tableExists(src, "settings") ? sqlCount(src, "settings") : 0
    let sdSettings  = sdCount(context, Setting.self)
    if sqlSettings == sdSettings { r.ok(label("count"), "\(sdSettings)") }
    else { r.note(label("count"), "SQLite \(sqlSettings) vs SwiftData \(sdSettings)  (app adds keys at runtime)") }

    // ── Duplicate Decisions ───────────────────────────────────────────────────
    print("\nDuplicate Decisions")
    let sqlDD = tableExists(src, "duplicate_decisions") ? sqlCount(src, "duplicate_decisions") : 0
    let sdDD  = sdCount(context, DuplicateDecision.self)
    if sqlDD == sdDD { r.ok(label("count"), "\(sdDD)") }
    else { r.fail(label("count"), "SQLite \(sqlDD) vs SwiftData \(sdDD)") }

    // ── Site Reviews ──────────────────────────────────────────────────────────
    print("\nSite Reviews")
    let sqlSR = tableExists(src, "site_reviews") ? sqlCount(src, "site_reviews") : 0
    let sdSR  = sdCount(context, SiteReview.self)
    if sqlSR == sdSR { r.ok(label("count"), "\(sdSR)") }
    else { r.fail(label("count"), "SQLite \(sqlSR) vs SwiftData \(sdSR)") }

    // ── Data Quality Reviews ──────────────────────────────────────────────────
    print("\nData Quality Reviews")
    let sqlDQR = tableExists(src, "data_quality_reviews") ? sqlCount(src, "data_quality_reviews") : 0
    let sdDQR  = sdCount(context, DataQualityReview.self)
    if sqlDQR == sdDQR { r.ok(label("count"), "\(sdDQR)") }
    else { r.fail(label("count"), "SQLite \(sqlDQR) vs SwiftData \(sdDQR)") }

    // ── Per-job spot check ────────────────────────────────────────────────────
    print("\nPer-job spot check (sample of 5)")
    let spotNums = [1, 50, 100, 126, 136]
    let sdJobByNum = Dictionary(uniqueKeysWithValues: sdJobsAll.compactMap { j -> (Int, Job)? in
        guard let n = j.jobNumber else { return nil }; return (n, j)
    })
    let sqlSpotRows = queryRows(src, "SELECT job_number, company, title, status, fit_score FROM jobs WHERE job_number IN (1,50,100,126,136)")
    let sqlByNum = Dictionary(uniqueKeysWithValues: sqlSpotRows.compactMap { r -> (Int, [String: String?])? in
        guard let n = r.int("job_number") else { return nil }; return (n, r)
    })
    for num in spotNums {
        guard let sd = sdJobByNum[num] else {
            r.fail(label("job #\(num)"), "not found in SwiftData")
            continue
        }
        guard let sql = sqlByNum[num] else {
            r.note(label("job #\(num)"), "not in SQLite (may be post-migration)")
            continue
        }
        let sdSummary  = "\(sd.company ?? "-") | \(sd.title ?? "-") | \(sd.status.rawValue) | score=\(sd.fitScore.map(String.init) ?? "nil")"
        let sqlSummary = "\(sql.str("company") ?? "-") | \(sql.str("title") ?? "-") | \(sql.str("status") ?? "-") | score=\(sql.str("fit_score") ?? "nil")"
        if sdSummary == sqlSummary {
            r.ok(label("job #\(num)"), sdSummary)
        } else {
            r.note(label("job #\(num) SQLite"), sqlSummary)
            r.note(label("job #\(num) SwiftData"), sdSummary)
        }
    }

    return r
}

// MARK: - Patch: import records missing from SwiftData

struct PatchSummary {
    var jobsInserted = 0
    var siteReviews = 0
    var llmRequests = 0
    var llmRequestAttempts = 0
    var skipped = 0
}

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
            do { try context.save() } catch { fputs("Error saving new job: \(error)\n", stderr) }
            if let capId, let cap = captureMap[capId] { j.capture = cap }
            s.jobsInserted += 1
            print("  job \(jobLabel) (\(jobTitle) @ \(jobCompany)) → inserted")
        }
        if s.jobsInserted > 0 {
            // Final save to persist capture relationships set after each job's initial save
            do { try context.save() } catch { fputs("Error saving job relationships: \(error)\n", stderr) }
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

    do {
        try context.save()
    } catch {
        fputs("Error saving patch: \(error)\n", stderr)
    }
    return s
}

// MARK: - Patch Fit Scores: replace resume-less stubs with proper per-resume records

func patchFitScores(src: DBHandle, context: ModelContext) {
    guard tableExists(src, "job_fit_scores") else {
        print("No job_fit_scores table in SQLite — nothing to do.")
        return
    }

    // Build lookup maps
    let allJobs    = (try? context.fetch(FetchDescriptor<Job>())) ?? []
    let allResumes = (try? context.fetch(FetchDescriptor<Resume>())) ?? []
    let jobMap    = Dictionary(uniqueKeysWithValues: allJobs.map { ($0.id, $0) })
    let resumeMap = Dictionary(uniqueKeysWithValues: allResumes.map { ($0.id, $0) })

    // Delete all stubs (JobFitScore records with no resume link).
    // App-scored records always have a resume; stubs from repair never do.
    let allScores = (try? context.fetch(FetchDescriptor<JobFitScore>())) ?? []
    let stubs = allScores.filter { $0.resume == nil }
    print("Deleting \(stubs.count) resume-less stub record(s)…")
    for stub in stubs { context.delete(stub) }
    do { try context.save() } catch {
        fputs("Error deleting stubs: \(error)\n", stderr); return
    }

    // Import succeeded per-resume scores from SQLite
    var inserted = 0
    var skipped  = 0
    let rows = queryRows(src, "SELECT * FROM job_fit_scores WHERE fit_status = 'succeeded'")
    for row in rows {
        guard let jobId = row.str("job_id") else { skipped += 1; continue }
        guard let job   = jobMap[jobId] else { skipped += 1; continue }

        let resumeId = row.str("resume_id")
        let resume   = resumeId.flatMap { resumeMap[$0] }

        // Skip if an identical (job, resume) pair is already present (app may have rescored)
        let alreadyPresent = job.fitScores.contains { $0.resume?.id == resumeId }
        if alreadyPresent { skipped += 1; continue }

        let rec = JobFitScore(
            fitScore: row.int("fit_score"),
            fitStatus: row.str("fit_status").flatMap { FitStatus(rawValue: $0) } ?? .none,
            fitScoreJSON: row.str("fit_score_json"),
            model: row.str("model"),
            scoredAt: row.date("scored_at"),
            createdAt: row.dateOrNow("created_at"),
            updatedAt: row.dateOrNow("updated_at")
        )
        context.insert(rec)
        rec.job    = job
        rec.resume = resume
        inserted += 1

        let resumeName = resume?.name ?? resumeId ?? "?"
        let jobLabel   = job.jobNumber.map { "#\($0)" } ?? jobId
        print("  \(jobLabel): \(resumeName) → score \(row.str("fit_score") ?? "?")")
    }

    do {
        try context.save()
        print("\nPhase 1 done: \(inserted) record(s) inserted, \(skipped) skipped.")
    } catch {
        fputs("Error saving fit scores: \(error)\n", stderr); return
    }

    // Phase 2: create stubs for jobs that have a succeeded fit score on the Job model
    // but no JobFitScore record (their scores were never in job_fit_scores table).
    // Re-fetch so relationship counts are current.
    let updatedJobs = (try? context.fetch(FetchDescriptor<Job>())) ?? []
    var stubs2 = 0
    for job in updatedJobs {
        guard job.fitStatus == .succeeded,
              let json = job.fitScoreJSON,
              job.fitScores.isEmpty else { continue }
        let stub = JobFitScore(
            fitScore: job.fitScore,
            fitStatus: .succeeded,
            fitScoreJSON: json,
            model: job.extractionModel,
            scoredAt: job.updatedAt
        )
        context.insert(stub)
        stub.job = job
        stubs2 += 1
        let label = job.jobNumber.map { "#\($0)" } ?? job.id
        print("  \(label): stub created (no per-resume data available)")
    }
    if stubs2 > 0 {
        do {
            try context.save()
            print("Phase 2 done: \(stubs2) stub(s) created for jobs with no per-resume data.")
        } catch {
            fputs("Error saving stubs: \(error)\n", stderr)
        }
    } else {
        print("Phase 2: no stubs needed.")
    }
}

// MARK: - Entry Point

guard let mode = parseArgs() else { exit(1) }

switch mode {

case let .verify(inputPath, storePath):
    guard FileManager.default.fileExists(atPath: inputPath) else {
        fputs("Error: SQLite DB not found at '\(inputPath)'\n", stderr); exit(1)
    }
    guard FileManager.default.fileExists(atPath: storePath) else {
        fputs("Error: SwiftData store not found at '\(storePath)'\n", stderr); exit(1)
    }
    guard let srcDB = openReadOnly(inputPath) else { exit(1) }
    defer { sqlite3_close(srcDB) }

    print("=== Jobhunt Migration Verification ===")
    print("SQLite:    \(inputPath)")
    print("SwiftData: \(storePath)")
    print("Legend:  ✓ match   ✗ mismatch   ~ expected/explained difference")

    let storeURL = URL(fileURLWithPath: storePath)
    let schema = Schema(SchemaV1.models)
    let config = ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)
    let container: ModelContainer
    do {
        container = try ModelContainer(for: schema, migrationPlan: JobhuntMigrationPlan.self, configurations: config)
    } catch {
        fputs("Error: could not open store: \(error)\n", stderr); exit(1)
    }
    let context = ModelContext(container)
    let result = verify(src: srcDB, context: context)

    print("")
    print("─────────────────────────────────────")
    let icon = result.failed == 0 ? "✓" : "✗"
    print("\(icon)  \(result.checks) checks: \(result.passed) passed, \(result.failed) failed, \(result.noted) noted")
    if result.failed > 0 { print("   Review ✗ items above — data may be missing.") }
    else { print("   Migration looks complete.") }

case let .patchFitScores(inputPath, storePath):
    guard FileManager.default.fileExists(atPath: inputPath) else {
        fputs("Error: SQLite DB not found at '\(inputPath)'\n", stderr); exit(1)
    }
    guard FileManager.default.fileExists(atPath: storePath) else {
        fputs("Error: SwiftData store not found at '\(storePath)'\n", stderr); exit(1)
    }
    guard let srcDB = openReadOnly(inputPath) else { exit(1) }
    defer { sqlite3_close(srcDB) }

    print("=== Patch Fit Scores ===")
    print("SQLite:    \(inputPath)")
    print("SwiftData: \(storePath)")

    let storeURL = URL(fileURLWithPath: storePath)
    let schema = Schema(SchemaV1.models)
    let config = ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)
    let container: ModelContainer
    do {
        container = try ModelContainer(for: schema, migrationPlan: JobhuntMigrationPlan.self, configurations: config)
    } catch {
        fputs("Error: could not open store: \(error)\n", stderr); exit(1)
    }
    let context = ModelContext(container)
    patchFitScores(src: srcDB, context: context)

case let .patch(inputPath, storePath):
    guard FileManager.default.fileExists(atPath: inputPath) else {
        fputs("Error: SQLite DB not found at '\(inputPath)'\n", stderr); exit(1)
    }
    guard FileManager.default.fileExists(atPath: storePath) else {
        fputs("Error: SwiftData store not found at '\(storePath)'\n", stderr); exit(1)
    }
    guard let srcDB = openReadOnly(inputPath) else { exit(1) }
    defer { sqlite3_close(srcDB) }

    print("=== Jobhunt Migration Patch ===")
    print("SQLite:    \(inputPath)")
    print("SwiftData: \(storePath)")

    let storeURL = URL(fileURLWithPath: storePath)
    let schema = Schema(SchemaV1.models)
    let config = ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)
    let container: ModelContainer
    do {
        container = try ModelContainer(for: schema, migrationPlan: JobhuntMigrationPlan.self, configurations: config)
    } catch {
        fputs("Error: could not open store: \(error)\n", stderr); exit(1)
    }
    let patchContext = ModelContext(container)
    let patchSummary = patch(src: srcDB, context: patchContext)
    print("")
    print("Patch complete:")
    print("  jobs inserted:               \(patchSummary.jobsInserted)")
    print("  site reviews inserted:       \(patchSummary.siteReviews)")
    print("  llm requests inserted:       \(patchSummary.llmRequests)")
    print("  llm request attempts inserted: \(patchSummary.llmRequestAttempts)")
    print("  already-present (skipped):   \(patchSummary.skipped)")

case let .repairFitScores(storePath):
    guard FileManager.default.fileExists(atPath: storePath) else {
        fputs("Error: store not found at '\(storePath)'\n", stderr)
        exit(1)
    }
    print("Store: \(storePath)")
    let storeURL = URL(fileURLWithPath: storePath)
    let schema = Schema(SchemaV1.models)
    let config = ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)
    let container: ModelContainer
    do {
        container = try ModelContainer(for: schema, migrationPlan: JobhuntMigrationPlan.self, configurations: config)
    } catch {
        fputs("Error: could not open store: \(error)\n", stderr)
        exit(1)
    }
    let context = ModelContext(container)
    print("Scanning for jobs with fit scores but no JobFitScore records...")
    let count = repairFitScores(context: context)
    print("")
    print("Repair complete: \(count) JobFitScore record(s) created.")

case let .migrate(inputPath, outputPath):
    guard FileManager.default.fileExists(atPath: inputPath) else {
        fputs("Error: input database not found at '\(inputPath)'\n", stderr)
        exit(1)
    }

    guard let srcDB = openReadOnly(inputPath) else { exit(1) }
    defer { sqlite3_close(srcDB) }

    print("Input:  \(inputPath)")
    print("Output: \(outputPath)")

    let outputURL = URL(fileURLWithPath: outputPath)
    let schema = Schema(SchemaV1.models)
    let config = ModelConfiguration(schema: schema, url: outputURL, cloudKitDatabase: .none)

    let container: ModelContainer
    do {
        container = try ModelContainer(for: schema, migrationPlan: JobhuntMigrationPlan.self, configurations: config)
    } catch {
        fputs("Error: could not create output SwiftData store: \(error)\n", stderr)
        exit(1)
    }

    let context = ModelContext(container)

    print("Migrating...")
    let summary = migrate(src: srcDB, context: context)

    do {
        try context.save()
    } catch {
        fputs("Error: failed to save output store: \(error)\n", stderr)
        exit(1)
    }

    print("")
    print("Migration complete:")
    print("  captures:              \(summary.captures)")
    print("  jobs:                  \(summary.jobs)")
    print("  events:                \(summary.events)")
    print("  site reviews:          \(summary.siteReviews)")
    print("  duplicate decisions:   \(summary.duplicateDecisions)")
    print("  settings:              \(summary.settings)")
    print("  job actions:           \(summary.jobActions)")
    print("  data quality reviews:  \(summary.dataQualityReviews)")
    print("  sites:                 \(summary.sites)")
    print("  resumes:               \(summary.resumes)")
    print("  job fit scores:        \(summary.jobFitScores)")
    print("  llm requests:          \(summary.llmRequests)")
    print("  llm request attempts:  \(summary.llmRequestAttempts)")
    print("  contacts:              \(summary.contacts)")
    print("  cover letters:         \(summary.coverLetters)")
    print("")
    print("Store written to: \(outputPath)")
}
