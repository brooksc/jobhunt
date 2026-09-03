import AppKit
import JobhuntCore
import SwiftData
import SwiftUI

struct ContentView: View {
    var router: Router
    var theme: Theme
    /// Persisted across launches (TASK-508). `NavigationSplitViewVisibility` isn't
    /// `RawRepresentable`, so a token is stored and mapped — `@SceneStorage` needs a plain value.
    @SceneStorage("jobs.columnVisibility") private var columnVisibilityToken = ""
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    /// Current window content width, so the job list can be sized as a share of it rather than a
    /// constant. At a fixed `min: 300` the column sat near 300pt in a 1900pt window, truncating
    /// nearly every title and wrapping company names to two lines while the detail pane held an
    /// empty state.
    @State private var windowWidth: CGFloat = 0

    /// Job-list column bounds, as a share of the window.
    ///
    /// Clamped at both ends: a share alone would make the column unusable on a small window and
    /// absurd on an ultrawide one. The floor is what fixes the reported symptom — the column can no
    /// longer be squeezed to 300pt just because the window is large enough to make that look silly.
    private var jobsColumnWidth: (min: CGFloat, ideal: CGFloat) {
        guard windowWidth > 0 else { return (300, 400) }
        return (
            min: Swift.min(Swift.max(windowWidth * 0.22, 300), 460),
            ideal: Swift.min(Swift.max(windowWidth * 0.28, 360), 560)
        )
    }

    @State private var selectedJobIDs: Set<String> = []
    @State private var showNotifications = false

    @Environment(AppServices.self) private var appServices
    @Environment(\.openSettings) private var openSettings
    @Query(filter: #Predicate<Job> { $0.unread == true }) private var unreadJobs: [Job]
    /// For the status bar's resting state. A few hundred rows, per the project's own note about not
    /// optimising for a scale this app won't reach.
    @Query private var allJobs: [Job]
    /// Narrowed to discovered captures in the predicate; the date is applied in memory because a
    /// `@Query` predicate is fixed when the view is created, and one built around "today" would keep
    /// reporting yesterday's count after midnight.
    @Query(filter: #Predicate<Capture> { $0.discoveredBySourceID != nil })
    private var discoveredCaptures: [Capture]

    /// Outstanding AI work. Kept as a `@Query` rather than pushed into `ActivityCenter`, because the
    /// queue's state already lives in the store and mirroring it imperatively would give the bar a
    /// second, drifting copy of a number SwiftData already publishes.
    /// Captured as locals because `#Predicate` can't name an enum case directly in a key-path
    /// comparison — it has to compare against a value the closure captured.
    @Query(filter: {
        let queued = LLMRequestStatus.queued
        let running = LLMRequestStatus.running
        return #Predicate<LLMRequest> { $0.status == queued || $0.status == running }
    }())
    private var outstandingRequests: [LLMRequest]

    private var discoveredTodayCount: Int {
        let start = Calendar.current.startOfDay(for: Date())
        return discoveredCaptures.count { $0.capturedAt >= start }
    }

    var body: some View {
        VStack(spacing: 0) {
            // App-wide queue alert lives ABOVE the split view (not as a `.safeAreaInset` on it) so it
            // can't render under the unified title bar and overlap the toolbar / sidebar (TASK-542).
            // When there's no alert this `if` produces nothing, so the layout is unchanged.
            if let alert = router.queueAlert {
                QueueAlertBanner(alert: alert, router: router) { router.queueAlert = nil }
            }
            splitView
                .background(
                    // Measures the window's content width so the job-list column can scale with it.
                    // A GeometryReader in the background participates in no layout of its own, so it
                    // reports the size without influencing it.
                    GeometryReader { proxy in
                        Color.clear
                            .onAppear { windowWidth = proxy.size.width }
                            .onChange(of: proxy.size.width) { _, width in windowWidth = width }
                    }
                )
        }
        .onAppear {
            columnVisibility = SplitVisibilityToken.visibility(for: columnVisibilityToken)
        }
        .onChange(of: columnVisibility) { _, new in
            columnVisibilityToken = SplitVisibilityToken.token(for: new)
        }
    }

    /// Maps `NavigationSplitViewVisibility` to a storable token and back (TASK-508).
    ///
    /// `detailOnly` is deliberately *not* restored as itself: relaunching into a hidden sidebar with
    /// no selected job leaves an empty window and no obvious way back. It restores as `all`.
    private enum SplitVisibilityToken {
        static func token(for visibility: NavigationSplitViewVisibility) -> String {
            switch visibility {
            case .detailOnly: "detailOnly"
            case .doubleColumn: "doubleColumn"
            default: "all"
            }
        }

        static func visibility(for token: String) -> NavigationSplitViewVisibility {
            switch token {
            case "doubleColumn": .doubleColumn
            default: .all
            }
        }
    }

    private var splitView: some View {
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
        // Published from the ROOT, not from the queue view. It was documented as coming from
        // LLMQueueView and in fact came from nowhere, so `@FocusedValue(\.queueCommands)` was always
        // nil and the Queue menu was permanently disabled — while still rendering "Pause Queue",
        // which reads as "the queue is running". Publishing here also means the command works from
        // any section: a paused queue is most likely to be noticed on the Jobs list, not on the queue
        // screen.
        .focusedSceneValue(\.queueCommands, QueueCommandHandlers(
            isPaused: appServices.settings.llmQueuePaused,
            togglePause: {
                let resume = appServices.settings.llmQueuePaused
                appServices.settings.llmQueuePaused = !resume
                Task {
                    if resume {
                        await appServices.queueActor.resumeQueue()
                    } else {
                        await appServices.queueActor.pauseQueue()
                    }
                }
            }
        ))
        .toolbar {
            notificationBell
            serviceStatusMenu
        }
        // The transient message now lives in the status bar rather than a floating capsule — see
        // StatusBar. Everything actionable or failed is still in the bell, unchanged.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            StatusBar(
                // Passed, not read from the environment: `.safeAreaInset` content is built outside
                // the host's environment, so `@Environment(AppServices.self)` inside it traps at
                // runtime and the compiler says nothing.
                activity: appServices.activity,
                toasts: appServices.toastStore,
                jobCount: allJobs.count,
                discoveredToday: discoveredTodayCount,
                queuedAIRequests: outstandingRequests.count,
                aiPaused: appServices.settings.llmQueuePaused,
                onOpen: { router.navigateToSection($0) }
            )
        }
        // Keyboard Shortcuts overlay (TASK-499) — opened by bare `?` (via the key monitor) or the
        // Help ▸ Keyboard Shortcuts menu item; Escape / the close button dismiss it.
        .sheet(isPresented: Binding(
            get: { router.showKeyboardShortcuts },
            set: { router.showKeyboardShortcuts = $0 }
        )) {
            KeyboardShortcutsView(dismiss: { router.showKeyboardShortcuts = false })
        }
        .modifier(KeyboardShortcutMonitor(router: router))
        .background(DockBadgeUpdater(unreadCount: unreadJobs.count { $0.status.awaitsReview }))
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
                .navigationSplitViewColumnWidth(
                    min: jobsColumnWidth.min, ideal: jobsColumnWidth.ideal, max: 720
                )
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
            LLMQueueView(
                queueActor: appServices.queueActor,
                settings: appServices.settings,
                toastStore: appServices.toastStore
            )
            .navigationSplitViewColumnWidth(min: 600, ideal: 900)
        case .sites:
            SitesView(siteService: appServices.siteService)
                .navigationSplitViewColumnWidth(min: 280, ideal: 340)
        case .duplicates:
            DuplicatesView()
                .navigationSplitViewColumnWidth(min: 600, ideal: 900)
        case .applicationHistory:
            ApplicationHistoryView()
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

    // MARK: - Notification center (bell) toolbar (TASK-645)

    @ToolbarContentBuilder
    private var notificationBell: some ToolbarContent {
        ToolbarItem(placement: .automatic) {
            Button {
                showNotifications.toggle()
            } label: {
                Image(systemName: appServices.toastStore.notifications.isEmpty ? "bell" : "bell.badge")
                    .foregroundStyle(appServices.toastStore.notifications.contains { $0.kind == .error }
                        ? Color.orange : Color.secondary)
            }
            .accessibilityLabel("Notifications")
            .help("Notifications")
            .popover(isPresented: $showNotifications, arrowEdge: .bottom) {
                NotificationCenterView(store: appServices.toastStore)
            }
        }
    }

    // MARK: - Service-status toolbar (HIG-4: interactive Menu, not bare images)

    @ToolbarContentBuilder
    private var serviceStatusMenu: some ToolbarContent {
        ToolbarItem(placement: .automatic) {
            Menu {
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
                HStack(spacing: 4) {
                    Image(systemName: aiConfigured ? "circle.grid.2x2" : "exclamationmark.circle")
                    Text("Status")
                        .font(.caption.weight(.medium))
                }
                .foregroundStyle(aiConfigured ? Color.secondary : Color.orange)
            }
            .help(aiConfigured
                ? "Status: AI provider, LLM queue, local server, and capture extension"
                : "Status: AI provider needs setup — also LLM queue, local server, capture extension")
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
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        case .auto: NSApp.appearance = nil
        }
    }
}

// MARK: - Job Inspector wrapper

struct JobInspectorView: View {
    @Binding var selectedJobIDs: Set<String>
    @Query(sort: \Job.createdAt, order: .reverse) private var allJobs: [Job]
    @Environment(\.jobService) private var jobService
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

    /// True when every selected row is already Interested, so offering to mark them Interested is a
    /// no-op. Mirrors the same check in the Jobs Actions menu.
    private var allSelectedAreInterested: Bool {
        guard !selectedJobIDs.isEmpty else { return false }
        let selected = allJobs.filter { selectedJobIDs.contains($0.id) }
        guard !selected.isEmpty else { return false }
        return selected.allSatisfy { $0.status == .pursuing }
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
                // Hidden when every selected job is already Interested — the same rule as the Actions
                // menu, so the two bulk-action surfaces agree.
                if !allSelectedAreInterested {
                    Button {
                        let ids = Array(selectedJobIDs)
                        Task {
                            do { try await jobService?.setStatusBulk(.pursuing, jobIDs: ids) } catch {
                                appServices.toastStore.show(
                                    "Couldn't update \(ids.count) job(s): \(error.localizedDescription)",
                                    isError: true
                                )
                            }
                        }
                    } label: {
                        Label("Mark \(selectedJobIDs.count) as Interested", systemImage: "bookmark")
                            .frame(minWidth: 160)
                    }
                    .buttonStyle(.bordered)
                }

                Button {
                    let ids = Array(selectedJobIDs)
                    Task {
                        var failed = 0
                        for id in ids {
                            do { try await jobService?.archive(jobID: id) } catch { failed += 1 }
                        }
                        if failed > 0 {
                            appServices.toastStore.show(
                                "Couldn't archive \(failed) of \(ids.count) job(s)",
                                isError: true
                            )
                        }
                    }
                } label: {
                    Label("Archive \(selectedJobIDs.count)", systemImage: "archivebox").frame(minWidth: 160)
                }
                .buttonStyle(.bordered)

                Button {
                    let ids = Array(selectedJobIDs)
                    Task {
                        do { try await jobService?.resetExtractionBulk(jobIDs: ids) } catch {
                            appServices.toastStore.show(
                                "Couldn't re-run AI: \(error.localizedDescription)",
                                isError: true
                            )
                        }
                    }
                } label: {
                    Label("Re-run AI on \(selectedJobIDs.count)", systemImage: "arrow.clockwise").frame(minWidth: 160)
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
