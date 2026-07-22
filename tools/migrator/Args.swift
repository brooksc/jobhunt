import Foundation

// MARK: - CLI Modes

enum Mode {
    case migrate(inputPath: String, outputPath: String)
    case repairFitScores(storePath: String)
    case verify(inputPath: String, storePath: String)
    case patch(inputPath: String, storePath: String)
    case patchFitScores(inputPath: String, storePath: String)
    case reclean(storePath: String)
    case backfillModels(storePath: String)
    case pruneOrphanFitScores(storePath: String)
    case pruneOrphanAttempts(storePath: String)
    case recomputeFitMirrors(storePath: String)
    case detectDuplicates(storePath: String)
    case repairDuplicateJobNumbers(storePath: String)
    case unmarkHeuristicDuplicates(storePath: String)

    /// True for modes that open the live store read-WRITE. The store is single-writer, so these
    /// must not run while the Jobhunt app is running (TASK-470). `migrate` writes a NEW output
    /// store and `verify` is read-only, so neither needs the guard.
    var mutatesLiveStore: Bool {
        switch self {
        case .migrate, .verify:
            return false
        case .repairFitScores, .patch, .patchFitScores, .reclean, .backfillModels,
             .pruneOrphanFitScores, .pruneOrphanAttempts, .recomputeFitMirrors, .detectDuplicates,
             .repairDuplicateJobNumbers, .unmarkHeuristicDuplicates:
            return true
        }
    }
}

func parseArgs(_ args: [String] = CommandLine.arguments) -> Mode? {
    let defaultStorePath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Jobhunt/jobhunt.store")
        .path
    let defaultInputPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Jobhunt/jobhunt.db")
        .path

    var repair = false
    var verify = false
    var patch = false
    var patchFit = false
    var reclean = false
    var backfillModels = false
    var pruneOrphanFitScores = false
    var pruneOrphanAttempts = false
    var recomputeFitMirrors = false
    var detectDuplicates = false
    var repairDuplicateJobNumbers = false
    var unmarkHeuristicDuplicates = false
    var storePath = defaultStorePath
    var inputPath = defaultInputPath
    var outputPath: String? = nil

    var i = 1
    while i < args.count {
        switch args[i] {
        case "--repair-fit-scores":
            repair = true
        case "--verify":
            verify = true
        case "--patch":
            patch = true
        case "--patch-fit-scores":
            patchFit = true
        case "--reclean":
            reclean = true
        case "--backfill-models":
            backfillModels = true
        case "--prune-orphan-fit-scores":
            pruneOrphanFitScores = true
        case "--prune-orphan-attempts":
            pruneOrphanAttempts = true
        case "--recompute-fit-mirrors":
            recomputeFitMirrors = true
        case "--detect-duplicates":
            detectDuplicates = true
        case "--repair-duplicate-job-numbers":
            repairDuplicateJobNumbers = true
        case "--unmark-heuristic-duplicates":
            unmarkHeuristicDuplicates = true
        case "--store":
            i += 1
            guard i < args.count, !args[i].hasPrefix("--") else {
                fputs("Error: --store requires a path argument.\n", stderr); return nil
            }
            storePath = args[i]
        case "--input":
            i += 1
            guard i < args.count, !args[i].hasPrefix("--") else {
                fputs("Error: --input requires a path argument.\n", stderr); return nil
            }
            inputPath = args[i]
        case "--output":
            i += 1
            guard i < args.count, !args[i].hasPrefix("--") else {
                fputs("Error: --output requires a path argument.\n", stderr); return nil
            }
            outputPath = args[i]
        default:
            // TASK-477: reject unrecognized arguments instead of silently ignoring typos.
            fputs("Error: unknown argument '\(args[i])'.\n", stderr); return nil
        }
        i += 1
    }

    // TASK-523: the operation flags are mutually exclusive. Previously several at once silently ran
    // only the first in priority order; reject the ambiguous invocation instead.
    let modeFlags: [(name: String, set: Bool)] = [
        ("--repair-fit-scores", repair),
        ("--verify", verify),
        ("--patch", patch),
        ("--patch-fit-scores", patchFit),
        ("--reclean", reclean),
        ("--backfill-models", backfillModels),
        ("--prune-orphan-fit-scores", pruneOrphanFitScores),
        ("--prune-orphan-attempts", pruneOrphanAttempts),
        ("--recompute-fit-mirrors", recomputeFitMirrors),
        ("--detect-duplicates", detectDuplicates),
        ("--repair-duplicate-job-numbers", repairDuplicateJobNumbers),
        ("--unmark-heuristic-duplicates", unmarkHeuristicDuplicates),
    ]
    let setFlags = modeFlags.filter(\.set).map(\.name)
    // `--output` with no operation flag means migrate; combining it with one is also ambiguous.
    let migrateRequested = outputPath != nil
    if setFlags.count > 1 || (!setFlags.isEmpty && migrateRequested) {
        let names = setFlags + (migrateRequested ? ["--output (migrate)"] : [])
        fputs(
            "Error: choose exactly one operation — these are mutually exclusive: "
                + "\(names.joined(separator: ", ")).\n",
            stderr
        )
        return nil
    }

    if repair { return .repairFitScores(storePath: storePath) }
    if verify { return .verify(inputPath: inputPath, storePath: storePath) }
    if patch { return .patch(inputPath: inputPath, storePath: storePath) }
    if patchFit { return .patchFitScores(inputPath: inputPath, storePath: storePath) }
    if reclean { return .reclean(storePath: storePath) }
    if backfillModels { return .backfillModels(storePath: storePath) }
    if pruneOrphanFitScores { return .pruneOrphanFitScores(storePath: storePath) }
    if pruneOrphanAttempts { return .pruneOrphanAttempts(storePath: storePath) }
    if recomputeFitMirrors { return .recomputeFitMirrors(storePath: storePath) }
    if detectDuplicates { return .detectDuplicates(storePath: storePath) }
    if repairDuplicateJobNumbers { return .repairDuplicateJobNumbers(storePath: storePath) }
    if unmarkHeuristicDuplicates { return .unmarkHeuristicDuplicates(storePath: storePath) }

    guard let out = outputPath else {
        fputs("Error: --output <path> is required.\n", stderr)
        fputs("Usage:\n", stderr)
        fputs("  JobhuntMigrator [--input <path>] --output <path>\n", stderr)
        fputs("  JobhuntMigrator --repair-fit-scores [--store <path>]\n", stderr)
        fputs("  JobhuntMigrator --verify [--input <path>] [--store <path>]\n", stderr)
        fputs("  JobhuntMigrator --patch  [--input <path>] [--store <path>]\n", stderr)
        fputs("  JobhuntMigrator --patch-fit-scores [--input <path>] [--store <path>]\n", stderr)
        fputs("  JobhuntMigrator --reclean [--store <path>]\n", stderr)
        fputs("  JobhuntMigrator --backfill-models [--store <path>]\n", stderr)
        fputs("  JobhuntMigrator --prune-orphan-fit-scores [--store <path>]\n", stderr)
        fputs("  JobhuntMigrator --prune-orphan-attempts [--store <path>]\n", stderr)
        fputs("  JobhuntMigrator --recompute-fit-mirrors [--store <path>]\n", stderr)
        fputs("  JobhuntMigrator --detect-duplicates [--store <path>]\n", stderr)
        fputs("  JobhuntMigrator --unmark-heuristic-duplicates [--store <path>]\n", stderr)
        return nil
    }
    return .migrate(inputPath: inputPath, outputPath: out)
}
