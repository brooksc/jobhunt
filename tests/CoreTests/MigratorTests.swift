import SQLite3
import SwiftData

// swiftlint:disable file_length
import XCTest
@testable import JobhuntCore

/// Tests for the production migrate(src:context:) implementation in tools/migrator/Migration.swift.
/// Migration.swift and SQLiteHelpers.swift are compiled directly into this target (see Project.swift).
final class MigratorTests: XCTestCase {
    // MARK: - Helpers

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

    func exec(_ db: OpaquePointer, _ sql: String) {
        var err: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(db, sql, nil, nil, &err)
        if rc != SQLITE_OK {
            let msg = err.map { String(cString: $0) } ?? "unknown"
            XCTFail("SQL error: \(msg) for: \(sql)")
        }
        sqlite3_free(err)
    }

    func makeOutputContext() throws -> (ModelContext, String) {
        let outputPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("migrator_out_\(UUID().uuidString).store").path
        let outputURL = URL(fileURLWithPath: outputPath)
        let schema = Schema(SchemaV1.models)
        let config = ModelConfiguration(schema: schema, url: outputURL, cloudKitDatabase: .none)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: JobhuntMigrationPlan.self,
            configurations: config
        )
        return (ModelContext(container), outputPath)
    }

    /// Minimal legacy schema — all tables the production migrator expects.
    func createMinimalSchema(_ db: OpaquePointer) {
        exec(db, """
            CREATE TABLE captures (id TEXT PRIMARY KEY, url TEXT NOT NULL, canonical_url TEXT,
              page_title TEXT NOT NULL, selected_text TEXT, visible_text TEXT,
              cleaned_description TEXT, structured_data_json TEXT, user_note TEXT,
              raw_hash TEXT NOT NULL, cleaned_hash TEXT, captured_at TEXT NOT NULL, created_at TEXT NOT NULL)
        """)
        exec(db, """
            CREATE TABLE jobs (id TEXT PRIMARY KEY, job_number INTEGER, capture_id TEXT NOT NULL,
              company TEXT, title TEXT, location TEXT, remote_type TEXT,
              salary_min INTEGER, salary_max INTEGER, salary_currency TEXT, salary_note TEXT,
              employment_type TEXT, seniority TEXT, status TEXT NOT NULL DEFAULT 'saved',
              manual_overrides TEXT NOT NULL DEFAULT '[]', extracted_json TEXT,
              extraction_status TEXT NOT NULL DEFAULT 'pending', extraction_error TEXT,
              fit_score INTEGER, fit_status TEXT NOT NULL DEFAULT 'none', fit_score_json TEXT,
              duplicate_of_job_id TEXT, duplicate_confidence REAL, extracted_at TEXT,
              rating INTEGER, extraction_model TEXT, application_url TEXT,
              extraction_confidence REAL, last_opened_at TEXT, unread INTEGER NOT NULL DEFAULT 0,
              created_at TEXT NOT NULL, updated_at TEXT NOT NULL)
        """)
        exec(db, """
            CREATE TABLE events (id TEXT PRIMARY KEY, job_id TEXT NOT NULL,
              event_type TEXT NOT NULL, note TEXT, occurred_at TEXT NOT NULL, created_at TEXT NOT NULL)
        """)
        exec(db, """
            CREATE TABLE site_reviews (id TEXT PRIMARY KEY, site_url TEXT NOT NULL,
              site_origin TEXT NOT NULL, page_title TEXT, reviewed_at TEXT NOT NULL,
              next_review_at TEXT, note TEXT, created_at TEXT NOT NULL)
        """)
        exec(db, """
            CREATE TABLE duplicate_decisions (cleaned_hash TEXT PRIMARY KEY,
              decision TEXT NOT NULL, keep_job_id TEXT, note TEXT,
              decided_at TEXT NOT NULL, created_at TEXT NOT NULL)
        """)
        exec(db, """
            CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT NOT NULL,
              updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ','now')))
        """)
        exec(db, """
            CREATE TABLE job_actions (id TEXT PRIMARY KEY, job_id TEXT NOT NULL,
              note TEXT NOT NULL DEFAULT '', due_date TEXT NOT NULL, completed_at TEXT,
              snoozed_until TEXT, created_at TEXT NOT NULL, updated_at TEXT NOT NULL)
        """)
        exec(db, """
            CREATE TABLE data_quality_reviews (job_id TEXT PRIMARY KEY,
              reviewed_at TEXT NOT NULL, note TEXT NOT NULL DEFAULT '')
        """)
        exec(db, """
            CREATE TABLE sites (id TEXT PRIMARY KEY, origin TEXT NOT NULL, url TEXT NOT NULL,
              company_name TEXT, company_website TEXT, jobs_url TEXT,
              company_description TEXT NOT NULL DEFAULT '', page_title TEXT NOT NULL DEFAULT '',
              interval_days INTEGER NOT NULL DEFAULT 14, last_reviewed_at TEXT,
              next_review_at TEXT, note TEXT NOT NULL DEFAULT '',
              state TEXT NOT NULL DEFAULT 'not_reviewed', added_at TEXT NOT NULL,
              created_at TEXT NOT NULL, updated_at TEXT NOT NULL)
        """)
        exec(db, """
            CREATE TABLE resumes (id TEXT PRIMARY KEY, name TEXT NOT NULL, filename TEXT,
              text TEXT NOT NULL DEFAULT '', char_count INTEGER NOT NULL DEFAULT 0,
              active INTEGER NOT NULL DEFAULT 1, sort_order INTEGER NOT NULL DEFAULT 0,
              created_at TEXT NOT NULL, updated_at TEXT NOT NULL)
        """)
        exec(db, """
            CREATE TABLE job_fit_scores (job_id TEXT NOT NULL, resume_id TEXT NOT NULL,
              fit_score INTEGER, fit_status TEXT NOT NULL DEFAULT 'none', fit_score_json TEXT,
              model TEXT, scored_at TEXT, created_at TEXT NOT NULL, updated_at TEXT NOT NULL,
              PRIMARY KEY (job_id, resume_id))
        """)
        exec(db, """
            CREATE TABLE llm_requests (id TEXT PRIMARY KEY, job_id TEXT NOT NULL,
              request_type TEXT NOT NULL DEFAULT 'extract', resume_id TEXT,
              status TEXT NOT NULL DEFAULT 'queued', attempt INTEGER NOT NULL DEFAULT 1,
              model TEXT, error TEXT, created_at TEXT NOT NULL, started_at TEXT, finished_at TEXT)
        """)
        exec(db, """
            CREATE TABLE llm_request_attempts (id TEXT PRIMARY KEY, request_id TEXT NOT NULL,
              job_id TEXT NOT NULL, request_type TEXT NOT NULL, attempt INTEGER NOT NULL,
              status TEXT NOT NULL, model_requested TEXT, model_returned TEXT,
              response_format TEXT, base_url TEXT, started_at TEXT NOT NULL,
              finished_at TEXT, duration_ms INTEGER, error TEXT, response_preview TEXT,
              prompt_chars INTEGER, response_chars INTEGER, resume_id TEXT)
        """)
        exec(db, """
            CREATE TABLE contacts (id TEXT PRIMARY KEY, job_id TEXT NOT NULL,
              name TEXT NOT NULL, role TEXT, email TEXT, linkedin_url TEXT, phone TEXT,
              notes TEXT, created_at TEXT NOT NULL, updated_at TEXT NOT NULL)
        """)
        exec(db, """
            CREATE TABLE cover_letters (id TEXT PRIMARY KEY, job_id TEXT NOT NULL,
              resume_id TEXT, content TEXT NOT NULL, instructions TEXT, model TEXT,
              created_at TEXT NOT NULL)
        """)
    }

    // MARK: - Arg parsing (TASK-523)

    func testParseArgs_singleOperationFlag_parses() {
        guard case .reclean = parseArgs(["JobhuntMigrator", "--reclean", "--store", "/tmp/s"]) else {
            return XCTFail("a single operation flag should parse to that mode")
        }
    }

    func testParseArgs_twoOperationFlags_rejected() {
        let mode = parseArgs(["JobhuntMigrator", "--reclean", "--repair-duplicate-job-numbers", "--store", "/tmp/s"])
        XCTAssertNil(mode, "combining two mutually-exclusive operation flags must be rejected, not silently run one")
    }

    func testParseArgs_operationFlagPlusMigrate_rejected() {
        let mode = parseArgs(["JobhuntMigrator", "--reclean", "--output", "/tmp/out.store"])
        XCTAssertNil(mode, "an operation flag combined with --output (migrate) is ambiguous")
    }

    func testParseArgs_migrateOnly_parses() {
        guard case .migrate = parseArgs(["JobhuntMigrator", "--output", "/tmp/out.store"]) else {
            return XCTFail("--output alone should parse to migrate")
        }
    }

    // MARK: - Tests

    func testOpenReadOnlyNonExistentPath() {
        let path = "/tmp/does_not_exist_\(UUID().uuidString).db"
        var dbPtr: OpaquePointer?
        let rc = sqlite3_open_v2(path, &dbPtr, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil)
        XCTAssertNotEqual(rc, SQLITE_OK)
        sqlite3_close(dbPtr)
        XCTAssertFalse(FileManager.default.fileExists(atPath: path))
    }

    /// Empty DB → production migrate() → all counts 0.
    func testEmptyDBProducesZeroRows() throws {
        let dbPath = try makeTempDB { createMinimalSchema($0) }
        defer { try? FileManager.default.removeItem(atPath: dbPath) }

        var srcDB: OpaquePointer?
        XCTAssertEqual(sqlite3_open_v2(dbPath, &srcDB, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil), SQLITE_OK)
        guard let srcDB else { return XCTFail("Could not open source DB") }
        defer { sqlite3_close(srcDB) }

        let (context, outPath) = try makeOutputContext()
        defer { try? FileManager.default.removeItem(atPath: outPath) }

        let summary = migrate(src: srcDB, context: context)

        XCTAssertEqual(summary.captures, 0)
        XCTAssertEqual(summary.jobs, 0)
        XCTAssertEqual(summary.events, 0)
        XCTAssertEqual(summary.sites, 0)
        XCTAssertEqual(summary.resumes, 0)
        XCTAssertEqual(summary.settings, 0)

        try context.save()
        XCTAssertEqual(try context.fetch(FetchDescriptor<Capture>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Job>()).count, 0)
    }

    /// Fixture DB → production migrate() → row counts and fields match.
    func testFixtureDBRowCountsMatch() throws {
        let now = "2024-01-15T12:00:00Z"

        let dbPath = try makeTempDB { db in
            createMinimalSchema(db)
            exec(db, """
                INSERT INTO captures (id, url, page_title, raw_hash, captured_at, created_at)
                VALUES ('cap1', 'https://example.com/jobs/1', 'Senior Engineer', 'hash_abc', '\(now)', '\(now)')
            """)
            exec(db, """
                INSERT INTO jobs (id, job_number, capture_id, company, title, status,
                                  manual_overrides, extraction_status, fit_status, unread,
                                  created_at, updated_at)
                VALUES ('job1', 42, 'cap1', 'Acme Corp', 'Senior Engineer', 'saved',
                        '[]', 'succeeded', 'none', 0, '\(now)', '\(now)')
            """)
            exec(db, "UPDATE jobs SET extracted_json = '{\"title\":\"Senior Engineer\"}' WHERE id = 'job1'")
            exec(db, """
                INSERT INTO events (id, job_id, event_type, occurred_at, created_at)
                VALUES ('ev1', 'job1', 'applied', '\(now)', '\(now)')
            """)
            exec(db, """
                INSERT INTO sites (id, origin, url, company_description, page_title, state,
                                   interval_days, note, added_at, created_at, updated_at)
                VALUES ('site1', 'https://acme.com', 'https://acme.com/careers', '',
                        'Acme Jobs', 'not_reviewed', 14, '', '\(now)', '\(now)', '\(now)')
            """)
            exec(db, """
                INSERT INTO resumes (id, name, text, char_count, active, sort_order, created_at, updated_at)
                VALUES ('res1', 'My Resume', 'Resume content', 14, 1, 0, '\(now)', '\(now)')
            """)
            exec(db, "INSERT INTO settings (key, value, updated_at) VALUES ('llm_provider', 'lmstudio', '\(now)')")
        }
        defer { try? FileManager.default.removeItem(atPath: dbPath) }

        var srcDB: OpaquePointer?
        XCTAssertEqual(sqlite3_open_v2(dbPath, &srcDB, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil), SQLITE_OK)
        guard let srcDB else { return XCTFail("Could not open fixture DB") }
        defer { sqlite3_close(srcDB) }

        let (context, outPath) = try makeOutputContext()
        defer { try? FileManager.default.removeItem(atPath: outPath) }

        let summary = migrate(src: srcDB, context: context)
        try context.save()

        XCTAssertEqual(summary.captures, 1)
        XCTAssertEqual(summary.jobs, 1)
        XCTAssertEqual(summary.events, 1)
        XCTAssertEqual(summary.sites, 1)
        XCTAssertEqual(summary.resumes, 1)
        XCTAssertEqual(summary.settings, 1)

        let job = try XCTUnwrap(context.fetch(FetchDescriptor<Job>()).first)
        XCTAssertEqual(job.jobNumber, 42)
        XCTAssertEqual(job.company, "Acme Corp")
        XCTAssertEqual(job.extractedJSON, "{\"title\":\"Senior Engineer\"}")
        XCTAssertEqual(job.status, .pursuing)
        XCTAssertNotNil(job.capture)
        XCTAssertEqual(job.capture?.id, "cap1")

        let capture = try XCTUnwrap(context.fetch(FetchDescriptor<Capture>()).first)
        XCTAssertEqual(capture.rawHash, "hash_abc")

        let setting = try XCTUnwrap(context.fetch(FetchDescriptor<Setting>()).first)
        XCTAssertEqual(setting.key, "llm_provider")
        XCTAssertEqual(setting.value, "lmstudio")
    }

    /// Orphan event (job_id points to no job) must be skipped and reported in summary.
    func testOrphanEventIsSkipped() throws {
        let now = "2024-01-15T12:00:00Z"

        let dbPath = try makeTempDB { db in
            createMinimalSchema(db)
            exec(db, """
                INSERT INTO events (id, job_id, event_type, occurred_at, created_at)
                VALUES ('ev_orphan', 'nonexistent_job', 'applied', '\(now)', '\(now)')
            """)
        }
        defer { try? FileManager.default.removeItem(atPath: dbPath) }

        var srcDB: OpaquePointer?
        XCTAssertEqual(sqlite3_open_v2(dbPath, &srcDB, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil), SQLITE_OK)
        guard let srcDB else { return XCTFail("Could not open source DB") }
        defer { sqlite3_close(srcDB) }

        let (context, outPath) = try makeOutputContext()
        defer { try? FileManager.default.removeItem(atPath: outPath) }

        let summary = migrate(src: srcDB, context: context)
        try context.save()

        // Orphan event must not appear in the store.
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<JobEvent>()).count,
            0,
            "Orphan event should be skipped, not imported"
        )
        // Summary must report it.
        XCTAssertGreaterThan(
            summary.skippedOrphans,
            0,
            "summary.skippedOrphans should count the skipped event"
        )
    }

    /// Orphan job_action (job_id points to no job) must be skipped and reported in summary.
    func testOrphanJobActionIsSkipped() throws {
        let now = "2024-01-15T12:00:00Z"

        let dbPath = try makeTempDB { db in
            createMinimalSchema(db)
            exec(db, """
                INSERT INTO job_actions (id, job_id, note, due_date, created_at, updated_at)
                VALUES ('action_orphan', 'nonexistent_job', 'Follow up', '\(now)', '\(now)', '\(now)')
            """)
        }
        defer { try? FileManager.default.removeItem(atPath: dbPath) }

        var srcDB: OpaquePointer?
        XCTAssertEqual(sqlite3_open_v2(dbPath, &srcDB, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil), SQLITE_OK)
        guard let srcDB else { return XCTFail("Could not open source DB") }
        defer { sqlite3_close(srcDB) }

        let (context, outPath) = try makeOutputContext()
        defer { try? FileManager.default.removeItem(atPath: outPath) }

        let summary = migrate(src: srcDB, context: context)
        try context.save()

        XCTAssertEqual(
            try context.fetch(FetchDescriptor<JobAction>()).count,
            0,
            "Orphan job_action should be skipped, not imported"
        )
        XCTAssertEqual(
            summary.skippedOrphanActions,
            1,
            "summary.skippedOrphanActions should be 1"
        )
        XCTAssertGreaterThan(
            summary.skippedOrphans,
            0,
            "summary.skippedOrphans should count the skipped job_action"
        )
    }

    /// Orphan job_fit_score (job_id points to no job) must be skipped and reported in summary.
    func testOrphanJobFitScoreIsSkipped() throws {
        let now = "2024-01-15T12:00:00Z"

        let dbPath = try makeTempDB { db in
            createMinimalSchema(db)
            exec(db, """
                INSERT INTO resumes (id, name, text, char_count, active, sort_order, created_at, updated_at)
                VALUES ('res1', 'My Resume', 'Content', 7, 1, 0, '\(now)', '\(now)')
            """)
            exec(db, """
                INSERT INTO job_fit_scores (job_id, resume_id, fit_score, fit_status, created_at, updated_at)
                VALUES ('nonexistent_job', 'res1', 80, 'good', '\(now)', '\(now)')
            """)
        }
        defer { try? FileManager.default.removeItem(atPath: dbPath) }

        var srcDB: OpaquePointer?
        XCTAssertEqual(sqlite3_open_v2(dbPath, &srcDB, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil), SQLITE_OK)
        guard let srcDB else { return XCTFail("Could not open source DB") }
        defer { sqlite3_close(srcDB) }

        let (context, outPath) = try makeOutputContext()
        defer { try? FileManager.default.removeItem(atPath: outPath) }

        let summary = migrate(src: srcDB, context: context)
        try context.save()

        XCTAssertEqual(
            try context.fetch(FetchDescriptor<JobFitScore>()).count,
            0,
            "Orphan job_fit_score should be skipped, not imported"
        )
        XCTAssertEqual(
            summary.skippedOrphanFitScores,
            1,
            "summary.skippedOrphanFitScores should be 1"
        )
        XCTAssertGreaterThan(
            summary.skippedOrphans,
            0,
            "summary.skippedOrphans should count the skipped job_fit_score"
        )
    }

    /// migrate() is a run-once operation. Calling it on a non-empty store returns early
    /// with skippedNonEmpty=true to prevent duplicate records (no DB-level unique constraints).
    func testMigratorRefusesToRunOnNonEmptyStore() throws {
        let now = "2024-01-15T12:00:00Z"
        let dbPath = try makeTempDB { db in
            createMinimalSchema(db)
            exec(db, """
                INSERT INTO captures (id, url, page_title, raw_hash, captured_at, created_at)
                VALUES ('cap1', 'https://example.com/jobs/1', 'Engineer', 'hash_abc', '\(now)', '\(now)')
            """)
            exec(db, """
                INSERT INTO jobs (id, job_number, capture_id, status, manual_overrides,
                                  extraction_status, fit_status, unread, created_at, updated_at)
                VALUES ('job1', 1, 'cap1', 'saved', '[]', 'pending', 'none', 0, '\(now)', '\(now)')
            """)
        }
        defer { try? FileManager.default.removeItem(atPath: dbPath) }

        var srcDB: OpaquePointer?
        XCTAssertEqual(sqlite3_open_v2(dbPath, &srcDB, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil), SQLITE_OK)
        guard let srcDB else { return XCTFail("Could not open source DB") }
        defer { sqlite3_close(srcDB) }

        let (context, outPath) = try makeOutputContext()
        defer { try? FileManager.default.removeItem(atPath: outPath) }

        // First run populates the store.
        let s1 = migrate(src: srcDB, context: context)
        try context.save()
        XCTAssertFalse(s1.skippedNonEmpty)
        XCTAssertEqual(s1.captures, 1)

        // Second run on the same (now non-empty) context must bail out.
        let s2 = migrate(src: srcDB, context: context)
        XCTAssertTrue(s2.skippedNonEmpty, "Second run must skip to prevent duplicates")
        XCTAssertEqual(s2.captures, 0, "No records should be imported on the second run")

        // Store must still contain exactly the rows from the first run.
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<Capture>()).count,
            1,
            "Store should not grow after a skipped second run"
        )
        XCTAssertEqual(try context.fetch(FetchDescriptor<Job>()).count, 1)
    }

    /// migrate() must set capturedAtDenormalized from the capture's capturedAt,
    /// not from the job's createdAt (which may differ).
    func testMigration_setsCapturedAtDenormalized() throws {
        // Use distinct dates so we can verify the right field is used.
        let capturedAt = "2024-03-15T10:00:00Z"
        let createdAt = "2024-01-01T00:00:00Z"

        let dbPath = try makeTempDB { db in
            createMinimalSchema(db)
            exec(db, """
                INSERT INTO captures (id, url, page_title, raw_hash, captured_at, created_at)
                VALUES ('cap1', 'https://example.com/jobs/1', 'Engineer', 'hash_xyz',
                        '\(capturedAt)', '\(createdAt)')
            """)
            exec(db, """
                INSERT INTO jobs (id, job_number, capture_id, status, manual_overrides,
                                  extraction_status, fit_status, unread, created_at, updated_at)
                VALUES ('job1', 1, 'cap1', 'saved', '[]', 'pending', 'none', 0,
                        '\(createdAt)', '\(createdAt)')
            """)
        }
        defer { try? FileManager.default.removeItem(atPath: dbPath) }

        var srcDB: OpaquePointer?
        XCTAssertEqual(sqlite3_open_v2(dbPath, &srcDB, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil), SQLITE_OK)
        guard let srcDB else { return XCTFail("Could not open source DB") }
        defer { sqlite3_close(srcDB) }

        let (context, outPath) = try makeOutputContext()
        defer { try? FileManager.default.removeItem(atPath: outPath) }

        let summary = migrate(src: srcDB, context: context)
        try context.save()

        XCTAssertEqual(summary.jobs, 1)
        let job = try XCTUnwrap(context.fetch(FetchDescriptor<Job>()).first)

        // capturedAtDenormalized must be set to the capture's capturedAt date.
        let denormalized = try XCTUnwrap(
            job.capturedAtDenormalized,
            "capturedAtDenormalized must not be nil after migration"
        )

        // Parse the expected dates using the same ISO-8601 UTC formatter the migrator uses.
        let fmt = ISO8601DateFormatter()
        let expectedCapturedAt = try XCTUnwrap(fmt.date(from: capturedAt))
        let expectedCreatedAt = try XCTUnwrap(fmt.date(from: createdAt))

        XCTAssertEqual(
            denormalized,
            expectedCapturedAt,
            "capturedAtDenormalized should equal capture.capturedAt"
        )
        XCTAssertNotEqual(
            denormalized,
            expectedCreatedAt,
            "capturedAtDenormalized must not equal job.createdAt (different dates)"
        )
    }

    /// patch() must also set capturedAtDenormalized from the capture's capturedAt.
    func testPatch_setsCapturedAtDenormalized() throws {
        // Use distinct dates so we can verify the right field is used.
        let capturedAt = "2024-03-15T10:00:00Z"
        let createdAt = "2024-01-01T00:00:00Z"

        let dbPath = try makeTempDB { db in
            createMinimalSchema(db)
            exec(db, """
                INSERT INTO captures (id, url, page_title, raw_hash, captured_at, created_at)
                VALUES ('cap1', 'https://example.com/jobs/1', 'Engineer', 'hash_xyz',
                        '\(capturedAt)', '\(createdAt)')
            """)
            exec(db, """
                INSERT INTO jobs (id, job_number, capture_id, status, manual_overrides,
                                  extraction_status, fit_status, unread, created_at, updated_at)
                VALUES ('job1', 1, 'cap1', 'saved', '[]', 'pending', 'none', 0,
                        '\(createdAt)', '\(createdAt)')
            """)
        }
        defer { try? FileManager.default.removeItem(atPath: dbPath) }

        var srcDB: OpaquePointer?
        XCTAssertEqual(sqlite3_open_v2(dbPath, &srcDB, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil), SQLITE_OK)
        guard let srcDB else { return XCTFail("Could not open source DB") }
        defer { sqlite3_close(srcDB) }

        let (context, outPath) = try makeOutputContext()
        defer { try? FileManager.default.removeItem(atPath: outPath) }

        // Pre-populate the capture (patch() expects captures to already be in SwiftData).
        let fmt = ISO8601DateFormatter()
        let capturedAtDate = try XCTUnwrap(fmt.date(from: capturedAt))
        let createdAtDate = try XCTUnwrap(fmt.date(from: createdAt))
        let cap = Capture(
            id: "cap1",
            url: "https://example.com/jobs/1",
            canonicalURL: nil,
            pageTitle: "Engineer",
            selectedText: nil,
            visibleText: nil,
            cleanedDescription: nil,
            structuredDataJSON: nil,
            userNote: nil,
            rawHash: "hash_xyz",
            cleanedHash: nil,
            capturedAt: capturedAtDate,
            createdAt: createdAtDate
        )
        context.insert(cap)
        try context.save()

        let summary = patch(src: srcDB, context: context)
        XCTAssertEqual(summary.jobsInserted, 1)

        let job = try XCTUnwrap(context.fetch(FetchDescriptor<Job>()).first)

        let denormalized = try XCTUnwrap(
            job.capturedAtDenormalized,
            "capturedAtDenormalized must not be nil after patch"
        )
        XCTAssertEqual(
            denormalized,
            capturedAtDate,
            "capturedAtDenormalized should equal capture.capturedAt"
        )
        XCTAssertNotEqual(
            denormalized,
            createdAtDate,
            "capturedAtDenormalized must not equal job.createdAt (different dates)"
        )
    }
}

// swiftlint:enable file_length
