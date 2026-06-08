import SwiftUI
import JobhuntCore

struct ContentView: View {
    let queueActor: QueueActor
    let settings: SettingsStore

    @State private var router = Router()
    @State private var theme = Theme()

    var body: some View {
        NavigationSplitView {
            Sidebar(router: router, theme: theme)
        } content: {
            contentView(for: router.selectedSection)
        } detail: {
            Text("Select a job")
                .foregroundStyle(.secondary)
        }
        .environment(router)
        .environment(theme)
        .preferredColorScheme(
            theme.colorSchemePreference == .auto ? nil :
                theme.colorSchemePreference == .dark ? .dark : .light
        )
    }

    @ViewBuilder
    func contentView(for section: SidebarSection) -> some View {
        switch section {
        case .jobs:
            Text("Jobs screen coming soon")
                .foregroundStyle(.secondary)
        case .dashboard:
            Text("Dashboard coming soon")
                .foregroundStyle(.secondary)
        case .dataQuality:
            Text("Data Quality coming soon")
                .foregroundStyle(.secondary)
        case .needsAction:
            Text("Needs Action coming soon")
                .foregroundStyle(.secondary)
        case .llmQueue:
            LLMQueueView(queueActor: queueActor, settings: settings)
        case .sites:
            Text("Sites coming soon")
                .foregroundStyle(.secondary)
        case .duplicates:
            Text("Duplicates coming soon")
                .foregroundStyle(.secondary)
        case .settings:
            Text("Settings coming soon")
                .foregroundStyle(.secondary)
        case .help:
            Text("Help coming soon")
                .foregroundStyle(.secondary)
        }
    }
}
