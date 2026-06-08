import SwiftUI
import SwiftData
import JobhuntCore

@main
struct JobhuntApp: App {
    let modelContainer: ModelContainer
    let siteService: SiteService

    init() {
        do {
            let container = try ModelContainerFactory.production()
            modelContainer = container
            let store = BackgroundStore(modelContainer: container)
            siteService = SiteService(store: store)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView(siteService: siteService)
        }
        .modelContainer(modelContainer)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
