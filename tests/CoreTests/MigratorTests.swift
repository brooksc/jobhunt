import XCTest

/// Tests for the JobhuntMigrator CLI's argument parsing (`tools/migrator/Args.swift`, compiled
/// directly into this target — see Project.swift). Every mode mutates the live SwiftData store, so
/// a misparse runs the wrong destructive operation; these guard the selection rules, not the fixups
/// themselves (those are tested against `BackgroundStore` in their own files).
final class MigratorTests: XCTestCase {
    // MARK: - Arg parsing (TASK-523)

    func testParseArgs_singleOperationFlag_parses() {
        guard case .reclean = parseArgs(["JobhuntMigrator", "--reclean", "--store", "/tmp/s"]) else {
            return XCTFail("a single operation flag should parse to that mode")
        }
    }

    func testParseArgs_twoOperationFlags_rejected() {
        let mode = parseArgs(["JobhuntMigrator", "--reclean", "--repair-duplicate-job-numbers", "--store", "/tmp/s"])
        XCTAssertNil(mode, "combining two mutually-exclusive operation flags must be rejected, not silently run one")
    }

    /// There is no default operation. A bare invocation (or one carrying only `--store`) must print
    /// usage and fail rather than picking something to run against the user's store.
    func testParseArgs_noOperationFlag_rejected() {
        XCTAssertNil(parseArgs(["JobhuntMigrator"]))
        XCTAssertNil(parseArgs(["JobhuntMigrator", "--store", "/tmp/s"]))
    }

    /// The legacy Electron→SwiftData import is gone. Its flags must be rejected as unknown (TASK-477)
    /// rather than silently ignored, so an old command line fails loudly instead of appearing to work.
    func testParseArgs_retiredImportFlags_rejected() {
        let retired = [
            ["JobhuntMigrator", "--output", "/tmp/out.store"],
            ["JobhuntMigrator", "--input", "/tmp/jobhunt.db", "--output", "/tmp/out.store"],
            ["JobhuntMigrator", "--verify"],
            ["JobhuntMigrator", "--patch"],
            ["JobhuntMigrator", "--patch-fit-scores"],
            ["JobhuntMigrator", "--repair-fit-scores"],
            ["JobhuntMigrator", "--reclean", "--output", "/tmp/out.store"]
        ]
        for args in retired {
            XCTAssertNil(parseArgs(args), "must reject: \(args.dropFirst().joined(separator: " "))")
        }
    }

    // MARK: - Arg parsing: --rescore-stale-fit-scores (TASK-711)

    /// The one mode that spends money must not start on the bare flag: unconfirmed means "print the
    /// bill and stop".
    func testParseArgs_rescoreStale_defaultsToUnconfirmed() {
        guard case let .rescoreStaleFitScores(_, confirmed, limit) = parseArgs(
            ["JobhuntMigrator", "--rescore-stale-fit-scores"]
        ) else {
            return XCTFail("--rescore-stale-fit-scores should parse")
        }
        XCTAssertFalse(confirmed)
        XCTAssertNil(limit)
    }

    func testParseArgs_rescoreStale_acceptsConfirmationAndLimit() {
        guard case let .rescoreStaleFitScores(_, confirmed, limit) = parseArgs(
            ["JobhuntMigrator", "--rescore-stale-fit-scores", "--yes", "--limit", "5"]
        ) else {
            return XCTFail("--yes and --limit should parse alongside the mode")
        }
        XCTAssertTrue(confirmed)
        XCTAssertEqual(limit, 5)
    }

    /// `--yes` attached to some other mode would read as a confirmation nothing asked for, and a bad
    /// `--limit` must not silently become "all of them".
    func testParseArgs_rescoreStale_rejectsMisplacedOrMalformedModifiers() {
        let invalid = [
            ["JobhuntMigrator", "--reclean", "--yes"],
            ["JobhuntMigrator", "--reclean", "--limit", "5"],
            ["JobhuntMigrator", "--rescore-stale-fit-scores", "--limit", "0"],
            ["JobhuntMigrator", "--rescore-stale-fit-scores", "--limit", "many"]
        ]
        for args in invalid {
            XCTAssertNil(parseArgs(args), "must reject: \(args.dropFirst().joined(separator: " "))")
        }
    }

    // MARK: - Arg parsing: --merge-job

    func testParseArgs_mergeJob_parsesBothJobNumbers() {
        guard case let .mergeJob(_, from, into) = parseArgs(
            ["JobhuntMigrator", "--merge-job", "--from", "761", "--into", "725"]
        ) else {
            return XCTFail("--merge-job with --from/--into should parse")
        }
        XCTAssertEqual(from, 761)
        XCTAssertEqual(into, 725)
    }

    /// A merge that silently defaulted one side would delete the wrong job — reject every partial form.
    func testParseArgs_mergeJob_rejectsIncompleteOrNonsensicalForms() {
        let invalid = [
            ["JobhuntMigrator", "--merge-job"], // neither side
            ["JobhuntMigrator", "--merge-job", "--from", "761"], // no --into
            ["JobhuntMigrator", "--merge-job", "--into", "725"], // no --from
            ["JobhuntMigrator", "--merge-job", "--from", "725", "--into", "725"], // itself
            ["JobhuntMigrator", "--merge-job", "--from", "abc", "--into", "725"], // not a number
            ["JobhuntMigrator", "--merge-job", "--from", "0", "--into", "725"], // not a job number
            ["JobhuntMigrator", "--from", "761", "--into", "725"] // no operation flag
        ]
        for args in invalid {
            XCTAssertNil(parseArgs(args), "must reject: \(args.dropFirst().joined(separator: " "))")
        }
    }
}
