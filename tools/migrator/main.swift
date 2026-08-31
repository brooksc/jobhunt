// JobhuntMigrator — external CLI for one-time data fixups on the live Jobhunt SwiftData store.
// Project convention: such work lives here, never in the app's launch path (the store is
// single-writer, so it must run out-of-band with the app quit).
//
// Usage:
//   JobhuntMigrator --reclean [--store <path>]     (and the other operation flags — see Args.swift)
//
// NOT shipped in the app. DMG scheme only.
// Implementation is split by responsibility in the sibling files:
//   Args.swift, SQLiteHelpers.swift, RepairJobNumbers.swift

import Foundation
import JobhuntCore
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
/// Every mode opens the live store read-write, so this is unconditional.
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

/// Open the live store read-write, with the banner every mode prints. Exits on failure.
func openLiveStore(_ storePath: String, title: String) -> BackgroundStore {
    guard FileManager.default.fileExists(atPath: storePath) else {
        fputs("Error: store not found at '\(storePath)'\n", stderr); exit(1)
    }
    print("=== \(title) ===")
    print("Store: \(storePath)")
    print("(Run with the Jobhunt app quit — the store is single-writer.)")
    let schema = Schema(SchemaV1.models)
    let config = ModelConfiguration(
        schema: schema, url: URL(fileURLWithPath: storePath), cloudKitDatabase: .none
    )
    do {
        return try BackgroundStore(
            modelContainer: ModelContainer(
                for: schema, migrationPlan: JobhuntMigrationPlan.self, configurations: config
            )
        )
    } catch {
        fputs("Error: could not open store: \(error)\n", stderr); exit(1)
    }
}

requireAppNotRunning()

switch mode {
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

case let .recheckEvidence(storePath):
    guard FileManager.default.fileExists(atPath: storePath) else {
        fputs("Error: store not found at '\(storePath)'\n", stderr); exit(1)
    }
    print("=== Recheck Fabricated Evidence ===")
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
        let result = try await store.recheckStoredEvidence()
        print("Recheck complete: \(result.checked) analysis/analyses checked, "
            + "\(result.flagged) verdict(s) marked as citing evidence the résumé doesn't support.")
        print("No scores changed — the check marks, it doesn't overrule. Review the flagged rows in "
            + "the Fit tab and use \"I don't have this\" on any that are genuinely wrong.")
        if result.skipped > 0 {
            print("Skipped \(result.skipped) with no résumé or posting text to check against.")
        }
    } catch {
        fputs("Error: recheck failed: \(error)\n", stderr); exit(1)
    }

case let .normalizeSeniority(storePath):
    guard FileManager.default.fileExists(atPath: storePath) else {
        fputs("Error: store not found at '\(storePath)'\n", stderr); exit(1)
    }
    print("=== Normalize Seniority ===")
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
        let result = try await store.normalizeStoredSeniority()
        print("Normalize complete: \(result.changed) job(s) updated, "
            + "\(result.cleared) cleared to null (no level in the stored text).")
    } catch {
        fputs("Error: normalize failed: \(error)\n", stderr); exit(1)
    }

case let .repairSalaries(storePath):
    guard FileManager.default.fileExists(atPath: storePath) else {
        fputs("Error: store not found at '\(storePath)'\n", stderr); exit(1)
    }
    print("=== Repair Invented Salary Bands ===")
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
        let result = try await store.repairStoredSalariesFromSettings()
        print("Repair complete: \(result.corrected) job(s) re-parsed to a corrected band, "
            + "\(result.cleared) cleared (the posting states no pay).")
        if result.skippedOverridden > 0 {
            print("Left alone: \(result.skippedOverridden) job(s) whose salary you edited by hand.")
        }
    } catch {
        fputs("Error: repair failed: \(error)\n", stderr); exit(1)
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

case let .repairRemoteTypes(storePath):
    guard FileManager.default.fileExists(atPath: storePath) else {
        fputs("Error: store not found at '\(storePath)'\n", stderr); exit(1)
    }
    print("=== Repair Erased Work Arrangements ===")
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
        let result = try await store.repairRemoteTypesFromExtractedJSON()
        let breakdown = RemoteType.allCases
            .compactMap { type in result.restored[type].map { "\($0) \(type.rawValue)" } }
            .joined(separator: ", ")
        print("Repair complete: \(result.totalRestored) arrangement(s) restored from stored extractions"
            + (breakdown.isEmpty ? "." : " (\(breakdown))."))
        print("Re-judged: \(result.criteriaChanged) job(s) changed their meets-criteria verdict.")
        print("Left alone: \(result.skippedOverridden) with a hand-edited arrangement, "
            + "\(result.skippedUnrecoverable) with nothing recoverable in their extraction.")
    } catch {
        fputs("Error: repair failed: \(error)\n", stderr); exit(1)
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

case let .mergeJob(storePath, from, into):
    guard FileManager.default.fileExists(atPath: storePath) else {
        fputs("Error: store not found at '\(storePath)'\n", stderr); exit(1)
    }
    print("=== Merge Job #\(from) into Job #\(into) ===")
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
        let result = try await store.mergeJob(from: from, into: into)
        let filled = result.fieldsCopied.isEmpty ? "none (nothing was missing)" : result.fieldsCopied
            .joined(separator: ", ")
        print("Merge complete: job #\(result.removedJobNumber) deleted; kept job #\(result.keptJobNumber).")
        print("Fields filled in on the kept job: \(filled)")
    } catch {
        fputs("Error: merge failed: \(error)\n", stderr); exit(1)
    }

case let .backfillFitVersions(storePath):
    let store = openLiveStore(storePath, title: "Backfill Fit Rubric Versions")
    do {
        let result = try await store.backfillFitScorePromptVersions()
        print("Backfill complete: \(result.updated) score(s) had their rubric version filled in "
            + "from stored JSON (no LLM calls).")
        if result.unversioned > 0 {
            print("Left unversioned: \(result.unversioned) score(s) whose analysis records no version "
                + "— unknown, not v1.")
        }
    } catch {
        fputs("Error: backfill failed: \(error)\n", stderr); exit(1)
    }

case let .fitVersionHistogram(storePath):
    let store = openLiveStore(storePath, title: "Fit Rubric Version Histogram")
    do {
        let rows = try await store.fitScorePromptVersionHistogram()
        let total = rows.reduce(0) { $0 + $1.count }
        print("Current rubric: v\(FitScorer.assessmentPromptVersion)")
        for row in rows {
            let name = row.version.map { "v\($0)" } ?? "(no version recorded)"
            let mean = row.meanScore.map { String(format: "mean %.1f", $0) } ?? "no numeric scores"
            print("  \(name): \(row.count) score(s), \(mean)")
        }
        print("Total: \(total) stored score(s).")
        print("(Counts read the stored column — run --backfill-fit-versions first if it looks empty.)")
    } catch {
        fputs("Error: histogram failed: \(error)\n", stderr); exit(1)
    }

case let .rescoreStaleFitScores(storePath, confirmed, limit):
    let store = openLiveStore(storePath, title: "Rescore Stale Fit Scores")
    do {
        let current = FitScorer.assessmentPromptVersion
        var targets = try await store.staleFitScores(currentVersion: current)
        if let limit { targets = Array(targets.prefix(limit)) }
        let plan = try await RescorePlan(targets: targets, config: store.storedScoringConfig())
        guard describeRescorePlan(plan, currentVersion: current) else { break }
        guard confirmed else {
            print("Nothing sent. Re-run with --yes to spend that; --limit <n> to try a few first.")
            break
        }
        let apiKey = ProcessInfo.processInfo.environment[apiKeyEnvironmentVariable] ?? ""
        guard !apiKey.isEmpty || !LLMProviderFactory.requiresAPIKey(provider: plan.config.provider) else {
            fputs("Error: \(plan.config.provider) needs an API key — set \(apiKeyEnvironmentVariable).\n", stderr)
            exit(1)
        }
        try await runRescore(
            plan: plan, store: store,
            feedback: store.scoringFeedbackForRescore(), apiKey: apiKey
        )
    } catch {
        fputs("Error: rescore failed: \(error)\n", stderr); exit(1)
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
}
