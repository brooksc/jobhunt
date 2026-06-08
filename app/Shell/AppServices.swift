import Foundation
import SwiftData
import JobhuntCore

/// Observable container for app-level services, injected into the SwiftUI environment.
/// Constructed once in JobhuntApp and passed via .environment(appServices).
@Observable
final class AppServices: @unchecked Sendable {
    let jobService: JobService
    let siteService: SiteService

    init(modelContainer: ModelContainer) {
        let store = BackgroundStore(modelContainer: modelContainer)
        let context = ModelContext(modelContainer)
        let settings = SettingsStore(modelContext: context)
        let queue = QueueActor(
            store: store,
            settings: settings,
            providerFactory: { LLMProviderFactory.makeProvider(settings: settings) }
        )
        self.jobService = JobService(store: store, queue: queue)
        self.siteService = SiteService(store: store)
    }
}
