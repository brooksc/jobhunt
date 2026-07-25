import AppKit
import JobhuntCore
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Errors raised while resolving a launch mode's store.
enum FixtureOutputError: LocalizedError {
    case refusedProductionPath(String)

    var errorDescription: String? {
        switch self {
        case let .refusedProductionPath(path):
            return "Refusing to seed a fixture to \(path): it resolves to the production store. "
                + "Choose a different --seed-fixture-output path."
        }
    }
}

/// Adds a Window-menu command to reopen the single main window after the user closes it
/// (App Review Guideline 4: a closed main window must be reopenable from a menu). Unconditional so
/// it works even in the store-recovery state. Clicking the Dock icon also reopens the window.
struct ReopenMainWindowCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(after: .singleWindowList) {
            Button("JobHunt Window") { openWindow(id: JobhuntApp.mainWindowID) }
                .keyboardShortcut("0", modifiers: .command)
        }
    }
}

/// App-owned termination coordinator (TASK-554). Replaces the fire-and-forget `willTerminate`
/// observer: `applicationShouldTerminate` defers quit (`.terminateLater`), runs the single shutdown
/// sequence (stop PlatformIntegration → `await AppServices.shutdown()`), then lets the app quit —
/// so teardown ordering is owned by the app lifecycle, not raced against process exit. The
/// `shutdownSequence` closure is also the clear hook where MCP token cleanup (TASK-530) will plug in.
@MainActor
final class AppTerminationCoordinator: NSObject, NSApplicationDelegate {
    /// Set by `JobhuntApp` once the service graph exists.
    var shutdownSequence: (() async -> Void)?
    private var isTerminating = false

    func applicationShouldTerminate(_: NSApplication) -> NSApplication.TerminateReply {
        guard shutdownSequence != nil, !isTerminating else { return .terminateNow }
        isTerminating = true
        Task { @MainActor [self] in
            await shutdownSequence?()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}

@main
struct JobhuntApp: App {
    /// Scene id for the single main window — targeted by `openWindow` from the reopen command.
    static let mainWindowID = "main"

    /// Owns app termination so shutdown is awaited, not fire-and-forget (TASK-554).
    @NSApplicationDelegateAdaptor(AppTerminationCoordinator.self) private var terminationCoordinator

    /// Non-nil when ModelContainer failed to open — shows recovery UI instead of main window.
    let storeFailure: StoreFailure?

    let modelContainer: ModelContainer?
    let appServices: AppServices?
    let onboardingManager: OnboardingManager?
    let router: Router?
    let platformIntegration: PlatformIntegration?
    let theme = Theme()

    // Sparkle auto-updater — DMG (Developer ID) builds only. Created once and held for the app's
    // lifetime so scheduled background update checks run. MAS builds exclude Sparkle entirely.
    // nil in UI-test mode: Sparkle's first-launch "check for updates automatically?" prompt steals
    // focus and blocks UI/screenshot automation.
    #if !MAS_BUILD
        let sparkleUpdater: SparkleUpdaterController? =
            CommandLine.arguments.contains("--ui-test-store") ? nil : SparkleUpdaterController()
    #endif

    struct StoreFailure {
        let storeURL: URL
        let message: String
    }

    /// Activate an already-running instance and exit, so only one process ever opens the production
    /// store. UI-test runs are exempt: `--ui-test-store` opens an isolated temp store, so coexisting
    /// with a normal instance is safe and the suite must not be killed by this guard.
    private static func terminateIfAnotherInstanceIsRunning() {
        guard !CommandLine.arguments.contains("--ui-test-store") else { return }
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        guard let existing = others.first else { return }
        existing.activate()
        // exit(0), not NSApp.terminate: the app isn't running yet (this is `init`), and the
        // termination coordinator would try to shut down a service graph that was never built.
        exit(0)
    }

    init() {
        // Refuse to become a second writer on the production store. SQLite's file locking prevents raw
        // corruption, but SwiftData/CoreData layers its own caches on top and is NOT multi-process-safe:
        // two instances produce stale reads and lost updates. This is reachable in practice — an
        // installed /Applications copy and a build run from DerivedData share one store (the store path
        // is fixed, not keyed by bundle path). Hand off to the instance that's already running.
        Self.terminateIfAnotherInstanceIsRunning()

        do {
            // TASK-426: parse launch arguments into an explicit plan up front. Invalid/incomplete
            // arguments throw (caught below) instead of silently falling back to production.
            let plan = try LaunchPlan.parse(CommandLine.arguments)

            let container = try Self.openStore(for: plan.mode)

            // TASK-425/426: the MCP token is generated by the launch owner (here), gated by mode,
            // and passed into the service graph — construction no longer writes to the machine.
            var mcpToken = ""
            if plan.needsMCPToken {
                #if !MAS_BUILD
                    do {
                        mcpToken = try MCPTokenManager.generateAndWrite()
                    } catch {
                        NSLog("JobhuntApp: MCP token setup failed — MCP will be unavailable: \(error)")
                    }
                #endif
            }

            modelContainer = container
            let services = AppServices(
                modelContainer: container,
                mcpToken: mcpToken,
                pauseQueue: plan.startsQueuePaused
            )
            appServices = services
            // TASK-486: in UI tests, point the LLM at a localhost mock server (started by the test
            // runner) so the AI path runs end-to-end with no API key. Gated to uiTest mode so it can
            // never reconfigure a real user's provider.
            if plan.mode == .uiTest, let mockPort = Self.llmMockPort() {
                services.settings.llmProvider = "lmstudio" // OpenAI-compatible, no key/consent
                services.settings.llmBaseURL = "http://127.0.0.1:\(mockPort)"
                services.settings.setModelForProvider("mock-model", provider: "lmstudio")
                services.settings.llmQueuePaused = false // let the queue process against the mock
            }
            let mgr = OnboardingManager(settings: services.settings)
            if plan.mode == .uiTest { mgr.isPresented = false } // Never block tests with onboarding
            onboardingManager = mgr
            let sharedRouter = Router()
            router = sharedRouter
            let integration = PlatformIntegration(router: sharedRouter, modelContainer: container)
            platformIntegration = integration
            storeFailure = nil

            Task { @MainActor in
                // Interactive modes start runtime services AND platform integration (which requests
                // notification auth, registers focus/deep-link observers, applies window policy).
                // Fixture generation does none of this — it only seeds and exits (TASK-419/425).
                if plan.runsRuntimeServices {
                    integration.start(queue: services.queueActor)
                    services.startRuntime()
                }
                if plan.allowsDemoSeed {
                    try? await DemoSeeder.seedDemo(into: services.backgroundStore)
                } else if plan.seedDemoDataRequested {
                    // TASK-427: a seed flag outside UI-test mode must not touch the selected store.
                    fputs(
                        "Refusing --seed-demo-data without --ui-test-store: demo seeding is only "
                            + "allowed into the isolated UI-test store, not the selected store.\n",
                        stderr
                    )
                }
                if case .fixtureGenerate = plan.mode {
                    do {
                        // TASK-423: fail (don't silently no-op) if the target already has data — a
                        // fixture seeded on top of existing rows would be stale/incomplete.
                        let existing = try await services.backgroundStore.fetch(FetchDescriptor<Job>())
                        guard existing.isEmpty else {
                            fputs(
                                "Fixture output target already contains \(existing.count) job(s) — "
                                    + "refusing to seed onto a non-empty store. Remove it first.\n",
                                stderr
                            )
                            exit(1)
                        }
                        try await FixtureSeeder.seed(into: services.backgroundStore, skipIfPopulated: false)
                        exit(0)
                    } catch {
                        fputs("FixtureSeeder failed: \(error)\n", stderr)
                        exit(1)
                    }
                }
            }
        } catch {
            modelContainer = nil
            appServices = nil
            onboardingManager = nil
            router = nil
            platformIntegration = nil
            // Clear message for launch-argument errors; localizedDescription otherwise.
            let message = (error as? LaunchArgumentError)?.description ?? error.localizedDescription
            storeFailure = StoreFailure(
                storeURL: ModelContainerFactory.productionStoreURL(),
                message: message
            )
        }
    }

    /// Parse `--llm-mock-port <port>` (TASK-486), used only in UI tests to point the app at a
    /// localhost mock LLM server. Returns nil when absent/invalid.
    private static func llmMockPort() -> Int? {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: "--llm-mock-port"), index + 1 < args.count else { return nil }
        return Int(args[index + 1])
    }

    /// Opens the ModelContainer for the given launch mode. Store-selection policy lives here, one
    /// branch per mode, instead of interleaved conditionals in `init` (TASK-426).
    private static func openStore(for mode: LaunchMode) throws -> ModelContainer {
        switch mode {
        case .uiTest:
            // Dedicated temp store that cannot touch the user's production database. Fail closed if
            // the clean-slate cleanup can't complete, so a test never opens stale data (TASK-424).
            let storeURL = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("JobhuntUITest/jobhunt-ui-test.store")
            return try ModelContainerFactory.freshTestStore(at: storeURL)
        case let .fixtureRead(path):
            // Open an isolated copy of a committed fixture database.
            return try ModelContainerFactory.fixture(copying: URL(fileURLWithPath: path))
        case let .fixtureGenerate(outputPath):
            // Seed a fresh fixture and write it to the given path (used by build-fixture-db.sh).
            // TASK-423: never let fixture generation overwrite the user's production store.
            guard LaunchPolicy.isSafeFixtureOutputPath(
                outputPath,
                productionStorePath: ModelContainerFactory.productionStoreURL().path
            ) else {
                throw FixtureOutputError.refusedProductionPath(outputPath)
            }
            let outputURL = URL(fileURLWithPath: outputPath)
            // Fail closed if the output directory can't be created (TASK-424).
            try FileManager.default.createDirectory(
                at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            return try ModelContainerFactory.test(at: outputURL)
        case .production:
            return try ModelContainerFactory.production()
        }
    }

    var body: some Scene {
        Window("JobHunt", id: Self.mainWindowID) {
            if let failure = storeFailure {
                StoreRecoveryView(failure: failure)
            } else if let container = modelContainer,
                      let services = appServices,
                      let mgr = onboardingManager,
                      let r = router,
                      let integration = platformIntegration {
                ContentView(router: r, theme: theme)
                    .environment(services)
                    .sheet(isPresented: Binding(
                        get: { mgr.isPresented },
                        set: { mgr.isPresented = $0 }
                    )) {
                        OnboardingView(
                            onboardingManager: mgr,
                            settings: services.settings,
                            modelContainer: container,
                            resumeService: services.resumeService
                        )
                    }
                    .onOpenURL { url in
                        integration.handleDeepLink(url)
                    }
                    // App-owned shutdown on termination (TASK-430/554): hand the teardown sequence to
                    // the NSApplicationDelegate so quit AWAITS server stop + runtime-task cancellation
                    // (via AppServices.shutdown) instead of racing process exit.
                    .onAppear {
                        terminationCoordinator.shutdownSequence = {
                            integration.stop()
                            await services.shutdown()
                            // Remove the transient MCP token now that the server (which accepts it) is
                            // stopped — only if this launch generated one (TASK-530).
                            if services.mcpTokenWasGenerated {
                                MCPTokenManager.delete()
                            }
                        }
                    }
                    // TASK-464: Settings → Debug "Reopen Onboarding".
                    .onReceive(NotificationCenter.default.publisher(for: .reopenOnboarding)) { _ in
                        mgr.reopen()
                    }
                    .modelContainer(container)
            }
        }
        .defaultSize(width: 1200, height: 750)
        .commands {
            ReopenMainWindowCommands()
            if let r = router {
                QueueMenuCommands()
                QualityMenuCommands()
                JobMenuCommands()

                // Go menu — jump to any section via ⌃⌘<n>. A standard macOS navigation
                // affordance, and the deterministic path UI tests use (synthesized clicks on
                // the List(.sidebar) rows are unreliable under XCUITest on macOS 26).
                CommandMenu("Go") {
                    Button("Dashboard") { r.navigateToSection(.dashboard) }
                        .keyboardShortcut("1", modifiers: [.command, .control])
                    Button("Needs Action") { r.navigateToSection(.needsAction) }
                        .keyboardShortcut("2", modifiers: [.command, .control])
                    Button("Jobs") {
                        r.activeSavedSearchID = nil
                        r.sidebarJobFilter = nil
                        r.navigateToSection(.jobs)
                    }
                    .keyboardShortcut("3", modifiers: [.command, .control])
                    Button("Sites") { r.navigateToSection(.sites) }
                        .keyboardShortcut("4", modifiers: [.command, .control])
                    Button("Duplicates") { r.navigateToSection(.duplicates) }
                        .keyboardShortcut("5", modifiers: [.command, .control])
                    Button("LLM Queue") { r.navigateToSection(.llmQueue) }
                        .keyboardShortcut("6", modifiers: [.command, .control])
                    Button("Data Quality") { r.navigateToSection(.dataQuality) }
                        .keyboardShortcut("7", modifiers: [.command, .control])
                    Button("Resumes") { r.navigateToSection(.resumes) }
                        .keyboardShortcut("8", modifiers: [.command, .control])

                    Divider()
                    // ⌘1–⌘6 — jump to the Jobs list with a smart-folder filter applied (TASK-499).
                    // Each clears any active saved search and sets the sidebar filter, so the list and
                    // the sidebar selection stay in sync.
                    ForEach(filterShortcutOrder, id: \.title) { entry in
                        Button("Jobs: \(entry.title)") {
                            r.activeSavedSearchID = nil
                            r.sidebarJobFilter = entry.status
                            r.navigateToSection(.jobs)
                        }
                        .keyboardShortcut(entry.key, modifiers: .command)
                    }
                }

                // ⌘N — Add Job (HIG-7)
                CommandGroup(replacing: .newItem) {
                    Button("Add Job…") {
                        r.navigateToSection(.jobs)
                        r.showAddJobSheet = true
                    }
                    .keyboardShortcut("n", modifiers: .command)
                }

                // ⌘K — Jump to Jobs / focus search
                CommandGroup(after: .newItem) {
                    Button("Search Jobs") {
                        r.navigateToSection(.jobs)
                        r.focusSearch = true
                    }
                    .keyboardShortcut("k", modifiers: .command)
                }

                // ⌘F — standard macOS Find, placed in the Edit menu. Focuses the Jobs search
                // field (an alias for ⌘K, which stays for muscle memory). HIG-3.8/10.2.
                CommandGroup(after: .textEditing) {
                    Button("Find") {
                        r.navigateToSection(.jobs)
                        r.focusSearch = true
                    }
                    .keyboardShortcut("f", modifiers: .command)
                }

                // ⌘⇧E — Export the current filtered Jobs view to CSV (not a full backup; HIG-18).
                // Single export path: the Jobs screen owns it so the menu and the in-list
                // command always export exactly what the user is looking at.
                CommandGroup(after: .importExport) {
                    Button("Export Current List to CSV…") {
                        r.navigateToSection(.jobs)
                        r.exportJobsRequested = true
                    }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                }

                #if !MAS_BUILD
                    if let sparkleUpdater {
                        CommandGroup(after: .appInfo) {
                            CheckForUpdatesCommand(updater: sparkleUpdater)
                        }
                    }
                #endif

                // HIG: Help belongs in the menu bar's Help menu, not the sidebar. Replaces the
                // empty system default ("Help isn't available") with a link to the online docs,
                // which stay current independent of the app build.
                CommandGroup(replacing: .help) {
                    // Keyboard Shortcuts overlay (TASK-499). Bare `?` also opens it (via the key
                    // monitor); the menu item is the discoverable entry point. It takes over the
                    // former ⌘? binding so online Help no longer conflicts with it.
                    Button("Keyboard Shortcuts") { r.showKeyboardShortcuts = true }
                        .keyboardShortcut("?", modifiers: .command)

                    Divider()

                    Button("JobHunt Help") {
                        if let url = URL(string: "https://jobhunt-app.com/help/") {
                            NSWorkspace.shared.open(url)
                        }
                    }

                    Button("Report an Issue…") {
                        if let url = URL(string: "https://jobhunt-app.com/issues/") {
                            NSWorkspace.shared.open(url)
                        }
                    }

                    // Diagnostics live at the point of reporting, not buried in the Debug tab most
                    // users never open. Copies the same redacted blob and confirms with a toast.
                    Button("Copy Diagnostics") {
                        if let services = appServices {
                            Task { @MainActor in
                                let text = await services.diagnosticsText()
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(text, forType: .string)
                                services.toastStore.show("Diagnostics copied — paste it into your report")
                            }
                        }
                    }
                }
            }
        }

        // HIG-2: Dedicated Settings scene — opened via ⌘, from the app menu.
        // Only available when the store opened successfully.
        Settings {
            if let services = appServices, let container = modelContainer, let r = router {
                SettingsView()
                    .environment(services)
                    .environment(theme)
                    .environment(r)
                    .modelContainer(container)
            }
        }
    }
}
