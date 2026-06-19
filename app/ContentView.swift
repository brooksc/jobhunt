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
    @Environment(\.openSettings) private var openSettings
    @Query(filter: #Predicate<Job> { $0.unread == true }) private var unreadJobs: [Job]
    @Query private var allJobs: [Job]

    // Availability check (triggered from the toolbar menu) — finds Pursuing jobs whose postings
    // appear gone, then offers to mark them Expired (same flow as Settings → Availability).
    @State private var goneJobs: [GoneJobResult] = []
    @State private var showingExpiredConfirmation = false
    @State private var isCheckingAvailability = false

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
        .sheet(isPresented: $showingExpiredConfirmation) {
            ExpiredConfirmationSheet(
                goneJobs: goneJobs,
                onConfirm: { markExpired($0) },
                onDismiss: { showingExpiredConfirmation = false }
            )
        }
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
        case .resumes:
            ResumesTab(settings: appServices.settings)
                .navigationTitle("Resumes")
                .accessibilityIdentifier("content.resumes")
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
                Section("Jobs") {
                    Button {
                        Task { await runAvailabilityCheck() }
                    } label: {
                        Label(
                            isCheckingAvailability ? "Checking availability…" : "Check Pursuing Availability",
                            systemImage: "checkmark.seal"
                        )
                    }
                    .disabled(isCheckingAvailability)
                }
                Section("LLM") {
                    if aiConfigured {
                        Label(
                            "\(appServices.settings.llmProvider) · \(shortModelName)",
                            systemImage: "cpu"
                        )
                    } else {
                        Button {
                            router.settingsTab = .llm
                            openSettings()
                        } label: {
                            Label("Set Up AI Provider…", systemImage: "exclamationmark.triangle")
                        }
                    }
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
                Image(systemName: aiConfigured ? "circle.grid.2x2" : "exclamationmark.circle")
                    .foregroundStyle(aiConfigured ? Color.secondary : Color.orange)
            }
            .help(aiConfigured ? "Service status" : "AI provider not set up — open to configure")
        }
    }

    // MARK: - Availability check

    private func runAvailabilityCheck() async {
        let pursuing = allJobs.filter { $0.status == .pursuing }
        guard !pursuing.isEmpty else {
            appServices.toastStore.show("No pursuing jobs to check")
            return
        }
        isCheckingAvailability = true
        defer { isCheckingAvailability = false }

        let found = await AvailabilityChecker.findGoneJobs(pursuing)
        appServices.settings.set(
            ISO8601DateFormatter().string(from: Date()),
            forKey: SettingsKey.availabilityLastAutoCheckAt
        )
        if found.isEmpty {
            appServices.toastStore.show("All \(pursuing.count) pursuing jobs are still available")
        } else {
            goneJobs = found
            showingExpiredConfirmation = true
        }
    }

    private func markExpired(_ jobs: [GoneJobResult]) {
        showingExpiredConfirmation = false
        let ids = jobs.map(\.jobID)
        let count = ids.count
        Task {
            do {
                try await appServices.jobService.markExpired(jobIDs: ids)
                appServices.toastStore.show("\(count) job(s) marked expired")
            } catch {
                appServices.toastStore.show("Couldn't mark jobs expired: \(error.localizedDescription)", isError: true)
            }
        }
    }

    // MARK: - Helpers

    private var shortModelName: String {
        appServices.settings.llmModel.split(separator: "-").prefix(2).joined(separator: "-")
    }

    private var aiConfigured: Bool {
        AIConfig.isConfigured(appServices.settings)
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
    @Environment(AppServices.self) private var appServices

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
            // TASK-469: give the detail view a per-job identity so prev/next navigation re-mounts it
            // — otherwise @State (loaded skills, in-progress edit buffers) carries over from the
            // previously viewed job (onAppear doesn't re-fire on a reused instance).
            .id(job.id)
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
                    Task {
                        var failed = 0
                        for id in ids {
                            do { try await jobService?.archive(jobID: id) }
                            catch { failed += 1 }
                        }
                        if failed > 0 {
                            appServices.toastStore.show("Couldn't archive \(failed) of \(ids.count) job(s)", isError: true)
                        }
                    }
                } label: {
                    Label("Archive All", systemImage: "archivebox").frame(minWidth: 160)
                }
                .buttonStyle(.bordered)

                Button {
                    let ids = Array(selectedJobIDs)
                    Task {
                        do { try await jobService?.resetExtractionBulk(jobIDs: ids) }
                        catch { appServices.toastStore.show("Couldn't re-run AI: \(error.localizedDescription)", isError: true) }
                    }
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

