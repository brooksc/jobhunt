import SwiftUI
import SwiftData
import JobhuntCore

struct ContentView: View {
    @State private var router = Router()
    @State private var theme = Theme()
    @Environment(AppServices.self) private var appServices

    @Query private var sites: [Site]

    private var selectedSite: Site? {
        guard let id = router.selectedSiteID else { return nil }
        return sites.first { $0.id == id }
    }

    var body: some View {
        NavigationSplitView {
            Sidebar(router: router, theme: theme)
        } content: {
            contentView(for: router.selectedSection)
        } detail: {
            detailView(for: router.selectedSection)
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
            SitesView(siteService: appServices.siteService)
        case .duplicates:
            DuplicatesView()
        case .settings:
            Text("Settings coming soon")
                .foregroundStyle(.secondary)
        case .help:
            Text("Help coming soon")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    func detailView(for section: SidebarSection) -> some View {
        switch section {
        case .sites:
            if let site = selectedSite {
                SiteDetailView(site: site, siteService: appServices.siteService)
            } else {
                ContentUnavailableView(
                    "No Site Selected",
                    systemImage: "globe",
                    description: Text("Select a site to view details.")
                )
            }
        default:
            JobDetailPlaceholder()
        }
    }
}

// Preview requires a real ModelContainer (for AppServices) so is omitted here.
