import XCTest
@testable import JobhuntCore

final class LaunchModeTests: XCTestCase {
    // MARK: - Parsing (TASK-426 AC#1/#3/#5)

    func testNoArgsIsProduction() throws {
        let plan = try LaunchPlan.parse(["/path/to/Jobhunt"])
        XCTAssertEqual(plan.mode, .production)
        XCTAssertFalse(plan.seedDemoDataRequested)
    }

    func testUITestStore() throws {
        let plan = try LaunchPlan.parse(["app", "--ui-test-store"])
        XCTAssertEqual(plan.mode, .uiTest)
        XCTAssertTrue(plan.startsQueuePaused)
    }

    func testFixtureReadParsesPath() throws {
        let plan = try LaunchPlan.parse(["app", "--fixture-db", "/tmp/fix.store"])
        XCTAssertEqual(plan.mode, .fixtureRead(path: "/tmp/fix.store"))
    }

    func testFixtureGenerateParsesPath() throws {
        let plan = try LaunchPlan.parse(["app", "--seed-fixture-output", "/tmp/out.store"])
        XCTAssertEqual(plan.mode, .fixtureGenerate(outputPath: "/tmp/out.store"))
    }

    func testSeedDemoDataFlagCaptured() throws {
        let plan = try LaunchPlan.parse(["app", "--ui-test-store", "--seed-demo-data"])
        XCTAssertTrue(plan.seedDemoDataRequested)
    }

    // MARK: - Invalid arguments fail instead of falling back to production (AC#3)

    func testMissingFixtureDBValueThrows() {
        XCTAssertThrowsError(try LaunchPlan.parse(["app", "--fixture-db"])) { error in
            XCTAssertEqual(error as? LaunchArgumentError, .missingValue(flag: "--fixture-db"))
        }
    }

    func testFixtureDBFollowedByFlagThrows() {
        // "--fixture-db --seed-demo-data" — the next token is a flag, not a path.
        XCTAssertThrowsError(try LaunchPlan.parse(["app", "--fixture-db", "--seed-demo-data"])) { error in
            XCTAssertEqual(error as? LaunchArgumentError, .missingValue(flag: "--fixture-db"))
        }
    }

    func testConflictingModesThrows() {
        XCTAssertThrowsError(try LaunchPlan.parse(["app", "--ui-test-store", "--fixture-db", "/tmp/x"])) { error in
            switch error {
            case LaunchArgumentError.conflictingModes(_):
                break
            default:
                XCTFail("expected conflictingModes, got \(error)")
            }
        }
    }

    // MARK: - Mode → startup plan (AC#2/#5)

    func testFixtureGenerateOptsOutOfRuntimeServicesAndToken() throws {
        let plan = try LaunchPlan.parse(["app", "--seed-fixture-output", "/tmp/out.store"])
        XCTAssertFalse(plan.runsRuntimeServices, "Fixture generation must not start the server etc.")
        XCTAssertFalse(plan.needsMCPToken)
        XCTAssertFalse(plan.startsQueuePaused)
    }

    func testInteractiveModesRunRuntimeServices() throws {
        for plan in [
            try LaunchPlan.parse(["app"]),
            try LaunchPlan.parse(["app", "--ui-test-store"]),
            try LaunchPlan.parse(["app", "--fixture-db", "/tmp/x.store"]),
        ] {
            XCTAssertTrue(plan.runsRuntimeServices)
            XCTAssertTrue(plan.needsMCPToken)
        }
    }

    func testAllowsDemoSeedOnlyInUITest() throws {
        XCTAssertTrue(try LaunchPlan.parse(["app", "--ui-test-store", "--seed-demo-data"]).allowsDemoSeed)
        // Demo seed flag without UI-test store (production) must NOT allow seeding.
        XCTAssertFalse(try LaunchPlan.parse(["app", "--seed-demo-data"]).allowsDemoSeed)
    }
}
