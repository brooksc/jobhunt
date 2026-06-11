// JobhuntMigrator — one-time external tool to migrate legacy jobhunt.db (SQLite)
// to a SwiftData store usable by the native Jobhunt app.
//
// Usage:
//   JobhuntMigrator [--input <path>] --output <path>
//   JobhuntMigrator --repair-fit-scores [--store <path>]
//
// NOT shipped in the app. DMG scheme only.
// Implementation is split by responsibility in the sibling files:
//   Args.swift, SQLiteHelpers.swift, Migration.swift, Verify.swift, Patch.swift, FitScores.swift

import Foundation
import JobhuntCore
import SQLite3
import SwiftData

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
