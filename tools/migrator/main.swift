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

/// Announce which build is about to touch the store.
///
/// TASK-652: a stale binary silently ran superseded logic — `--recompute-fit-mirrors` reported
/// "0 corrected" against 206 provably-wrong mirrors, and "0 corrected" is indistinguishable from
/// "already correct". The cause was two DerivedData trees, so builds succeeded into a directory other
/// than the binary being run. Printing the compile date makes a months-old binary obvious BEFORE it
/// mutates anything. Build with scripts/build-migrator.sh, which pins the same path.
func printBuildIdentity() {
    // __DATE__/__TIME__ have no Swift equivalent; the executable's own mtime is the build time.
    let path = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
    let built = (try? FileManager.default.attributesOfItem(atPath: path.path)[.modificationDate] as? Date)
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm"
    let stamp = built.map { formatter.string(from: $0) } ?? "unknown"
    FileHandle.standardError.write(Data("JobhuntMigrator (built \(stamp))\n".utf8))
    if let built, Date().timeIntervalSince(built) > 24 * 3600 {
        FileHandle.standardError.write(Data(
            "  ⚠︎ This binary is more than a day old. If the code has changed since, rebuild first:\n"
                .utf8
        ))
        FileHandle.standardError.write(Data("     ./scripts/build-migrator.sh\n".utf8))
    }
}

printBuildIdentity()

guard let mode = parseArgs() else { exit(1) }

/// The SwiftData store is single-writer and not multi-process-safe. Refuse to open it read-write
/// while the Jobhunt app is running (TASK-470) — two writers on the same SQLite file corrupt it.
/// Matches the pgrep precondition in scripts/migrate-db.py.
func requireAppNotRunning() {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
    task.arguments = ["-x", "Jobhunt"]
    task.standardOutput = Pipe()
    task.standardError = Pipe()
    do {
        try task.run()
        task.waitUntilExit()
        if task.terminationStatus == 0 {
            fputs(
                "Error: Jobhunt is running — the store is single-writer. Quit it first:\n"
                    + "  osascript -e 'quit app \"Jobhunt\"'\n",
                stderr
            )
            exit(1)
        }
    } catch {
        fputs("Warning: could not check whether Jobhunt is running (\(error)). Ensure it is quit.\n", stderr)
    }
}

if mode.mutatesLiveStore {
    requireAppNotRunning()
}

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
    print("  events inserted:             \(patchSummary.events)")
    print("  saved searches inserted:     \(patchSummary.savedSearches)")
    print("  settings inserted:           \(patchSummary.settings)")
    print("  captures re-cleaned:         \(patchSummary.recleanedCaptures)")
    print("  already-present (skipped):   \(patchSummary.skipped)")

case let .reclean(storePath):
    guard FileManager.default.fileExists(atPath: storePath) else {
        fputs("Error: store not found at '\(storePath)'\n", stderr); exit(1)
    }
    print("=== Re-clean Captures ===")
    print("Store: \(storePath)")
    print("(Run with the Jobhunt app quit — the store is single-writer.)")
    let storeURL = URL(fileURLWithPath: storePath)
    let schema = Schema(SchemaV1.models)
    let config = ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)
    let container: ModelContainer
    do {
        container = try ModelContainer(for: schema, migrationPlan: JobhuntMigrationPlan.self, configurations: config)
    } catch {
        fputs("Error: could not open store: \(error)\n", stderr); exit(1)
    }
    let store = BackgroundStore(modelContainer: container)
    do {
        let changed = try await store.recleanAllCaptures()
        print("Re-clean complete: \(changed) capture(s) updated.")
    } catch {
        fputs("Error: re-clean failed: \(error)\n", stderr); exit(1)
    }

case let .backfillModels(storePath):
    guard FileManager.default.fileExists(atPath: storePath) else {
        fputs("Error: store not found at '\(storePath)'\n", stderr); exit(1)
    }
    print("=== Backfill LLM Request Models ===")
    print("Store: \(storePath)")
    print("(Run with the Jobhunt app quit — the store is single-writer.)")
    let storeURL = URL(fileURLWithPath: storePath)
    let schema = Schema(SchemaV1.models)
    let config = ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)
    let container: ModelContainer
    do {
        container = try ModelContainer(for: schema, migrationPlan: JobhuntMigrationPlan.self, configurations: config)
    } catch {
        fputs("Error: could not open store: \(error)\n", stderr); exit(1)
    }
    let store = BackgroundStore(modelContainer: container)
    do {
        try await store.backfillRequestModels()
        print("Backfill complete.")
    } catch {
        fputs("Error: backfill failed: \(error)\n", stderr); exit(1)
    }

case let .pruneOrphanFitScores(storePath):
    guard FileManager.default.fileExists(atPath: storePath) else {
        fputs("Error: store not found at '\(storePath)'\n", stderr); exit(1)
    }
    print("=== Prune Orphan Fit Scores ===")
    print("Store: \(storePath)")
    print("(Run with the Jobhunt app quit — the store is single-writer.)")
    let storeURL = URL(fileURLWithPath: storePath)
    let schema = Schema(SchemaV1.models)
    let config = ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)
    let container: ModelContainer
    do {
        container = try ModelContainer(for: schema, migrationPlan: JobhuntMigrationPlan.self, configurations: config)
    } catch {
        fputs("Error: could not open store: \(error)\n", stderr); exit(1)
    }
    let store = BackgroundStore(modelContainer: container)
    do {
        let deleted = try await store.pruneOrphanFitScores()
        print("Prune complete: \(deleted) orphan fit score(s) deleted; affected jobs recomputed.")
    } catch {
        fputs("Error: prune failed: \(error)\n", stderr); exit(1)
    }

case let .pruneOrphanReferralAttempts(storePath):
    guard FileManager.default.fileExists(atPath: storePath) else {
        fputs("Error: store not found at '\(storePath)'\n", stderr); exit(1)
    }
    print("=== Prune Orphan Referral Attempts ===")
    print("Store: \(storePath)")
    print("(Run with the Jobhunt app quit — the store is single-writer.)")
    let storeURL = URL(fileURLWithPath: storePath)
    let schema = Schema(SchemaV1.models)
    let config = ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)
    let container: ModelContainer
    do {
        container = try ModelContainer(for: schema, migrationPlan: JobhuntMigrationPlan.self, configurations: config)
    } catch {
        fputs("Error: could not open store: \(error)\n", stderr); exit(1)
    }
    let store = BackgroundStore(modelContainer: container)
    do {
        let deleted = try await store.pruneOrphanReferralAttempts()
        print("Prune complete: \(deleted) orphan referral attempt(s) deleted.")
    } catch {
        fputs("Error: prune failed: \(error)\n", stderr); exit(1)
    }

case let .pruneOrphanAttempts(storePath):
    guard FileManager.default.fileExists(atPath: storePath) else {
        fputs("Error: store not found at '\(storePath)'\n", stderr); exit(1)
    }
    print("=== Prune Orphan LLM Request Attempts ===")
    print("Store: \(storePath)")
    print("(Run with the Jobhunt app quit — the store is single-writer.)")
    let storeURL = URL(fileURLWithPath: storePath)
    let schema = Schema(SchemaV1.models)
    let config = ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)
    let container: ModelContainer
    do {
        container = try ModelContainer(for: schema, migrationPlan: JobhuntMigrationPlan.self, configurations: config)
    } catch {
        fputs("Error: could not open store: \(error)\n", stderr); exit(1)
    }
    let store = BackgroundStore(modelContainer: container)
    do {
        let deleted = try await store.pruneOrphanRequestAttempts()
        print("Prune complete: \(deleted) orphan attempt(s) deleted.")
    } catch {
        fputs("Error: prune failed: \(error)\n", stderr); exit(1)
    }

case let .recomputeFitMirrors(storePath):
    guard FileManager.default.fileExists(atPath: storePath) else {
        fputs("Error: store not found at '\(storePath)'\n", stderr); exit(1)
    }
    print("=== Recompute Job Fit Mirrors ===")
    print("Store: \(storePath)")
    print("(Run with the Jobhunt app quit — the store is single-writer.)")
    let storeURL = URL(fileURLWithPath: storePath)
    let schema = Schema(SchemaV1.models)
    let config = ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)
    let container: ModelContainer
    do {
        container = try ModelContainer(for: schema, migrationPlan: JobhuntMigrationPlan.self, configurations: config)
    } catch {
        fputs("Error: could not open store: \(error)\n", stderr); exit(1)
    }
    let store = BackgroundStore(modelContainer: container)
    do {
        let changed = try await store.recomputeAllJobFitMirrors()
        print("Recompute complete: \(changed) job mirror(s) corrected.")
    } catch {
        fputs("Error: recompute failed: \(error)\n", stderr); exit(1)
    }

case let .recomputeCriteria(storePath):
    guard FileManager.default.fileExists(atPath: storePath) else {
        fputs("Error: store not found at '\(storePath)'\n", stderr); exit(1)
    }
    print("=== Recompute Location Criteria ===")
    print("Store: \(storePath)")
    print("(Run with the Jobhunt app quit — the store is single-writer.)")
    let storeURL = URL(fileURLWithPath: storePath)
    let schema = Schema(SchemaV1.models)
    let config = ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)
    let container: ModelContainer
    do {
        container = try ModelContainer(for: schema, migrationPlan: JobhuntMigrationPlan.self, configurations: config)
    } catch {
        fputs("Error: could not open store: \(error)\n", stderr); exit(1)
    }
    let store = BackgroundStore(modelContainer: container)
    do {
        let changed = try await store.recomputeMeetsCriteriaFromSettings()
        print("Recompute complete: \(changed) job(s) re-judged against the current location settings.")
    } catch {
        fputs("Error: recompute failed: \(error)\n", stderr); exit(1)
    }

case let .repairCanonicalURLs(storePath):
    guard FileManager.default.fileExists(atPath: storePath) else {
        fputs("Error: store not found at '\(storePath)'\n", stderr); exit(1)
    }
    print("=== Repair Untrustworthy Canonical URLs ===")
    print("Store: \(storePath)")
    print("(Run with the Jobhunt app quit — the store is single-writer.)")
    let storeURL = URL(fileURLWithPath: storePath)
    let schema = Schema(SchemaV1.models)
    let config = ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)
    let container: ModelContainer
    do {
        container = try ModelContainer(for: schema, migrationPlan: JobhuntMigrationPlan.self, configurations: config)
    } catch {
        fputs("Error: could not open store: \(error)\n", stderr); exit(1)
    }
    let store = BackgroundStore(modelContainer: container)
    do {
        let cleared = try await store.repairUntrustworthyCanonicalURLs()
        print("Repair complete: \(cleared) capture(s) had a non-identifying canonical URL cleared.")
    } catch {
        fputs("Error: repair failed: \(error)\n", stderr); exit(1)
    }

case let .detectDuplicates(storePath):
    guard FileManager.default.fileExists(atPath: storePath) else {
        fputs("Error: store not found at '\(storePath)'\n", stderr); exit(1)
    }
    print("=== Detect & Flag Duplicates ===")
    print("Store: \(storePath)")
    print("(Run with the Jobhunt app quit — the store is single-writer.)")
    let storeURL = URL(fileURLWithPath: storePath)
    let schema = Schema(SchemaV1.models)
    let config = ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)
    let container: ModelContainer
    do {
        container = try ModelContainer(for: schema, migrationPlan: JobhuntMigrationPlan.self, configurations: config)
    } catch {
        fputs("Error: could not open store: \(error)\n", stderr); exit(1)
    }
    let store = BackgroundStore(modelContainer: container)
    do {
        let flagged = try await store.detectAndPersistDomainDuplicates()
        print("Detection complete: \(flagged) job(s) newly flagged as duplicates.")
    } catch {
        fputs("Error: detection failed: \(error)\n", stderr); exit(1)
    }

case let .unmarkHeuristicDuplicates(storePath):
    guard FileManager.default.fileExists(atPath: storePath) else {
        fputs("Error: store not found at '\(storePath)'\n", stderr); exit(1)
    }
    print("=== Un-mark Heuristic Duplicates (TASK-622) ===")
    print("Store: \(storePath)")
    print("(Run with the Jobhunt app quit — the store is single-writer.)")
    let storeURL = URL(fileURLWithPath: storePath)
    let schema = Schema(SchemaV1.models)
    let config = ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)
    let container: ModelContainer
    do {
        container = try ModelContainer(for: schema, migrationPlan: JobhuntMigrationPlan.self, configurations: config)
    } catch {
        fputs("Error: could not open store: \(error)\n", stderr); exit(1)
    }
    let store = BackgroundStore(modelContainer: container)
    do {
        let recovered = try await store.unmarkHeuristicDuplicates()
        print("Recovery complete: \(recovered) fuzzy-flagged job(s) un-marked and restored "
            + "(definitive same-posting duplicates kept).")
    } catch {
        fputs("Error: recovery failed: \(error)\n", stderr); exit(1)
    }

case let .repairDuplicateJobNumbers(storePath):
    guard FileManager.default.fileExists(atPath: storePath) else {
        fputs("Error: store not found at '\(storePath)'\n", stderr); exit(1)
    }
    print("=== Repair Duplicate Job Numbers ===")
    print("Store: \(storePath)")
    print("(Run with the Jobhunt app quit — the store is single-writer. Back up first.)")
    // Raw SQLite: a store with duplicate job numbers can't be opened by SwiftData (the unique
    // index fails), so this runs before any ModelContainer open. Renumbers collisions, keeping
    // the oldest row's number — non-destructive.
    guard let result = repairDuplicateJobNumbers(at: storePath) else {
        fputs("Error: repair failed.\n", stderr); exit(1)
    }
    if result.duplicatesFound == 0 {
        print("No duplicate job numbers found — nothing to repair.")
    } else {
        print("Repair complete: renumbered \(result.renumbered) of \(result.duplicatesFound) duplicate row(s).")
    }

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
    if summary.skippedOrphans > 0 {
        var parts: [String] = []
        if summary.skippedOrphanEvents > 0 { parts.append("events=\(summary.skippedOrphanEvents)") }
        if summary.skippedOrphanActions > 0 { parts.append("actions=\(summary.skippedOrphanActions)") }
        if summary
            .skippedOrphanDataQualityReviews >
            0 { parts.append("dataQualityReviews=\(summary.skippedOrphanDataQualityReviews)") }
        if summary.skippedOrphanFitScores > 0 { parts.append("fitScores=\(summary.skippedOrphanFitScores)") }
        if summary.skippedOrphanLLMRequests > 0 { parts.append("llmRequests=\(summary.skippedOrphanLLMRequests)") }
        if summary
            .skippedOrphanLLMRequestAttempts >
            0 { parts.append("llmRequestAttempts=\(summary.skippedOrphanLLMRequestAttempts)") }
        if summary.skippedOrphanContacts > 0 { parts.append("contacts=\(summary.skippedOrphanContacts)") }
        if summary.skippedOrphanCoverLetters > 0 { parts.append("coverLetters=\(summary.skippedOrphanCoverLetters)") }
        print("")
        print("Skipped \(summary.skippedOrphans) orphan row(s): \(parts.joined(separator: ", "))")
    }
    print("")
    print("Store written to: \(outputPath)")
}
