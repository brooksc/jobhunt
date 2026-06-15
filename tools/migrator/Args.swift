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
}

func parseArgs() -> Mode? {
    let defaultStorePath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Jobhunt/jobhunt.store")
        .path
    let defaultInputPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Jobhunt/jobhunt.db")
        .path

    var repair = false
    var verify = false
    var patch  = false
    var patchFit = false
    var reclean = false
    var backfillModels = false
    var storePath = defaultStorePath
    var inputPath = defaultInputPath
    var outputPath: String? = nil

    var i = 1
    let args = CommandLine.arguments
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
        case "--store":
            i += 1
            if i < args.count { storePath = args[i] }
        case "--input":
            i += 1
            if i < args.count { inputPath = args[i] }
        case "--output":
            i += 1
            if i < args.count { outputPath = args[i] }
        default:
            break
        }
        i += 1
    }

    if repair   { return .repairFitScores(storePath: storePath) }
    if verify   { return .verify(inputPath: inputPath, storePath: storePath) }
    if patch    { return .patch(inputPath: inputPath, storePath: storePath) }
    if patchFit { return .patchFitScores(inputPath: inputPath, storePath: storePath) }
    if reclean  { return .reclean(storePath: storePath) }
    if backfillModels { return .backfillModels(storePath: storePath) }

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
        return nil
    }
    return .migrate(inputPath: inputPath, outputPath: out)
}
