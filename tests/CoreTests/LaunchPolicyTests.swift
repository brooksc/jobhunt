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
}
