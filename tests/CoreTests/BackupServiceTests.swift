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
}
