import SwiftUI
import SwiftData
import JobhuntCore

@main
struct JobhuntApp: App {
    let modelContainer: ModelContainer
    let backgroundStore: BackgroundStore
    let settingsStore: SettingsStore
    let queueActor: QueueActor

    init() {
        do {
            let container = try ModelContainerFactory.production()
            modelContainer = container
            let store = BackgroundStore(modelContainer: container)
            backgroundStore = store
            let settings = SettingsStore(modelContext: container.mainContext)
            settingsStore = settings
            queueActor = QueueActor(
                store: store,
                settings: settings,
                providerFactory: { LLMProviderFactory.makeProvider(settings: settings) }
            )
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView(queueActor: queueActor, settings: settingsStore)
        }
        .modelContainer(modelContainer)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
