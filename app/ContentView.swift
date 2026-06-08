import AppKit
import JobhuntCore
import SwiftData
import SwiftUI

struct ContentView: View {
    var router: Router
    @State private var theme = Theme()
    @Environment(AppServices.self) private var appServices

    @Query private var sites: [Site]
    @Query(filter: #Predicate<Job> { $0.unread == true }) private var unreadJobs: [Job]

    private var selectedSite: Site? {
        guard let id = router.selectedSiteID else { return nil }
        return sites.first { $0.id == id }
    }

    var body: some View {
        NavigationSplitView {
            Sidebar(router: router, theme: theme)
        } content: {
            contentView(for: router.selectedSection)
                .navigationSplitViewColumnWidth(min: 550, ideal: 700)
        } detail: {
            detailView(for: router.selectedSection)
        }
        .environment(router)
        .environment(theme)
        .preferredColorScheme(
            theme.colorSchemePreference == .auto ? nil :
                theme.colorSchemePreference == .dark ? .dark : .light
        )
        .background(
            DockBadgeUpdater(unreadCount: unreadJobs.count)
                .frame(width: 0, height: 0)
        )
        .onAppear {
            guard let window = NSApp.mainWindow else { return }
            window.minSize = NSSize(width: 900, height: 600)
            guard window.frame.width < 1200 || window.frame.height < 750 else { return }
            let newW = max(window.frame.width, 1200)
            let newH = max(window.frame.height, 750)
            let origin = window.frame.origin
            window.setFrame(NSRect(x: origin.x, y: origin.y, width: newW, height: newH), display: true)
        }
    }

    @ViewBuilder
    func contentView(for section: SidebarSection) -> some View {
        switch section {
        case .jobs:
            JobsView()
        case .dashboard:
            DashboardView()
        case .dataQuality:
            DataQualityView()
        case .needsAction:
            NeedsActionView()
        case .llmQueue:
            LLMQueueView(queueActor: appServices.queueActor, settings: appServices.settings)
        case .sites:
            SitesView(siteService: appServices.siteService)
        case .duplicates:
            DuplicatesView()
        case .settings:
            SettingsView()
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
