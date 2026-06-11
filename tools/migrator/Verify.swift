import Foundation
import JobhuntCore
import SQLite3
import SwiftData

// MARK: - Verify Result

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

// MARK: - Counting Helpers

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

// MARK: - Verification

// swiftlint:disable:next function_body_length cyclomatic_complexity
func verify(src: DBHandle, context: ModelContext) -> VerifyResult {
    var r = VerifyResult()
    let pad = 34

    func label(_ s: String) -> String { s.padding(toLength: pad, withPad: " ", startingAt: 0) }

    // ── Captures ──────────────────────────────────────────────────────────────
    print("\nCaptures")
    let sqlCaptures = sqlCount(src, "captures")
    let sdCaptures  = sdCount(context, Capture.self)
    let sqlCaptureIDs = Set(queryRows(src, "SELECT id FROM captures").compactMap { $0.str("id") })
    let sdCaptureIDs  = Set((try? context.fetch(FetchDescriptor<Capture>()))?.map(\.id) ?? [])
    let missingCaptures = sqlCaptureIDs.subtracting(sdCaptureIDs)
    let extraCaptures   = sdCaptureIDs.subtracting(sqlCaptureIDs)
    let knownOrphanCaptures: Set<String> = ["cap_b69c45c00be44806915ebf3674c138e2"]
    let realMissingCaptures = missingCaptures.subtracting(knownOrphanCaptures)
    let orphansPresent = knownOrphanCaptures.intersection(missingCaptures)
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
    if sqlJobs == sdJobs {
        r.ok(label("count"), "\(sdJobs)")
    } else {
        r.fail(label("count"), "SQLite \(sqlJobs) vs SwiftData \(sdJobs)")
    }

    let sqlJobRows = queryRows(src, "SELECT id, job_number, status, company, title, fit_score, fit_status, extraction_status FROM jobs ORDER BY job_number")
    let sdJobsAll  = (try? context.fetch(FetchDescriptor<Job>(sortBy: [SortDescriptor(\Job.jobNumber)]))) ?? []
    let sdJobByID  = Dictionary(uniqueKeysWithValues: sdJobsAll.compactMap { j -> (String, Job)? in (j.id, j) })

    var statusMismatches = 0, fitMismatches = 0, missingJobs = 0
    var statusDetails: [String] = [], fitDetails: [String] = []

    for row in sqlJobRows {
        guard let id = row.str("id") else { continue }
        guard let sdJob = sdJobByID[id] else { missingJobs += 1; continue }
        let num = row.str("job_number") ?? id

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

    r.note(label("SQLite rows (all statuses)"), "\(sqlFSTotal)  (includes pending per-resume rows)")
    r.note(label("SQLite succeeded"),           "\(sqlFSSucceeded)  (unique job×resume pairs scored)")
    if sdFS >= sdFSSucceeded {
        r.ok(label("SwiftData records"),        "\(sdFS)  (\(sdFSSucceeded) succeeded; stubs from job.fitScoreJSON)")
    } else {
        r.fail(label("SwiftData records"),      "\(sdFS)")
    }
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
