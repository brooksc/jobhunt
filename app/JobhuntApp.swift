import AppKit
import JobhuntCore
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

@main
struct JobhuntApp: App {
    // Non-nil when ModelContainer failed to open — shows recovery UI instead of main window.
    let storeFailure: StoreFailure?

    let modelContainer: ModelContainer?
    let appServices: AppServices?
    let onboardingManager: OnboardingManager?
    let router: Router?
    let platformIntegration: PlatformIntegration?
    let theme = Theme()

    struct StoreFailure {
        let storeURL: URL
        let message: String
    }

    init() {
        let args = CommandLine.arguments
        let isUITest = args.contains("--ui-test-store")
        let shouldSeed = args.contains("--seed-demo-data")
        let fixtureDBPath: String? = {
            guard let idx = args.firstIndex(of: "--fixture-db"), args.index(after: idx) < args.endIndex
            else { return nil }
            return args[args.index(after: idx)]
        }()
        let fixtureOutputPath: String? = {
            guard let idx = args.firstIndex(of: "--seed-fixture-output"),
                  args.index(after: idx) < args.endIndex
            else { return nil }
            return args[args.index(after: idx)]
        }()

        do {
            let container: ModelContainer
            if isUITest {
                // Use a dedicated temp store that cannot touch the user's production database.
                let storeURL = URL(fileURLWithPath: NSTemporaryDirectory())
                    .appendingPathComponent("JobhuntUITest/jobhunt-ui-test.store")
                try? FileManager.default.createDirectory(
                    at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                // Always start fresh so tests see a clean slate.
                let shmURL = storeURL.appendingPathExtension("shm")
                let walURL = storeURL.appendingPathExtension("wal")
                for url in [storeURL, shmURL, walURL] { try? FileManager.default.removeItem(at: url) }
                container = try ModelContainerFactory.test(at: storeURL)
            } else if let fixturePath = fixtureDBPath {
                // Open an isolated copy of a committed fixture database.
                container = try ModelContainerFactory.fixture(copying: URL(fileURLWithPath: fixturePath))
            } else if let outputPath = fixtureOutputPath {
                // Seed a fresh fixture and write it to the given path (used by build-fixture-db.sh).
                let outputURL = URL(fileURLWithPath: outputPath)
                try? FileManager.default.createDirectory(
                    at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                container = try ModelContainerFactory.test(at: outputURL)
            } else {
                container = try ModelContainerFactory.production()
            }

            modelContainer = container
            let services = AppServices(modelContainer: container)
            appServices = services
            let mgr = OnboardingManager(settings: services.settings)
            if isUITest { mgr.isPresented = false }  // Never block tests with the onboarding sheet
            onboardingManager = mgr
            let sharedRouter = Router()
            router = sharedRouter
            let integration = PlatformIntegration(router: sharedRouter, modelContainer: container)
            platformIntegration = integration
            storeFailure = nil
            // TASK-427: demo seeding is only safe in the isolated UI-test store. Passing
            // --seed-demo-data to a normal launch must never seed the production/selected store.
            let allowDemoSeed = LaunchPolicy.allowsDemoSeed(isUITest: isUITest, seedRequested: shouldSeed)
            Task { @MainActor in
                integration.start(queue: services.queueActor)
                if allowDemoSeed {
                    try? await DemoSeeder.seedDemo(into: services.backgroundStore)
                } else if shouldSeed {
                    fputs("Refusing --seed-demo-data without --ui-test-store: demo seeding is only "
                        + "allowed into the isolated UI-test store, not the selected store.\n", stderr)
                }
                if fixtureOutputPath != nil {
                    do {
                        try await FixtureSeeder.seed(into: services.backgroundStore)
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
            storeFailure = StoreFailure(
                storeURL: ModelContainerFactory.productionStoreURL(),
                message: error.localizedDescription
            )
        }
    }

    var body: some Scene {
        WindowGroup {
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
                    .modelContainer(container)
            }
        }
        .defaultSize(width: 1200, height: 750)
        .commands {
            if let r = router, let services = appServices, let container = modelContainer {
                QueueMenuCommands()
                QualityMenuCommands()

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
                    Divider()
                    Button("Settings") { r.navigateToSection(.settings) }
                        .keyboardShortcut("8", modifiers: [.command, .control])
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

                // ⌘⇧E — Export job list fields to CSV (not a full backup; HIG-18)
                CommandGroup(after: .importExport) {
                    Button("Export Job List to CSV…") {
                        Task { @MainActor in
                            let ctx = ModelContext(container)
                            let jobs = (try? ctx.fetch(FetchDescriptor<Job>(
                                sortBy: [SortDescriptor(\Job.createdAt, order: .reverse)]
                            ))) ?? []
                            let csv = ExportService.jobsCSV(jobs: jobs)
                            let panel = NSSavePanel()
                            panel.allowedContentTypes = [.commaSeparatedText]
                            panel.nameFieldStringValue = "jobs.csv"
                            guard panel.runModal() == .OK, let url = panel.url else { return }
                            do {
                                try ExportService.write(csv, to: url)
                            } catch {
                                services.toastStore.show(
                                    "Export failed: \(error.localizedDescription)", isError: true
                                )
                            }
                        }
                    }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                }

                #if !MAS_BUILD
                    CommandGroup(after: .appInfo) {
                        Button("Check for Updates…") {
                            SparkleUpdater.checkForUpdates()
                        }
                    }
                #endif
            }
        }

        // HIG-2: Dedicated Settings scene — opened via ⌘, from the app menu.
        // Only available when the store opened successfully.
        Settings {
            if let services = appServices, let container = modelContainer {
                SettingsView()
                    .environment(services)
                    .environment(theme)
                    .modelContainer(container)
            }
        }
    }
}
