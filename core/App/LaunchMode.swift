import Foundation

/// Which store/launch mode the app was started in. Parsed from launch arguments once, up front,
/// so store selection, seeding, MCP-token, and runtime-service decisions are explicit per mode
/// rather than interleaved conditionals in the App initializer (TASK-426).
public enum LaunchMode: Equatable {
    /// Normal launch against the user's production store.
    case production
    /// UI-test launch against an isolated temp store (`--ui-test-store`).
    case uiTest
    /// Open an isolated copy of a committed fixture database (`--fixture-db <path>`).
    case fixtureRead(path: String)
    /// Seed a fresh fixture store and write it out, then exit (`--seed-fixture-output <path>`).
    case fixtureGenerate(outputPath: String)
}

/// The fully-resolved launch plan: the mode plus the flags that modify startup behavior.
public struct LaunchPlan: Equatable {
    public let mode: LaunchMode
    /// Whether `--seed-demo-data` was passed (only honored in a safe mode — see `allowsDemoSeed`).
    public let seedDemoDataRequested: Bool
    /// `--run-queue`: start the isolated-store instance with the LLM queue RUNNING.
    ///
    /// UI tests need the opposite — seeded `.pending` rows must keep their state to be asserted on —
    /// so the isolated store defaults to paused. A demo or a screen recording wants the pipeline to
    /// actually run. Opt-in, so no existing test changes behaviour.
    public let runQueueRequested: Bool

    public init(mode: LaunchMode, seedDemoDataRequested: Bool, runQueueRequested: Bool = false) {
        self.mode = mode
        self.seedDemoDataRequested = seedDemoDataRequested
        self.runQueueRequested = runQueueRequested
    }

    /// Runtime services (HTTP server, queue recovery, availability checks, launch observers) run
    /// for every interactive mode but NOT for fixture generation, which only seeds and exits — so
    /// generating a fixture never starts a server or touches user-machine state.
    public var runsRuntimeServices: Bool {
        switch mode {
        case .production, .uiTest, .fixtureRead: return true
        case .fixtureGenerate: return false
        }
    }

    /// The MCP token is only needed when the HTTP server runs.
    public var needsMCPToken: Bool {
        runsRuntimeServices
    }

    /// The LLM queue starts paused in UI-test mode so seeded `.pending` jobs keep their state.
    ///
    /// **Not** when demo data was requested. Demo mode shares the isolated store with UI tests, but
    /// the two want opposite things: a test asserts on rows that must stay `.pending`, while a demo
    /// exists to show extraction and scoring actually happening. Conflating them meant every demo
    /// launch came up paused, every captured job sat queued, and — until the resume path was fixed —
    /// there was no working way to start it.
    public var startsQueuePaused: Bool {
        mode == .uiTest && !runQueueRequested
    }

    /// Demo seeding is confined to the UI-test store (TASK-427).
    public var allowsDemoSeed: Bool {
        LaunchPolicy.allowsDemoSeed(isUITest: mode == .uiTest, seedRequested: seedDemoDataRequested)
    }
}

public enum LaunchArgumentError: Error, Equatable, CustomStringConvertible {
    /// A flag that requires a following value was passed without one.
    case missingValue(flag: String)
    /// More than one mutually-exclusive store-mode flag was passed.
    case conflictingModes([String])

    public var description: String {
        switch self {
        case let .missingValue(flag):
            return "Launch argument \(flag) requires a value (e.g. \(flag) /path/to/store)."
        case let .conflictingModes(flags):
            return "Conflicting launch mode arguments: \(flags.joined(separator: ", ")). Pass at most one."
        }
    }
}

public extension LaunchPlan {
    /// Parse launch arguments into a plan. Throws on invalid/incomplete arguments rather than
    /// silently falling back to production (TASK-426 AC#3).
    static func parse(_ args: [String]) throws -> LaunchPlan {
        let seed = args.contains("--seed-demo-data")
        let runQueue = args.contains("--run-queue")

        let isUITest = args.contains("--ui-test-store")
        let fixtureReadPath = try valueAfter("--fixture-db", in: args)
        let fixtureGeneratePath = try valueAfter("--seed-fixture-output", in: args)

        // Detect conflicting mode selections.
        var selected: [String] = []
        if isUITest { selected.append("--ui-test-store") }
        if fixtureReadPath != nil { selected.append("--fixture-db") }
        if fixtureGeneratePath != nil { selected.append("--seed-fixture-output") }
        if selected.count > 1 { throw LaunchArgumentError.conflictingModes(selected) }

        let mode: LaunchMode
        if isUITest {
            mode = .uiTest
        } else if let path = fixtureReadPath {
            mode = .fixtureRead(path: path)
        } else if let path = fixtureGeneratePath {
            mode = .fixtureGenerate(outputPath: path)
        } else {
            mode = .production
        }
        return LaunchPlan(mode: mode, seedDemoDataRequested: seed, runQueueRequested: runQueue)
    }

    /// Returns the value following `flag`, or nil if the flag is absent. Throws if the flag is
    /// present but has no following value.
    private static func valueAfter(_ flag: String, in args: [String]) throws -> String? {
        guard let idx = args.firstIndex(of: flag) else { return nil }
        let valueIdx = args.index(after: idx)
        guard valueIdx < args.endIndex else { throw LaunchArgumentError.missingValue(flag: flag) }
        let value = args[valueIdx]
        // A following flag (starts with "--") is not a value.
        guard !value.hasPrefix("--") else { throw LaunchArgumentError.missingValue(flag: flag) }
        return value
    }
}
