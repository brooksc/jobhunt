import SwiftUI
import SwiftData
import JobhuntCore

@main
struct JobhuntApp: App {
    let modelContainer: ModelContainer
    let appServices: AppServices

    init() {
        do {
            let container = try ModelContainerFactory.production()
            modelContainer = container
            appServices = AppServices(modelContainer: container)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appServices)
        }
        .modelContainer(modelContainer)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
