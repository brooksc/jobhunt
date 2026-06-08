import Foundation
import SwiftData

public enum ModelContainerFactory {
    // Production container stored in the app's Application Support directory.
    public static func production() throws -> ModelContainer {
        let schema = Schema(SchemaV1.models)
        let url = productionStoreURL()
        let config = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, migrationPlan: JobhuntMigrationPlan.self, configurations: config)
    }

    // In-memory container for unit tests — isolated, never touches disk.
    public static func inMemory() throws -> ModelContainer {
        let schema = Schema(SchemaV1.models)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, migrationPlan: JobhuntMigrationPlan.self, configurations: config)
    }

    private static func productionStoreURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Jobhunt", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("jobhunt.store")
    }
}
