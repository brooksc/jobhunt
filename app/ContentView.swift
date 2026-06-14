import AppKit
import JobhuntCore
import SwiftData
import SwiftUI

struct ContentView: View {
    var router: Router
    var theme: Theme
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var selectedJobIDs: Set<String> = []

    @Environment(AppServices.self) private var appServices
    @Query(filter: #Predicate<Job> { $0.unread == true }) private var unreadJobs: [Job]

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            Sidebar(router: router)
                .navigationSplitViewColumnWidth(min: 170, ideal: 210)
        } content: {
            contentColumn
        } detail: {
            detailColumn
        }
        .environment(router)
        .environment(theme)
        .environment(\.jobService, appServices.jobService)
        .environment(\.queueActor, appServices.queueActor)
        .toolbar { serviceStatusMenu }
        .overlay(alignment: .bottom) {
            ToastOverlay(store: appServices.toastStore)
        }
        .background(DockBadgeUpdater(unreadCount: unreadJobs.count))
        .onAppear {
            applyAppearance(theme.colorSchemePreference)
        }
        .onChange(of: theme.colorSchemePreference) { _, pref in applyAppearance(pref) }
        .onChange(of: router.selectedSection) { _, section in
            switch section {
            case .jobs, .sites: columnVisibility = .all
            default:
                // .doubleColumn on macOS hides the sidebar (not the detail pane),
                // so we keep .all and collapse the detail column via its content.
                columnVisibility = .all
                selectedJobIDs = []
            }
        }
        .onChange(of: router.selectedJobID) { _, jobID in
            if let id = jobID {
                selectedJobIDs = [id]
                router.selectedSection = .jobs
                columnVisibility = .all
                router.selectedJobID = nil
            }
        }
    }

    // MARK: - Content column

    @ViewBuilder
    private var contentColumn: some View {
        switch router.selectedSection {
        case .jobs:
            JobsView(selectedJobIDs: $selectedJobIDs)
                .navigationSplitViewColumnWidth(min: 300, ideal: 400)
        case .dashboard:
            DashboardView()
                .navigationSplitViewColumnWidth(min: 600, ideal: 900)
        case .dataQuality:
            DataQualityView()
                .navigationSplitViewColumnWidth(min: 600, ideal: 900)
        case .needsAction:
            NeedsActionView()
                .navigationSplitViewColumnWidth(min: 600, ideal: 900)
        case .llmQueue:
            LLMQueueView(queueActor: appServices.queueActor, settings: appServices.settings, toastStore: appServices.toastStore)
                .navigationSplitViewColumnWidth(min: 600, ideal: 900)
        case .sites:
            SitesView(siteService: appServices.siteService)
                .navigationSplitViewColumnWidth(min: 280, ideal: 340)
        case .duplicates:
            DuplicatesView()
                .navigationSplitViewColumnWidth(min: 600, ideal: 900)
        case .help:
            HelpView()
                .navigationSplitViewColumnWidth(min: 600, ideal: 900)
        case .settings:
            SettingsView()
                .navigationSplitViewColumnWidth(min: 600, ideal: 900)
        }
    }

    // MARK: - Detail / Inspector column

    @ViewBuilder
    private var detailColumn: some View {
        switch router.selectedSection {
        case .jobs:
            JobInspectorView(selectedJobIDs: $selectedJobIDs)
                .navigationSplitViewColumnWidth(min: 600, ideal: 820)
        case .sites:
            SiteInspectorView()
                .navigationSplitViewColumnWidth(min: 340, ideal: 460)
        default:
            // Full-width sections have no inspector; collapse the detail column.
            Color.clear
                .navigationSplitViewColumnWidth(min: 0, ideal: 0, max: 0)
                .accessibilityHidden(true)
        }
    }

    // MARK: - Service-status toolbar (HIG-4: interactive Menu, not bare images)

    @ToolbarContentBuilder
    private var serviceStatusMenu: some ToolbarContent {
        ToolbarItem(placement: .automatic) {
            Menu {
                Section("LLM") {
                    Label(
                        "\(appServices.settings.llmProvider) · \(shortModelName)",
                        systemImage: "cpu"
                    )
                    Button("Open LLM Queue") { router.navigateToSection(.llmQueue) }
                }
                Section("Local Server") {
                    if appServices.serverRunning {
                        Label("Server: running", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else if let err = appServices.serverError {
                        Label("Server: \(err)", systemImage: "exclamationmark.circle.fill")
                            .foregroundStyle(.red)
                        Button("Retry") {
                            Task { @MainActor in
                                appServices.serverError = nil
                                do {
                                    try await appServices.server.start()
                                    appServices.serverRunning = true
                                } catch {
                                    appServices.serverError = error.localizedDescription
                                }
                            }
                        }
                    } else {
                        Label("Server: starting…", systemImage: "circle")
                            .foregroundStyle(.secondary)
                    }
                }
                Section("Capture") {
                    Label("Extension: linked", systemImage: "puzzlepiece")
                }
            } label: {
                Image(systemName: "circle.grid.2x2")
                    .foregroundStyle(.secondary)
            }
            .help("Service status")
        }
    }

    // MARK: - Helpers

    private var shortModelName: String {
        appServices.settings.llmModel.split(separator: "-").prefix(2).joined(separator: "-")
    }

    private func applyAppearance(_ pref: Theme.ColorSchemePreference) {
        switch pref {
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:  NSApp.appearance = NSAppearance(named: .darkAqua)
        case .auto:  NSApp.appearance = nil
        }
    }


}

// MARK: - Job Inspector wrapper

struct JobInspectorView: View {
    @Binding var selectedJobIDs: Set<String>
    @Query(sort: \Job.createdAt, order: .reverse) private var allJobs: [Job]
    @Environment(\.jobService) private var jobService
    @Environment(\.queueActor) private var queueActor

    private var selectedJob: Job? {
        guard selectedJobIDs.count == 1, let id = selectedJobIDs.first else { return nil }
        return allJobs.first { $0.id == id }
    }

    var body: some View {
        if let job = selectedJob {
            JobDetailView(
                job: job,
                onNavigatePrev: { navigateAdjacentJob(offset: -1) },
                onNavigateNext: { navigateAdjacentJob(offset: +1) },
                onClose: { selectedJobIDs.removeAll() }
            )
        } else if selectedJobIDs.count > 1 {
            multiSelectionSummary
        } else {
            emptyState
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "No Job Selected",
            systemImage: "sidebar.right",
            description: Text("Select a job from the list to view details.")
        )
    }

    private var multiSelectionSummary: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("\(selectedJobIDs.count) jobs selected")
                .font(.title3.weight(.semibold))
            Text("Use right-click for bulk actions, or select a single job to inspect.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 260)

            Divider().frame(maxWidth: 200)

            VStack(spacing: 10) {
                Button {
                    let ids = Array(selectedJobIDs)
                    Task { for id in ids { try? await jobService?.archive(jobID: id) } }
                } label: {
                    Label("Archive All", systemImage: "archivebox").frame(minWidth: 160)
                }
                .buttonStyle(.bordered)

                Button {
                    let ids = Array(selectedJobIDs)
                    Task { try? await jobService?.resetExtractionBulk(jobIDs: ids) }
                } label: {
                    Label("Re-run AI on All", systemImage: "arrow.clockwise").frame(minWidth: 160)
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private func navigateAdjacentJob(offset: Int) {
        guard let currentID = selectedJobIDs.first,
              let idx = allJobs.firstIndex(where: { $0.id == currentID }) else { return }
        let nextIdx = idx + offset
        guard allJobs.indices.contains(nextIdx) else { return }
        selectedJobIDs = [allJobs[nextIdx].id]
    }
}

// MARK: - Site Inspector (HIG-11: SiteDetailView in detail column)

private struct SiteInspectorView: View {
    @Environment(Router.self) private var router
    @Environment(AppServices.self) private var appServices
    @Query private var sites: [Site]

    private var selectedSite: Site? {
        guard let id = router.selectedSiteID else { return nil }
        return sites.first { $0.id == id }
    }

    var body: some View {
        if let site = selectedSite {
            SiteDetailView(site: site, siteService: appServices.siteService)
        } else {
            ContentUnavailableView(
                "No Site Selected",
                systemImage: "globe",
                description: Text("Select a site to view details.")
            )
        }
    }
}

