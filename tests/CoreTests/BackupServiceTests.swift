import SQLite3
import SwiftData
import XCTest
@testable import JobhuntCore

final class BackupServiceTests: XCTestCase {

    // MARK: - Helpers

    private func makeTempStoreURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("backup_test_\(UUID().uuidString).store")
    }

    private func makeFileBacked() throws -> (ModelContainer, URL) {
        let url = makeTempStoreURL()
        let schema = Schema(SchemaV1.models)
        let config = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, migrationPlan: JobhuntMigrationPlan.self, configurations: config)
        return (container, url)
    }

    // MARK: - Tests

    func testBackup_copiesAllModels() throws {
        let (container, storeURL) = try makeFileBacked()
        defer { try? FileManager.default.removeItem(at: storeURL) }

        let ctx = ModelContext(container)
        let job = Job(jobNumber: 7, title: "Backup Test Job")
        job.company = "BackupCo"
        let resume = Resume(name: "My Resume", text: "Swift developer", charCount: 15, active: true, sortOrder: 0)
        let site = Site(origin: "https://backupco.com", url: "https://backupco.com/jobs")
        let setting = Setting(key: "llm_provider", value: "lmstudio")
        ctx.insert(job); ctx.insert(resume); ctx.insert(site); ctx.insert(setting)
        try ctx.save()

        let destURL = makeTempStoreURL()
        defer { try? FileManager.default.removeItem(at: destURL) }

        try BackupService.backup(storeURL: storeURL, to: destURL)

        XCTAssertTrue(FileManager.default.fileExists(atPath: destURL.path), "Backup file must exist")

        // Restore: open a new container from the backup and verify all records are present
        let schema = Schema(SchemaV1.models)
        let restoreConfig = ModelConfiguration(schema: schema, url: destURL, cloudKitDatabase: .none)
        let restored = try ModelContainer(for: schema, migrationPlan: JobhuntMigrationPlan.self, configurations: restoreConfig)
        let rCtx = ModelContext(restored)

        let jobs = try rCtx.fetch(FetchDescriptor<Job>())
        XCTAssertEqual(jobs.count, 1, "Backup must contain 1 job")
        XCTAssertEqual(jobs.first?.jobNumber, 7)
        XCTAssertEqual(jobs.first?.company, "BackupCo")

        let resumes = try rCtx.fetch(FetchDescriptor<Resume>())
        XCTAssertEqual(resumes.count, 1, "Backup must contain 1 resume")
        XCTAssertEqual(resumes.first?.name, "My Resume")

        let sites = try rCtx.fetch(FetchDescriptor<Site>())
        XCTAssertEqual(sites.count, 1)

        let settings = try rCtx.fetch(FetchDescriptor<Setting>())
        XCTAssertEqual(settings.count, 1)
        XCTAssertEqual(settings.first?.value, "lmstudio")
    }

    func testBackup_throwsWhenStoreNotFound() {
        let missingURL = URL(fileURLWithPath: "/tmp/does_not_exist_\(UUID().uuidString).store")
        let destURL = makeTempStoreURL()
        XCTAssertThrowsError(try BackupService.backup(storeURL: missingURL, to: destURL)) { error in
            guard case BackupService.BackupError.storeNotFound = error else {
                XCTFail("Expected storeNotFound, got \(error)")
                return
            }
        }
    }

    func testBackup_createsDestinationDirectory() throws {
        let (container, storeURL) = try makeFileBacked()
        defer { try? FileManager.default.removeItem(at: storeURL) }

        let ctx = ModelContext(container)
        ctx.insert(Setting(key: "k", value: "v"))
        try ctx.save()

        // Destination is in a subdirectory that doesn't yet exist
        let destURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("backup_test_subdir_\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("backup.store")
        defer { try? FileManager.default.removeItem(at: destURL.deletingLastPathComponent()) }

        XCTAssertNoThrow(try BackupService.backup(storeURL: storeURL, to: destURL))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destURL.path))
    }

    func testBackup_isConsistentWithLiveStore() throws {
        // Verifies that a backup taken while the store has captures+jobs+events
        // round-trips without data loss for all relation-linked models.
        let (container, storeURL) = try makeFileBacked()
        defer { try? FileManager.default.removeItem(at: storeURL) }

        let ctx = ModelContext(container)
        let cap = Capture(url: "https://example.com/job/1", pageTitle: "Engineer", rawHash: "h1")
        let job = Job(jobNumber: 1, title: "Engineer")
        job.capture = cap
        let ev = JobEvent(eventType: "applied")
        ev.job = job
        ctx.insert(cap); ctx.insert(job); ctx.insert(ev)
        try ctx.save()

        let destURL = makeTempStoreURL()
        defer { try? FileManager.default.removeItem(at: destURL) }
        try BackupService.backup(storeURL: storeURL, to: destURL)

        let schema = Schema(SchemaV1.models)
        let restoreConfig = ModelConfiguration(schema: schema, url: destURL, cloudKitDatabase: .none)
        let restored = try ModelContainer(for: schema, migrationPlan: JobhuntMigrationPlan.self, configurations: restoreConfig)
        let rCtx = ModelContext(restored)

        let jobs = try rCtx.fetch(FetchDescriptor<Job>())
        let captures = try rCtx.fetch(FetchDescriptor<Capture>())
        let events = try rCtx.fetch(FetchDescriptor<JobEvent>())

        XCTAssertEqual(jobs.count, 1)
        XCTAssertEqual(captures.count, 1)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(jobs.first?.capture?.rawHash, "h1", "Capture-Job relationship must survive backup/restore")
        XCTAssertEqual(events.first?.job?.jobNumber, 1, "Event-Job relationship must survive backup/restore")
    }

    // MARK: - TASK-333 Regression tests

    /// TASK-327: Restore must remove hyphen-separated WAL/SHM companions (jobhunt.store-wal, not jobhunt.store.wal)
    func testRestore_removesHyphenWalAndShm() throws {
        let (container, storeURL) = try makeFileBacked()
        defer { try? FileManager.default.removeItem(at: storeURL) }

        let ctx = ModelContext(container)
        ctx.insert(Setting(key: "k", value: "v"))
        try ctx.save()

        // Create a valid backup to restore from
        let backupURL = makeTempStoreURL()
        defer { try? FileManager.default.removeItem(at: backupURL) }
        try BackupService.backup(storeURL: storeURL, to: backupURL)

        // Create fake hyphen-style companion files alongside the store
        let walURL = storeURL.deletingLastPathComponent()
            .appendingPathComponent(storeURL.lastPathComponent + "-wal")
        let shmURL = storeURL.deletingLastPathComponent()
            .appendingPathComponent(storeURL.lastPathComponent + "-shm")
        FileManager.default.createFile(atPath: walURL.path, contents: Data("fake wal".utf8))
        FileManager.default.createFile(atPath: shmURL.path, contents: Data("fake shm".utf8))
        defer {
            try? FileManager.default.removeItem(at: walURL)
            try? FileManager.default.removeItem(at: shmURL)
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: walURL.path), "WAL companion must exist before restore")
        XCTAssertTrue(FileManager.default.fileExists(atPath: shmURL.path), "SHM companion must exist before restore")

        try BackupService.restore(from: backupURL, to: storeURL)

        XCTAssertFalse(FileManager.default.fileExists(atPath: walURL.path), "WAL companion must be removed after restore")
        XCTAssertFalse(FileManager.default.fileExists(atPath: shmURL.path), "SHM companion must be removed after restore")
    }

    /// TASK-328: If copy from backup fails (non-existent source), original store must survive intact
    func testRestore_atomicOnCopyFailure() throws {
        let (container, storeURL) = try makeFileBacked()
        defer { try? FileManager.default.removeItem(at: storeURL) }

        let ctx = ModelContext(container)
        ctx.insert(Setting(key: "original", value: "data"))
        try ctx.save()

        // Use a non-existent backup path — isValidSQLite will reject it, triggering notValidSQLite
        let nonExistentBackup = URL(fileURLWithPath: "/tmp/no_such_backup_\(UUID().uuidString).store")

        XCTAssertThrowsError(try BackupService.restore(from: nonExistentBackup, to: storeURL)) { error in
            guard case BackupService.BackupError.notValidSQLite = error else {
                XCTFail("Expected notValidSQLite, got \(error)")
                return
            }
        }

        // Original store must still exist and be intact
        XCTAssertTrue(FileManager.default.fileExists(atPath: storeURL.path), "Original store must survive a failed restore")
    }

    /// TASK-331: isValidSQLite must reject a valid SQLite file that has no Jobhunt tables
    func testIsValidSQLite_rejectsArbitrarySQLite() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("arbitrary_\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }

        // Create a valid SQLite database but with no Jobhunt tables
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &db), SQLITE_OK)
        sqlite3_exec(db, "CREATE TABLE unrelated (id INTEGER PRIMARY KEY)", nil, nil, nil)
        sqlite3_close(db)

        XCTAssertFalse(BackupService.isValidSQLite(at: url), "Arbitrary SQLite without Jobhunt tables must be rejected")
    }

    /// TASK-331: isValidSQLite must reject files with random bytes (not a SQLite file)
    func testIsValidSQLite_rejectsCorruptedFile() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("corrupt_\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }

        let junk = Data(repeating: 0xFF, count: 256)
        try junk.write(to: url)

        XCTAssertFalse(BackupService.isValidSQLite(at: url), "File with random bytes must be rejected")
    }

    // MARK: - TASK-373 / TASK-374: validate-before-swap + atomic move-aside restore

    /// TASK-373/374: A Jobhunt-looking SQLite that passes the cheap magic+table check but is NOT a
    /// loadable CoreData store must be rejected during restore (after staging, before the swap),
    /// and the original live store must survive intact and readable.
    func testRestore_rejectsSchemaIncompatibleBackup_originalSurvives() throws {
        let (container, storeURL) = try makeFileBacked()
        defer { try? FileManager.default.removeItem(at: storeURL) }

        let ctx = ModelContext(container)
        ctx.insert(Job(jobNumber: 777, title: "Original Job"))
        ctx.insert(Setting(key: "original", value: "data"))
        try ctx.save()

        // Craft a file that has a ZJOB table (so isValidSQLite passes) but is not a valid CoreData
        // store (no Z_METADATA/Z_PRIMARYKEY) — opening it with the migration plan must fail.
        let fakeBackup = makeTempStoreURL()
        defer { try? FileManager.default.removeItem(at: fakeBackup) }
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(fakeBackup.path, &db), SQLITE_OK)
        sqlite3_exec(db, "CREATE TABLE ZJOB (Z_PK INTEGER PRIMARY KEY, ZTITLE TEXT)", nil, nil, nil)
        sqlite3_close(db)
        XCTAssertTrue(BackupService.isValidSQLite(at: fakeBackup), "Precondition: cheap check passes")

        XCTAssertThrowsError(try BackupService.restore(from: fakeBackup, to: storeURL)) { error in
            guard case BackupService.BackupError.incompatibleStore = error else {
                XCTFail("Expected incompatibleStore, got \(error)")
                return
            }
        }

        // The original store must still be present, openable, and hold its original rows.
        XCTAssertTrue(FileManager.default.fileExists(atPath: storeURL.path),
                      "Original store must survive a rejected restore")
        let schema = Schema(SchemaV1.models)
        let reopenConfig = ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)
        let reopened = try ModelContainer(for: schema, migrationPlan: JobhuntMigrationPlan.self, configurations: reopenConfig)
        let rCtx = ModelContext(reopened)
        let jobs = try rCtx.fetch(FetchDescriptor<Job>())
        XCTAssertEqual(jobs.count, 1, "Original data must be intact after a rejected restore")
        XCTAssertEqual(jobs.first?.jobNumber, 777)
    }

    /// TASK-373/374: A valid backup restores successfully and the store reopens with the backup's
    /// data (and none of the pre-restore data).
    func testRestore_replacesDataAndStoreIsReadable() throws {
        let (container, storeURL) = try makeFileBacked()
        defer { try? FileManager.default.removeItem(at: storeURL) }

        // State A: snapshot a backup containing only job #1.
        let ctxA = ModelContext(container)
        ctxA.insert(Job(jobNumber: 1, title: "Backed-up Job"))
        try ctxA.save()
        let backupURL = makeTempStoreURL()
        defer { try? FileManager.default.removeItem(at: backupURL) }
        try BackupService.backup(storeURL: storeURL, to: backupURL)

        // State B: mutate the live store to a different shape (add job #2).
        ctxA.insert(Job(jobNumber: 2, title: "Post-backup Job"))
        try ctxA.save()

        // Restore back to state A.
        try BackupService.restore(from: backupURL, to: storeURL)

        // Reopen and verify only the backed-up state is present.
        let schema = Schema(SchemaV1.models)
        let reopenConfig = ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)
        let reopened = try ModelContainer(for: schema, migrationPlan: JobhuntMigrationPlan.self, configurations: reopenConfig)
        let rCtx = ModelContext(reopened)
        let jobs = try rCtx.fetch(FetchDescriptor<Job>()).sorted { ($0.jobNumber ?? 0) < ($1.jobNumber ?? 0) }
        XCTAssertEqual(jobs.map(\.jobNumber), [1], "Restore must yield exactly the backed-up state")

        // No staging/aside leftovers remain next to the store.
        for suffix in [".incoming", ".old", ".old-wal", ".old-shm"] {
            let leftover = storeURL.deletingLastPathComponent()
                .appendingPathComponent(storeURL.lastPathComponent + suffix)
            XCTAssertFalse(FileManager.default.fileExists(atPath: leftover.path),
                           "Restore must not leave \(suffix) behind")
        }
    }

    /// TASK-331: isValidSQLite must accept a backup created by BackupService.backup
    func testIsValidSQLite_acceptsValidBackup() throws {
        let (container, storeURL) = try makeFileBacked()
        defer { try? FileManager.default.removeItem(at: storeURL) }

        let ctx = ModelContext(container)
        ctx.insert(Job(jobNumber: 99, title: "Valid Backup Job"))
        try ctx.save()

        let backupURL = makeTempStoreURL()
        defer { try? FileManager.default.removeItem(at: backupURL) }
        try BackupService.backup(storeURL: storeURL, to: backupURL)

        XCTAssertTrue(BackupService.isValidSQLite(at: backupURL), "Backup produced by BackupService must be valid")
    }
}
