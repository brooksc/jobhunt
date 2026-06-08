import SwiftUI

struct ContentView: View {
    @State private var router = Router()
    @State private var theme = Theme()
    @Environment(AppServices.self) private var appServices

    var body: some View {
        NavigationSplitView {
            Sidebar(router: router, theme: theme)
        } content: {
            contentView(for: router.selectedSection)
        } detail: {
            JobDetailPlaceholder()
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
            JobsView()
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
            Text("LLM Queue coming soon")
                .foregroundStyle(.secondary)
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

// Preview requires a real ModelContainer (for AppServices) so is omitted here.
