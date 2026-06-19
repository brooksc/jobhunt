import Foundation
import SwiftData

// MARK: - Uniqueness-constraint strategy (TASK-372)

//
// SwiftData enforces `@Attribute(.unique)` with a SQLite unique index. A store that already holds
// duplicate values on a newly-constrained column can't be opened — index creation fails during
// migration and `ModelContainer(...)` throws. The app handles that throw by showing
// `StoreRecoveryView` (restore-from-backup / start-fresh) rather than crashing, so a constrained
// store always fails *closed*, never silently corrupting data.
//
// Before adding a NEW uniqueness constraint to an existing field, ship a one-shot **JobhuntMigrator**
// repair mode that removes/renumbers duplicates (run out-of-band, app quit), the same way
// `jobNumber` uniqueness is recovered today by `--repair-duplicate-job-numbers`
// (`tools/migrator/RepairJobNumbers.swift`, raw SQLite — it must run *before* any `ModelContainer`
// open). Do NOT auto-dedup on launch: per project convention one-time fixups live in the CLI, and a
// launch-path repair would add risk and a "have we done this yet?" flag to the critical open path.
//
// Unique fields today: `Job.jobNumber`, `Capture.rawHash`, `Site.origin`, `Setting.key`,
// `DuplicateDecision.cleanedHash`, `SavedSearch.id` (TASK-522). Only `jobNumber` has — and needs — a
// repair: app-created numbers can't collide (atomic ingest under the single-writer store), but the
// Electron import CAN carry duplicate `job_number`s, which `--repair-duplicate-job-numbers` recovers.
// The rest are unique at their source or by construction: `rawHash`/`cleanedHash` are the content-dedup
// keys the source already enforces (so import can't produce collisions — and blind dedup would orphan
// jobs referencing a dropped capture); `origin`/`key` are natural identities; `SavedSearch.id` is a
// UUID. A duplicate on any of those could only come from an externally-modified store and fails
// *closed* (recovery UI). If that ever happens for a real store, add a targeted RepairJobNumbers-style
// raw-SQLite repair for that one field then — don't pre-build speculative repairs.
public enum ModelContainerFactory {
    /// Production container stored in the app's Application Support directory.
    public static func production() throws -> ModelContainer {
        let schema = Schema(SchemaV1.models)
        let url = productionStoreURL()
        let config = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, migrationPlan: JobhuntMigrationPlan.self, configurations: config)
    }

    /// On-disk container at an explicit path — used by UI tests for isolation from the production store.
    public static func test(at url: URL) throws -> ModelContainer {
        let schema = Schema(SchemaV1.models)
        let config = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, migrationPlan: JobhuntMigrationPlan.self, configurations: config)
    }

    /// The store file + its CoreData/SQLite WAL/SHM sidecars. The sidecars are hyphen-suffixed
    /// (`…store-wal` / `…store-shm`) — the names SQLite actually creates — NOT `.wal`/`.shm`
    /// extensions (TASK-424).
    public static func storeAndSidecars(of url: URL) -> [URL] {
        let dir = url.deletingLastPathComponent()
        let name = url.lastPathComponent
        return [
            url,
            dir.appendingPathComponent(name + "-wal"),
            dir.appendingPathComponent(name + "-shm")
        ]
    }

    /// Like `test(at:)` but FAILS CLOSED (TASK-424): creates the parent directory and removes any
    /// existing store + sidecars, throwing if that cleanup can't complete — so a UI-test run can never
    /// silently open stale data left by a previous run.
    public static func freshTestStore(at url: URL) throws -> ModelContainer {
        let fm = FileManager.default
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        for file in storeAndSidecars(of: url) where fm.fileExists(atPath: file.path) {
            try fm.removeItem(at: file)
        }
        return try test(at: url)
    }

    /// In-memory container for unit tests — isolated, never touches disk.
    public static func inMemory() throws -> ModelContainer {
        let schema = Schema(SchemaV1.models)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, migrationPlan: JobhuntMigrationPlan.self, configurations: config)
    }

    /// Copies the fixture SQLite at `source` to a fresh, unique temp directory and opens it.
    /// Each caller gets its own isolated copy in a per-call UUID directory, so parallel test runs
    /// and simultaneous launches never race on a shared destination (TASK-420). The caller owns the
    /// returned container; the temp copy is left for the OS to reclaim (it's under NSTemporaryDirectory).
    /// The committed fixture at `source` is never touched.
    public static func fixture(copying source: URL) throws -> ModelContainer {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("JobhuntFixture", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let tmp = dir.appendingPathComponent("jobhunt-fixture.store")
        try FileManager.default.copyItem(at: source, to: tmp)
        return try test(at: tmp)
    }

    public static func productionStoreURL() -> URL {
        // urls(for:in:) returns an empty array only on simulator/tests; guard is a safety net.
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else {
            return URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Jobhunt/jobhunt.store")
        }
        let dir = appSupport.appendingPathComponent("Jobhunt", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("jobhunt.store")
    }
}
