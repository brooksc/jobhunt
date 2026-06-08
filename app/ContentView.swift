import AppKit
import JobhuntCore
import SwiftData
import SwiftUI

struct ContentView: View {
    var router: Router
    @State private var theme = Theme()
    @State private var columnVisibility: NavigationSplitViewVisibility = .doubleColumn
    @Environment(AppServices.self) private var appServices

    @Query(filter: #Predicate<Job> { $0.unread == true }) private var unreadJobs: [Job]

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            Sidebar(router: router, theme: theme)
                .navigationSplitViewColumnWidth(min: 170, ideal: 200)
        } detail: {
            sectionView(for: router.selectedSection)
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
    private func sectionView(for section: SidebarSection) -> some View {
        switch section {
        case .jobs:
            JobsPaneView()
        case .dashboard:
            DashboardView()
        case .dataQuality:
            DataQualityView()
        case .needsAction:
            NeedsActionView()
        case .llmQueue:
            LLMQueueView(queueActor: appServices.queueActor, settings: appServices.settings)
        case .sites:
            SitesPaneView(siteService: appServices.siteService)
        case .duplicates:
            DuplicatesView()
        case .settings:
            SettingsView()
        case .help:
            HelpView()
        }
    }
}

// MARK: - Jobs pane (list + optional detail split)

private struct JobsPaneView: View {
    @Environment(Router.self) private var router

    var body: some View {
        HSplitView {
            JobsView()
                .frame(minWidth: 400, idealWidth: 550)
            if let jobID = router.selectedJobID {
                JobDetailWrapper(jobID: jobID)
                    .frame(minWidth: 350)
            }
        }
    }
}

// MARK: - Sites pane (list + detail split)

private struct SitesPaneView: View {
    let siteService: SiteService
    @Environment(Router.self) private var router
    @Query private var sites: [Site]

    private var selectedSite: Site? {
        guard let id = router.selectedSiteID else { return nil }
        return sites.first { $0.id == id }
    }

    var body: some View {
        HSplitView {
            SitesView(siteService: siteService)
                .frame(minWidth: 250, idealWidth: 350)
            Group {
                if let site = selectedSite {
                    SiteDetailView(site: site, siteService: siteService)
                } else {
                    ContentUnavailableView(
                        "No Site Selected",
                        systemImage: "globe",
                        description: Text("Select a site to view details.")
                    )
                }
            }
            .frame(minWidth: 350)
        }
    }
}

// MARK: - Job detail query wrapper

private struct JobDetailWrapper: View {
    let jobID: String
    @Query private var jobs: [Job]

    init(jobID: String) {
        self.jobID = jobID
        _jobs = Query(filter: #Predicate { $0.id == jobID })
    }

    var body: some View {
        if let job = jobs.first {
            JobDetailView(job: job)
        }
    }
}

// Preview requires a real ModelContainer (for AppServices) so is omitted here.
