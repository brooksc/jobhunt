import XCTest
@testable import JobhuntCore

final class LaunchPolicyTests: XCTestCase {
    // TASK-427: demo seeding must be confined to the isolated UI-test store.

    func testDemoSeedAllowedOnlyInUITestMode() {
        XCTAssertTrue(LaunchPolicy.allowsDemoSeed(isUITest: true, seedRequested: true),
                      "UI-test store + seed flag → seed")
    }

    func testDemoSeedRejectedWithoutUITestStore() {
        // The dangerous case: --seed-demo-data on a normal/production launch must NOT seed.
        XCTAssertFalse(LaunchPolicy.allowsDemoSeed(isUITest: false, seedRequested: true),
                       "seed flag without UI-test store must not seed the selected store")
    }

    func testNoSeedWhenFlagAbsent() {
        XCTAssertFalse(LaunchPolicy.allowsDemoSeed(isUITest: true, seedRequested: false))
        XCTAssertFalse(LaunchPolicy.allowsDemoSeed(isUITest: false, seedRequested: false))
    }

    // TASK-423: fixture generation must never overwrite the production store.

    func testFixtureOutputRejectsProductionPath() {
        let prod = "/Users/x/Library/Application Support/Jobhunt/jobhunt.store"
        XCTAssertFalse(LaunchPolicy.isSafeFixtureOutputPath(prod, productionStorePath: prod))
        // Path equivalence is normalized (./ and // collapse).
        XCTAssertFalse(LaunchPolicy.isSafeFixtureOutputPath(
            "/Users/x/Library/Application Support/Jobhunt/./jobhunt.store",
            productionStorePath: prod))
    }

    func testFixtureOutputAllowsOtherPaths() {
        let prod = "/Users/x/Library/Application Support/Jobhunt/jobhunt.store"
        XCTAssertTrue(LaunchPolicy.isSafeFixtureOutputPath(
            "/tmp/jobhunt-test.sqlite", productionStorePath: prod))
        XCTAssertTrue(LaunchPolicy.isSafeFixtureOutputPath(
            "/repo/tests/fixtures/jobhunt-test.sqlite", productionStorePath: prod))
    }
}
