import Foundation
import JobhuntCore
import JobhuntServer
import SwiftData
import SwiftUI

/// Observable container for app-level services, injected into the SwiftUI environment.
/// Constructed once in JobhuntApp and passed via .environment(appServices).
@Observable
final class AppServices: @unchecked Sendable {
    let jobService: JobService
    let siteService: SiteService
    let resumeService: ResumeService
    let queueActor: QueueActor
    let settings: SettingsStore
    let server: JobhuntServer
    let backgroundStore: BackgroundStore
    let toastStore = ToastStore()
    var serverRunning: Bool = false
    var serverError: String?

    init(modelContainer: ModelContainer) {
        let store = BackgroundStore(modelContainer: modelContainer)
        let context = ModelContext(modelContainer)
        let settingsStore = SettingsStore(modelContext: context)
        let queue = QueueActor(
            store: store,
            isPaused: { await MainActor.run { settingsStore.llmQueuePaused } },
            onSetPaused: { paused in await MainActor.run { settingsStore.llmQueuePaused = paused } },
            readExtractionSettings: { await MainActor.run { settingsStore.extractionSettings() } },
            providerFactory: { LLMProviderFactory.makeProvider(settings: settingsStore) }
        )
        let js = JobService(store: store, queue: queue)
        let ss = SiteService(store: store)
        #if !MAS_BUILD
        // Only generate MCP token for DMG builds where the MCP helper is bundled.
        // MAS sandbox builds exclude the MCP target entirely.
        let mcpToken: String
        do {
            mcpToken = try MCPTokenManager.generateAndWrite()
        } catch {
            NSLog("AppServices: MCP token setup failed — MCP will be unavailable: \(error)")
            mcpToken = ""
        }
        #else
        let mcpToken = ""
        #endif
        let localServer = JobhuntServer(jobService: js, siteService: ss, store: store, mcpToken: mcpToken)
        jobService = js
        siteService = ss
        resumeService = ResumeService(store: store)
        queueActor = queue
        settings = settingsStore
        server = localServer
        backgroundStore = store
        Task { @MainActor [weak self] in
            do {
                try await localServer.start()
                self?.serverRunning = true
            } catch {
                self?.serverError = error.localizedDescription
            }
        }
        Task {
            try? await queue.requeueRunningOnLaunch()
        }

        // Update last-check timestamp when a scheduled availability check completes.
        NotificationCenter.default.addObserver(
            forName: .availabilityCheckCompleted,
            object: nil,
            queue: .main
        ) { notification in
            if let timestamp = notification.userInfo?["timestamp"] as? String {
                settingsStore.set(timestamp, forKey: SettingsKey.availabilityLastAutoCheckAt)
            }
        }

        Task {
            // Run on launch; maybeRunStaleCheck gates on interval internally.
            await AvailabilityChecker.maybeRunStaleCheck(store: store, settings: settingsStore)
        }
    }
}
