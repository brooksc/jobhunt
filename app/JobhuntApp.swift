import JobhuntCore
import SwiftData
import SwiftUI

@main
struct JobhuntApp: App {
    let modelContainer: ModelContainer
    let appServices: AppServices
    let onboardingManager: OnboardingManager
    let router: Router
    let platformIntegration: PlatformIntegration
    let theme = Theme()

    init() {
        do {
            let container = try ModelContainerFactory.production()
            modelContainer = container
            let services = AppServices(modelContainer: container)
            appServices = services
            onboardingManager = OnboardingManager(settings: services.settings)
            let sharedRouter = Router()
            router = sharedRouter
            let integration = PlatformIntegration(router: sharedRouter, modelContainer: container)
            platformIntegration = integration
            Task { @MainActor in
                integration.start(queue: services.queueActor)
            }
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView(router: router, theme: theme)
                .environment(appServices)
                .sheet(isPresented: Binding(
                    get: { onboardingManager.isPresented },
                    set: { onboardingManager.isPresented = $0 }
                )) {
                    OnboardingView(
                        onboardingManager: onboardingManager,
                        settings: appServices.settings,
                        modelContainer: modelContainer
                    )
                }
                .onOpenURL { url in
                    platformIntegration.handleDeepLink(url)
                }
        }
        .defaultSize(width: 1200, height: 750)
        .modelContainer(modelContainer)
        .commands {
            // ⌘N — Add Job (HIG-7)
            CommandGroup(replacing: .newItem) {
                Button("Add Job…") {
                    router.navigateToSection(.jobs)
                    router.showAddJobSheet = true
                }
                .keyboardShortcut("n", modifiers: .command)
            }

            // ⌘⇧E — Export CSV (HIG-18)
            CommandGroup(after: .importExport) {
                Button("Export Jobs to CSV…") {
                    router.triggerExport = true
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

        // HIG-2: Dedicated Settings scene — opened via ⌘, from the app menu
        Settings {
            SettingsView()
                .environment(appServices)
                .environment(theme)
                .modelContainer(modelContainer)
        }
    }
}
