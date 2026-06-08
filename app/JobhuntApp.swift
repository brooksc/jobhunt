import SwiftUI
import SwiftData
import JobhuntCore

@main
struct JobhuntApp: App {
    let modelContainer: ModelContainer
    let appServices: AppServices
    let onboardingManager: OnboardingManager

    init() {
        do {
            let container = try ModelContainerFactory.production()
            modelContainer = container
            let services = AppServices(modelContainer: container)
            appServices = services
            onboardingManager = OnboardingManager(settings: services.settings)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
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
        }
        .modelContainer(modelContainer)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
