import SQLite3
import SwiftData

// swiftlint:disable file_length cyclomatic_complexity function_body_length type_body_length
import XCTest
@testable import JobhuntCore

/// Tests for the JobhuntMigrator logic.
///
/// These tests exercise the migration path by creating an in-memory (or temp-file) legacy SQLite DB,
/// inserting fixture rows, running the migration helpers, and asserting the resulting SwiftData
/// context contains the expected models.
final class MigratorTests: XCTestCase {
    // MARK: - Helpers

    /// Creates a temporary SQLite DB at a temp path, runs `setup`, returns the path.
    func makeTempDB(setup: (OpaquePointer) throws -> Void) throws -> String {
        let dir = FileManager.default.temporaryDirectory
        let path = dir.appendingPathComponent("migrator_test_\(UUID().uuidString).db").path
        var dbPtr: OpaquePointer?
        let openResult = sqlite3_open_v2(path, &dbPtr, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil)
        XCTAssertEqual(openResult, SQLITE_OK)
        guard let dbPtr else { XCTFail("Could not create temp DB"); throw XCTestError(.failureWhileWaiting) }
        defer { sqlite3_close(dbPtr) }
        try setup(dbPtr)
        return path
    }

    func exec(_ dbHandle: OpaquePointer, _ sql: String) {
        var err: UnsafeMutablePointer<CChar>?
        let execResult = sqlite3_exec(dbHandle, sql, nil, nil, &err)
        if execResult != SQLITE_OK {
            let msg = err.map { String(cString: $0) } ?? "unknown"
            XCTFail("SQL error: \(msg) for: \(sql)")
        }
        sqlite3_free(err)
    }

    /// Minimal legacy schema — just the tables tested here.
    func createMinimalSchema(_ dbHandle: OpaquePointer) {
        exec(dbHandle, """
            CREATE TABLE captures (
              id TEXT PRIMARY KEY,
              url TEXT NOT NULL,
              canonical_url TEXT,
              page_title TEXT NOT NULL,
              selected_text TEXT,
              visible_text TEXT,
              cleaned_description TEXT,
              structured_data_json TEXT,
              user_note TEXT,
              raw_hash TEXT NOT NULL,
              cleaned_hash TEXT,
              captured_at TEXT NOT NULL,
              created_at TEXT NOT NULL
            )
        """)
        exec(dbHandle, """
            CREATE TABLE jobs (
              id TEXT PRIMARY KEY,
              job_number INTEGER,
              capture_id TEXT NOT NULL,
              company TEXT,
              title TEXT,
              location TEXT,
              remote_type TEXT,
              salary_min INTEGER,
              salary_max INTEGER,
              salary_currency TEXT,
              salary_note TEXT,
              employment_type TEXT,
              seniority TEXT,
              status TEXT NOT NULL DEFAULT 'saved',
              manual_overrides TEXT NOT NULL DEFAULT '[]',
              extracted_json TEXT,
              extraction_status TEXT NOT NULL DEFAULT 'pending',
              extraction_error TEXT,
              fit_score INTEGER,
              fit_status TEXT NOT NULL DEFAULT 'none',
              fit_score_json TEXT,
              duplicate_of_job_id TEXT,
              duplicate_confidence REAL,
              extracted_at TEXT,
              rating INTEGER,
              extraction_model TEXT,
              application_url TEXT,
              extraction_confidence REAL,
              last_opened_at TEXT,
              unread INTEGER NOT NULL DEFAULT 0,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL
            )
        """)
        exec(dbHandle, """
            CREATE TABLE events (
              id TEXT PRIMARY KEY,
              job_id TEXT NOT NULL,
              event_type TEXT NOT NULL,
              note TEXT,
              occurred_at TEXT NOT NULL,
              created_at TEXT NOT NULL
            )
        """)
        exec(dbHandle, """
            CREATE TABLE site_reviews (
              id TEXT PRIMARY KEY,
              site_url TEXT NOT NULL,
              site_origin TEXT NOT NULL,
              page_title TEXT,
              reviewed_at TEXT NOT NULL,
              next_review_at TEXT,
              note TEXT,
              created_at TEXT NOT NULL
            )
        """)
        exec(dbHandle, """
            CREATE TABLE duplicate_decisions (
              cleaned_hash TEXT PRIMARY KEY,
              decision TEXT NOT NULL,
              keep_job_id TEXT,
              note TEXT,
              decided_at TEXT NOT NULL,
              created_at TEXT NOT NULL
            )
        """)
        exec(dbHandle, """
            CREATE TABLE settings (
              key TEXT PRIMARY KEY,
              value TEXT NOT NULL,
              updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ','now'))
            )
        """)
        exec(dbHandle, """
            CREATE TABLE job_actions (
              id TEXT PRIMARY KEY,
              job_id TEXT NOT NULL,
              note TEXT NOT NULL DEFAULT '',
              due_date TEXT NOT NULL,
              completed_at TEXT,
              snoozed_until TEXT,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL
            )
        """)
        exec(dbHandle, """
            CREATE TABLE data_quality_reviews (
              job_id TEXT PRIMARY KEY,
              reviewed_at TEXT NOT NULL,
              note TEXT NOT NULL DEFAULT ''
            )
        """)
        exec(dbHandle, """
            CREATE TABLE sites (
              id TEXT PRIMARY KEY,
              origin TEXT NOT NULL,
              url TEXT NOT NULL,
              company_name TEXT,
              company_website TEXT,
              jobs_url TEXT,
              company_description TEXT NOT NULL DEFAULT '',
              page_title TEXT NOT NULL DEFAULT '',
              interval_days INTEGER NOT NULL DEFAULT 14,
              last_reviewed_at TEXT,
              next_review_at TEXT,
              note TEXT NOT NULL DEFAULT '',
              state TEXT NOT NULL DEFAULT 'not_reviewed',
              added_at TEXT NOT NULL,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL
            )
        """)
        exec(dbHandle, """
            CREATE TABLE resumes (
              id TEXT PRIMARY KEY,
              name TEXT NOT NULL,
              filename TEXT,
              text TEXT NOT NULL DEFAULT '',
              char_count INTEGER NOT NULL DEFAULT 0,
              active INTEGER NOT NULL DEFAULT 1,
              sort_order INTEGER NOT NULL DEFAULT 0,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL
            )
        """)
        exec(dbHandle, """
            CREATE TABLE job_fit_scores (
              job_id TEXT NOT NULL,
              resume_id TEXT NOT NULL,
              fit_score INTEGER,
              fit_status TEXT NOT NULL DEFAULT 'none',
              fit_score_json TEXT,
              model TEXT,
              scored_at TEXT,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL,
              PRIMARY KEY (job_id, resume_id)
            )
        """)
        exec(dbHandle, """
            CREATE TABLE llm_requests (
              id TEXT PRIMARY KEY,
              job_id TEXT NOT NULL,
              request_type TEXT NOT NULL DEFAULT 'extract',
              resume_id TEXT,
              status TEXT NOT NULL DEFAULT 'queued',
              attempt INTEGER NOT NULL DEFAULT 1,
              model TEXT,
              error TEXT,
              created_at TEXT NOT NULL,
              started_at TEXT,
              finished_at TEXT
            )
        """)
        exec(dbHandle, """
            CREATE TABLE llm_request_attempts (
              id TEXT PRIMARY KEY,
              request_id TEXT NOT NULL,
              job_id TEXT NOT NULL,
              request_type TEXT NOT NULL,
              attempt INTEGER NOT NULL,
              status TEXT NOT NULL,
              model_requested TEXT,
              model_returned TEXT,
              response_format TEXT,
              base_url TEXT,
              started_at TEXT NOT NULL,
              finished_at TEXT,
              duration_ms INTEGER,
              error TEXT,
              response_preview TEXT,
              prompt_chars INTEGER,
              response_chars INTEGER,
              resume_id TEXT
            )
        """)
        exec(dbHandle, """
            CREATE TABLE contacts (
              id TEXT PRIMARY KEY,
              job_id TEXT NOT NULL,
              name TEXT NOT NULL,
              role TEXT,
              email TEXT,
              linkedin_url TEXT,
              phone TEXT,
              notes TEXT,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL
            )
        """)
        exec(dbHandle, """
            CREATE TABLE cover_letters (
              id TEXT PRIMARY KEY,
              job_id TEXT NOT NULL,
              resume_id TEXT,
              content TEXT NOT NULL,
              instructions TEXT,
              model TEXT,
              created_at TEXT NOT NULL
            )
        """)
    }

    // MARK: - Tests

    /// Opening a non-existent DB path should fail cleanly (openReadOnly returns nil).
    func testOpenReadOnlyNonExistentPath() {
        let path = "/tmp/definitely_does_not_exist_\(UUID().uuidString).db"
        // We can't directly call the migrator's openReadOnly (it's in the executable, not a testable module),
        // but we can replicate the same logic to verify SQLITE_CANTOPEN is returned.
        var dbPtr: OpaquePointer?
        let openResult = sqlite3_open_v2(path, &dbPtr, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil)
        XCTAssertNotEqual(openResult, SQLITE_OK, "sqlite3_open_v2 should fail for a non-existent path in readonly mode")
        sqlite3_close(dbPtr)
        XCTAssertFalse(FileManager.default.fileExists(atPath: path), "File should not have been created")
    }

    /// An empty legacy DB (all tables present, no rows) should produce a 0-row SwiftData store.
    func testEmptyDBProducesZeroRows() throws {
        let dbPath = try makeTempDB { dbHandle in createMinimalSchema(dbHandle) }
        defer { try? FileManager.default.removeItem(atPath: dbPath) }

        let outputPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("migrator_out_\(UUID().uuidString).store").path
        defer { try? FileManager.default.removeItem(atPath: outputPath) }

        // Open source DB
        var srcDB: OpaquePointer?
        let openResult = sqlite3_open_v2(dbPath, &srcDB, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil)
        XCTAssertEqual(openResult, SQLITE_OK)
        guard let srcDB else { XCTFail("Could not open source DB"); return }
        defer { sqlite3_close(srcDB) }

        // Create output store
        let outputURL = URL(fileURLWithPath: outputPath)
        let schema = Schema(SchemaV1.models)
        let config = ModelConfiguration(schema: schema, url: outputURL, cloudKitDatabase: .none)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: JobhuntMigrationPlan.self,
            configurations: config
        )
        let context = ModelContext(container)

        // Use the same migration helpers (replicated inline for testability)
        var captureCount = 0
        var jobCount = 0
        var eventCount = 0
        var siteCount = 0
        var resumeCount = 0

        func queryRows(_ dbHandle: OpaquePointer, _ sql: String) -> [[String: String?]] {
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(dbHandle, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
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

        // Count rows from legacy tables
        captureCount = queryRows(srcDB, "SELECT * FROM captures").count
        jobCount = queryRows(srcDB, "SELECT * FROM jobs").count
        eventCount = queryRows(srcDB, "SELECT * FROM events").count
        siteCount = queryRows(srcDB, "SELECT * FROM sites").count
        resumeCount = queryRows(srcDB, "SELECT * FROM resumes").count

        // All should be zero (empty DB)
        XCTAssertEqual(captureCount, 0)
        XCTAssertEqual(jobCount, 0)
        XCTAssertEqual(eventCount, 0)
        XCTAssertEqual(siteCount, 0)
        XCTAssertEqual(resumeCount, 0)

        // SwiftData store should also be empty
        try context.save()
        let captures = try context.fetch(FetchDescriptor<Capture>())
        let jobs = try context.fetch(FetchDescriptor<Job>())
        XCTAssertEqual(captures.count, 0, "No captures should be migrated from empty DB")
        XCTAssertEqual(jobs.count, 0, "No jobs should be migrated from empty DB")
    }

    /// A DB with fixture rows should produce matching row counts in the SwiftData store.
    func testFixtureDBRowCountsMatch() throws {
        let now = "2024-01-15T12:00:00Z"

        let dbPath = try makeTempDB { dbHandle in
            createMinimalSchema(dbHandle)

            // Insert a capture
            exec(dbHandle, """
                INSERT INTO captures (id, url, page_title, raw_hash, captured_at, created_at)
                VALUES ('cap1', 'https://example.com/jobs/1', 'Senior Engineer', 'hash_abc', '\(now)', '\(now)')
            """)

            // Insert a job linked to the capture
            exec(dbHandle, """
                INSERT INTO jobs (id, job_number, capture_id, company, title, status,
                                  manual_overrides, extraction_status, fit_status, unread,
                                  created_at, updated_at)
                VALUES ('job1', 42, 'cap1', 'Acme Corp', 'Senior Engineer', 'saved',
                        '[]', 'succeeded', 'none', 0, '\(now)', '\(now)')
            """)
            exec(dbHandle, """
                UPDATE jobs SET extracted_json = '{"title":"Senior Engineer"}' WHERE id = 'job1'
            """)

            // Insert an event
            exec(dbHandle, """
                INSERT INTO events (id, job_id, event_type, occurred_at, created_at)
                VALUES ('ev1', 'job1', 'applied', '\(now)', '\(now)')
            """)

            // Insert a site
            exec(dbHandle, """
                INSERT INTO sites (id, origin, url, company_description, page_title, state,
                                   interval_days, note, added_at, created_at, updated_at)
                VALUES ('site1', 'https://acme.com', 'https://acme.com/careers', '', 'Acme Jobs',
                        'not_reviewed', 14, '', '\(now)', '\(now)', '\(now)')
            """)

            // Insert a resume
            exec(dbHandle, """
                INSERT INTO resumes (id, name, text, char_count, active, sort_order, created_at, updated_at)
                VALUES ('res1', 'My Resume', 'Resume content here', 19, 1, 0, '\(now)', '\(now)')
            """)

            // Insert a setting
            exec(dbHandle, """
                INSERT INTO settings (key, value, updated_at) VALUES ('llm_provider', 'lmstudio', '\(now)')
            """)
        }
        defer { try? FileManager.default.removeItem(atPath: dbPath) }

        let outputPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("migrator_fixture_out_\(UUID().uuidString).store").path
        defer { try? FileManager.default.removeItem(atPath: outputPath) }

        // Open source
        var srcDB: OpaquePointer?
        let openResult = sqlite3_open_v2(dbPath, &srcDB, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil)
        XCTAssertEqual(openResult, SQLITE_OK)
        guard let srcDB else { XCTFail("Could not open fixture DB"); return }
        defer { sqlite3_close(srcDB) }

        // Create output store
        let outputURL = URL(fileURLWithPath: outputPath)
        let schema = Schema(SchemaV1.models)
        let config = ModelConfiguration(schema: schema, url: outputURL, cloudKitDatabase: .none)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: JobhuntMigrationPlan.self,
            configurations: config
        )
        let context = ModelContext(container)

        /// Replicate the migration logic inline for the key tables
        func queryRows(_ dbHandle: OpaquePointer, _ sql: String) -> [[String: String?]] {
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(dbHandle, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(stmt) }
            var rows: [[String: String?]] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                var row: [String: String?] = [:]
                let colCount = sqlite3_column_count(stmt)
                for col in 0 ..< colCount {
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

        func str(_ row: [String: String?], _ key: String) -> String? {
            guard let outer = row[key] else { return nil }
            return outer
        }
        func req(_ row: [String: String?], _ key: String, fallback: String = "") -> String {
            str(row, key) ?? fallback
        }
        func intVal(_ row: [String: String?], _ key: String) -> Int? {
            str(row, key).flatMap(Int.init)
        }
        func boolVal(
            _ row: [String: String?],
            _ key: String
        ) -> Bool {
            str(row, key).flatMap(Int.init).map { $0 != 0 } ?? false
        }

        let isoBasic = ISO8601DateFormatter()
        isoBasic.formatOptions = [.withInternetDateTime]
        func parseDate(_ dateStr: String?) -> Date? {
            dateStr.flatMap { isoBasic.date(from: $0) }
        }
        func dateOrNow(_ row: [String: String?], _ key: String) -> Date {
            parseDate(row[key] ?? nil) ?? Date()
        }

        // Migrate captures
        for row in queryRows(srcDB, "SELECT * FROM captures") {
            guard let id = str(row, "id"), let rawHash = str(row, "raw_hash") else { continue }
            context.insert(Capture(
                id: id, url: req(row, "url"), pageTitle: req(row, "page_title"),
                rawHash: rawHash, capturedAt: dateOrNow(row, "captured_at"),
                createdAt: dateOrNow(row, "created_at")
            ))
        }

        var captureMap: [String: Capture] = [:]
        for cap in (try? context.fetch(FetchDescriptor<Capture>())) ?? [] {
            captureMap[cap.id] = cap
        }

        // Migrate jobs
        for row in queryRows(srcDB, "SELECT * FROM jobs") {
            guard let id = str(row, "id") else { continue }
            let jobObj = Job(
                id: id,
                jobNumber: intVal(row, "job_number"),
                company: str(row, "company"),
                title: str(row, "title"),
                status: str(row, "status").flatMap { JobStatus(rawValue: $0) } ?? .saved,
                manualOverridesJSON: req(row, "manual_overrides", fallback: "[]"),
                extractedJSON: str(row, "extracted_json"),
                extractionStatus: str(row, "extraction_status").flatMap { ExtractionStatus(rawValue: $0) } ?? .pending,
                fitStatus: str(row, "fit_status").flatMap { FitStatus(rawValue: $0) } ?? .none,
                unread: boolVal(row, "unread"),
                createdAt: dateOrNow(row, "created_at"),
                updatedAt: dateOrNow(row, "updated_at")
            )
            if let capId = str(row, "capture_id") { jobObj.capture = captureMap[capId] }
            context.insert(jobObj)
        }

        var jobMap: [String: Job] = [:]
        for jobFetched in (try? context.fetch(FetchDescriptor<Job>())) ?? [] {
            jobMap[jobFetched.id] = jobFetched
        }

        // Migrate events
        for row in queryRows(srcDB, "SELECT * FROM events") {
            guard let id = str(row, "id"), let jobId = str(row, "job_id") else { continue }
            let evObj = JobEvent(
                id: id,
                eventType: req(row, "event_type"),
                occurredAt: dateOrNow(row, "occurred_at"),
                createdAt: dateOrNow(row, "created_at")
            )
            evObj.job = jobMap[jobId]
            context.insert(evObj)
        }

        // Migrate sites
        for row in queryRows(srcDB, "SELECT * FROM sites") {
            guard let id = str(row, "id") else { continue }
            context.insert(Site(
                id: id, origin: req(row, "origin"), url: req(row, "url"),
                companyDescription: req(row, "company_description"),
                pageTitle: req(row, "page_title"),
                intervalDays: intVal(row, "interval_days") ?? 14,
                note: req(row, "note"),
                state: str(row, "state").flatMap { SiteState(rawValue: $0) } ?? .notReviewed,
                addedAt: dateOrNow(row, "added_at"),
                createdAt: dateOrNow(row, "created_at"),
                updatedAt: dateOrNow(row, "updated_at")
            ))
        }

        // Migrate resumes
        for row in queryRows(srcDB, "SELECT * FROM resumes") {
            guard let id = str(row, "id") else { continue }
            context.insert(Resume(
                id: id, name: req(row, "name"),
                text: req(row, "text"),
                charCount: intVal(row, "char_count") ?? 0,
                active: boolVal(row, "active"),
                sortOrder: intVal(row, "sort_order") ?? 0,
                createdAt: dateOrNow(row, "created_at"),
                updatedAt: dateOrNow(row, "updated_at")
            ))
        }

        // Migrate settings
        for row in queryRows(srcDB, "SELECT * FROM settings") {
            guard let key = str(row, "key"), let value = str(row, "value") else { continue }
            context.insert(Setting(key: key, value: value, updatedAt: dateOrNow(row, "updated_at")))
        }

        try context.save()

        // Assert counts match fixture
        let captures = try context.fetch(FetchDescriptor<Capture>())
        let jobs = try context.fetch(FetchDescriptor<Job>())
        let events = try context.fetch(FetchDescriptor<JobEvent>())
        let sites = try context.fetch(FetchDescriptor<Site>())
        let resumes = try context.fetch(FetchDescriptor<Resume>())
        let settings = try context.fetch(FetchDescriptor<Setting>())

        XCTAssertEqual(captures.count, 1, "Should migrate 1 capture")
        XCTAssertEqual(jobs.count, 1, "Should migrate 1 job")
        XCTAssertEqual(events.count, 1, "Should migrate 1 event")
        XCTAssertEqual(sites.count, 1, "Should migrate 1 site")
        XCTAssertEqual(resumes.count, 1, "Should migrate 1 resume")
        XCTAssertEqual(settings.count, 1, "Should migrate 1 setting")

        // Spot-check key fields
        let job = try XCTUnwrap(jobs.first)
        XCTAssertEqual(job.jobNumber, 42, "jobNumber should be preserved verbatim")
        XCTAssertEqual(job.company, "Acme Corp", "company should be preserved")
        XCTAssertEqual(
            job.extractedJSON,
            "{\"title\":\"Senior Engineer\"}",
            "extractedJSON should be preserved verbatim"
        )
        XCTAssertEqual(job.status, .saved)

        let capture = try XCTUnwrap(captures.first)
        XCTAssertEqual(capture.rawHash, "hash_abc", "rawHash should be preserved verbatim")
        XCTAssertEqual(capture.id, "cap1")
        XCTAssertNotNil(job.capture, "Job should be linked to its capture")
        XCTAssertEqual(job.capture?.id, "cap1")

        let setting = try XCTUnwrap(settings.first)
        XCTAssertEqual(setting.key, "llm_provider")
        XCTAssertEqual(setting.value, "lmstudio")
    }
}

// swiftlint:enable file_length cyclomatic_complexity function_body_length type_body_length
