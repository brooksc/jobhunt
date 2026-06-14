import Foundation
import SwiftData

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

    /// In-memory container for unit tests — isolated, never touches disk.
    public static func inMemory() throws -> ModelContainer {
        let schema = Schema(SchemaV1.models)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, migrationPlan: JobhuntMigrationPlan.self, configurations: config)
    }

    /// Copies the fixture SQLite at `source` to a temp path and opens it.
    /// Tests get an isolated mutable copy — the committed fixture is never touched.
    public static func fixture(copying source: URL) throws -> ModelContainer {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("JobhuntFixture/jobhunt-fixture.store")
        try? FileManager.default.createDirectory(
            at: tmp.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Always start fresh — remove any leftover from a prior run
        for ext in ["", ".shm", ".wal"] {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: tmp.path + ext))
        }
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
