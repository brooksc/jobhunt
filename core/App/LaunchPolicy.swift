import Foundation

/// Pure, testable launch-time policy decisions, kept out of the @main App initializer so they can
/// be unit-tested without launching the app.
public enum LaunchPolicy {
    /// Whether demo data may be seeded for this launch.
    ///
    /// Demo seeding must only ever touch the isolated UI-test store — never the production (or any
    /// other selected) store. `--seed-demo-data` is a test-only argument; passing it to a normal
    /// launch must NOT mutate the user's real data. Returns true only when both the seed flag and
    /// the UI-test store mode are present.
    public static func allowsDemoSeed(isUITest: Bool, seedRequested: Bool) -> Bool {
        seedRequested && isUITest
    }
}
