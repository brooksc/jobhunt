import JobhuntCore
import SwiftData
import SwiftUI

// MARK: - Sidebar statuses shown as smart folders

private let sidebarStatuses: [JobStatus] = [
    .new,
    .pursuing,
    .applied,
    .interview,
    .offer,
    .rejected,
    .passed,
    .archived,
    .closed,
    .expired
]

/// Selected-row highlight (drawn manually because macOS 26's List(.sidebar) selection
/// highlight doesn't render — see sidebarRow).
private let sidebarSelectionColor = Color(red: 0.0, green: 0.32, blue: 0.75)

struct Sidebar: View {
    var router: Router

    @Environment(AppServices.self) private var appServices

    @Query(filter: #Predicate<JobAction> { $0.completedAt == nil }) private var pendingActions: [JobAction]
    /// Non-terminal LLM requests (queued or running) — drives the live "outstanding" badge on the
    /// LLM Queue row, updating as the queue drains (TASK-491).
    @Query(filter: #Predicate<LLMRequest> { $0.finishedAt == nil }) private var outstandingLLMRequests: [LLMRequest]
    /// How many of those are actively running — drives the activity spinner (TASK-496).
    private var llmRunningCount: Int {
        outstandingLLMRequests.count(where: { $0.status == .running })
    }

    @Query private var allJobs: [Job]
    @Query private var allDecisions: [DuplicateDecision]
    @Query(sort: \SavedSearch.sortOrder) private var savedSearches: [SavedSearch]
    @Query private var resumes: [Resume]

    /// Opens the standard macOS Settings (⌘,) window — Settings is no longer an in-window section.
    @Environment(\.openSettings) private var openSettings

    @State private var listSelection: SidebarItem? = .jobsAll
    /// Unresolved duplicate pairs awaiting review — same set the Duplicates screen shows,
    /// so the badge only appears when there is something to act on (not for already-merged dupes).
    @State private var duplicatePairCount = 0
    /// Badge counts computed off the synchronous render path (TASK-364). Recomputed off-main only
    /// when the underlying job/search data actually changes, debounced via `.task(id:)`.
    @State private var statusCounts: [JobStatus: Int] = [:]
    @State private var savedSearchCounts: [String: Int] = [:]
    @State private var renamingSearch: SavedSearch?
    @State private var renameText = ""
    @State private var searchToDelete: SavedSearch?
    /// Guards one-time restore of the persisted last view, and gates persistence so the pre-restore
    /// default never overwrites the saved selection.
    @State private var didRestore = false

    var body: some View {
        List(selection: $listSelection) {
            sidebarRow(
                .dashboard,
                id: "sidebar.dashboard",
                label: Label("Dashboard", systemImage: "chart.bar")
            )
            .help("Overview and stats")

            sidebarRow(
                .needsAction,
                id: "sidebar.needsAction",
                label: Label("Needs Action", systemImage: "bell")
            )
            .badge(pendingActions.isEmpty ? 0 : pendingActions.count)
            .help("Jobs with pending follow-up")

            sidebarRow(
                .resumes,
                id: "sidebar.resumes",
                label: Label("Resumes", systemImage: "doc.text")
            )
            .badge(resumes.isEmpty ? 0 : resumes.count)
            .help("Manage résumés used for AI fit scoring")

            Section("Jobs") {
                sidebarRow(
                    .jobsAll,
                    id: "sidebar.jobs.all",
                    label: Label("All Jobs", systemImage: "tray.2")
                )
                .badge(allJobs.count)
                .help("All captured jobs")

                ForEach(sidebarStatuses, id: \.self) { status in
                    let count = statusCounts[status] ?? 0
                    sidebarRow(
                        .jobs(status),
                        id: "sidebar.jobs.\(status.rawValue)",
                        label: Label(status.displayName, systemImage: Theme.statusSymbol(status))
                    )
                    .badge(count)
                    .help("Jobs with status: \(status.displayName)")
                }
            }

            if !savedSearches.isEmpty {
                Section("Saved Searches") {
                    ForEach(savedSearches) { search in
                        let count = savedSearchCounts[search.id] ?? 0
                        sidebarRow(
                            .savedSearch(search.id),
                            id: nil,
                            label: Label(search.name, systemImage: "pin")
                        )
                        .badge(count)
                        .help("Saved search: \(search.name)")
                        .contextMenu {
                            Button("Rename…") {
                                renamingSearch = search
                                renameText = search.name
                            }
                            Divider()
                            Button("Delete", role: .destructive) {
                                searchToDelete = search
                            }
                        }
                    }
                }
            }

            Section("Sources") {
                sidebarRow(
                    .sites,
                    id: "sidebar.sites",
                    label: Label("Sites", systemImage: "globe")
                )
                .help("Job listing sources")

                sidebarRow(
                    .duplicates,
                    id: "sidebar.duplicates",
                    label: Label("Duplicates", systemImage: "doc.on.doc")
                )
                .badge(duplicatePairCount)
                .help("Duplicate job postings awaiting review")
            }

            Section("Tools") {
                sidebarRow(
                    .llmQueue,
                    id: "sidebar.llmQueue",
                    label: HStack(spacing: 6) {
                        Label("LLM Queue", systemImage: "cpu")
                        // Activity spinner while the queue is actively processing — makes
                        // "it's working" obvious even when the outstanding count is small or
                        // briefly between the extract → fit phases (TASK-496).
                        if llmRunningCount > 0 {
                            ProgressView().controlSize(.small)
                        }
                    }
                )
                .badge(outstandingLLMRequests.isEmpty ? 0 : outstandingLLMRequests.count)
                .help("LLM processing queue status (badge = queued + running; spinner = processing)")

                sidebarRow(
                    .dataQuality,
                    id: "sidebar.dataQuality",
                    label: Label("Data Quality", systemImage: "checkmark.shield")
                )
                .help("Data quality issues")

                // Settings is the standard macOS preferences window (⌘,), not an in-window
                // section — this row just opens it.
                settingsRow

                sidebarRow(
                    .help,
                    id: "sidebar.help",
                    label: Label("Help", systemImage: "questionmark.circle")
                )
                .help("Help and documentation")
            }
        }
        .listStyle(.sidebar)
        .onChange(of: listSelection) { _, item in
            guard let item else { return }
            applySelection(item)
        }
        .onChange(of: router.selectedSection) { _, _ in syncSelectionFromRouter() }
        .onChange(of: router.sidebarJobFilter) { _, _ in syncSelectionFromRouter() }
        .onChange(of: router.activeSavedSearchID) { _, _ in syncSelectionFromRouter() }
        .onAppear {
            if !didRestore {
                didRestore = true
                restoreSelection()
            }
            syncSelectionFromRouter()
        }
        // Recompute the review-queue count off the main thread whenever jobs/decisions change.
        // SwiftUI restarts this task on each duplicateRefreshID change, giving implicit debouncing.
        .task(id: duplicateRefreshID) { await refreshDuplicateCount() }
        // Recompute status + saved-search badge counts off-main, debounced on the same idea.
        // The change signal is built from JobMatchFields/criteria — exactly the fields matching
        // consults — so a badge can never go stale from a field the signal forgot (TASK-364).
        .task(id: countsRefreshID) { await refreshBadgeCounts() }
        .sheet(item: $renamingSearch) { search in
            renameSheet(search)
        }
        .confirmationDialog(
            "Delete \"\(searchToDelete?.name ?? "")\"?",
            isPresented: .init(get: { searchToDelete != nil }, set: { if !$0 { searchToDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let search = searchToDelete {
                    let id = search.id
                    let wasSelected = listSelection == .savedSearch(search.id)
                    searchToDelete = nil
                    // Only move navigation away once the delete actually succeeds, so a failed
                    // delete doesn't strand the user on a selection that's gone (or still there).
                    Task {
                        do {
                            try await appServices.jobService.deleteSavedSearch(id: id)
                            if wasSelected { listSelection = .jobsAll }
                        } catch {
                            appServices.toastStore.show(
                                "Couldn't delete saved search: \(error.localizedDescription)",
                                isError: true
                            )
                        }
                    }
                }
            }
            Button("Cancel", role: .cancel) { searchToDelete = nil }
        }
    }

    // MARK: - Row builder

    @ViewBuilder
    private func sidebarRow(_ item: SidebarItem, id: String?, label: some View) -> some View {
        // macOS 26 regression: List(selection:) in a NavigationSplitView sidebar updates
        // neither the binding nor the highlight on mouse click. So we drive selection from
        // a Button (which reliably receives clicks) and draw the highlight ourselves.
        // Arrow-key navigation still updates `listSelection` natively, and the manual
        // highlight + onChange react to that the same way.
        let selected = listSelection == item
        Button {
            listSelection = item
        } label: {
            label
                // White icon + text on the dark-blue selection, like a native source list.
                .foregroundStyle(selected ? Color.white : Color.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 5)
                // .listRowBackground is ignored by .listStyle(.sidebar), so draw the
                // highlight here. Negative padding lets the capsule extend a few points
                // around the label without shifting the icon off its native position.
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(selected ? sidebarSelectionColor : Color.clear)
                        .padding(.horizontal, -6)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .tag(item)
        .accessibilityIdentifier(id ?? "")
    }

    /// A non-selectable sidebar row that opens the standard Settings (⌘,) window. Mirrors the
    /// unselected appearance of `sidebarRow` so it sits naturally among the navigation rows.
    private var settingsRow: some View {
        Button {
            openSettings()
        } label: {
            Label("Settings", systemImage: "gear")
                .foregroundStyle(Color.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 5)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("sidebar.settings")
        .help("App settings (⌘,)")
    }

    // MARK: - Duplicate review-queue count

    /// Changes whenever jobs (count/status/extraction) or decisions change in a way that
    /// affects duplicate detection — mirrors DuplicatesView's refresh trigger.
    private var duplicateRefreshID: Int {
        var hasher = Hasher()
        hasher.combine(allDecisions.count)
        for job in allJobs {
            hasher.combine(job.id)
            hasher.combine(job.status.rawValue)
            hasher.combine(job.extractionStatus.rawValue)
        }
        return hasher.finalize()
    }

    @MainActor
    private func refreshDuplicateCount() async {
        // Match DuplicatesView: only count pairs where both jobs are still un-marked — a job already
        // marked `.duplicate` is resolved and shouldn't drive the review badge (TASK-497).
        let snapshots = allJobs.compactMap { job -> JobSnapshot? in
            guard job.status != .duplicate, let capture = job.capture else { return nil }
            return JobSnapshot(job: job, capture: capture)
        }
        let resolvedHashes = Set(allDecisions.map(\.cleanedHash))
        let count = await Task.detached(priority: .utility) {
            DuplicateDetector().duplicateGroups(snapshots: snapshots, resolvedHashes: resolvedHashes).count
        }.value
        duplicatePairCount = count
    }

    // MARK: - Badge counts (TASK-364)

    /// Change signal for the badge counts. Built from `JobMatchFields`/`SavedSearchCriteria` — the
    /// exact fields matching consults — so the counts re-run iff something that could change a badge
    /// changed. O(N+S) per body, versus the old O(N×S) match work that ran in `body` directly.
    private var countsRefreshID: Int {
        var hasher = Hasher()
        for job in allJobs {
            hasher.combine(JobMatchFields(job: job))
        }
        for search in savedSearches {
            hasher.combine(search.id)
            hasher.combine(SavedSearchCriteria(search))
        }
        return hasher.finalize()
    }

    @MainActor
    private func refreshBadgeCounts() async {
        // Snapshot on main (cheap), run the O(N×S) matching off-main.
        let fields = allJobs.map { JobMatchFields(job: $0) }
        let criteria = savedSearches.map { (id: $0.id, criteria: SavedSearchCriteria($0)) }
        let now = Date()
        let result = await Task.detached(priority: .utility) {
            var statusByRaw: [String: Int] = [:]
            for field in fields {
                statusByRaw[field.statusRaw, default: 0] += 1
            }
            var searchCounts: [String: Int] = [:]
            for entry in criteria {
                searchCounts[entry.id] = fields.count(where: { entry.criteria.matches($0, now: now) })
            }
            return (statusByRaw, searchCounts)
        }.value

        // A newer refresh supersedes this one: `.task(id:)` cancels the old task, so bail rather
        // than publish stale counts (same hazard fixed in DuplicatesView / TASK-384).
        guard !Task.isCancelled else { return }
        var statusByEnum: [JobStatus: Int] = [:]
        for (raw, count) in result.0 {
            if let status = JobStatus(rawValue: raw) { statusByEnum[status] = count }
        }
        statusCounts = statusByEnum
        savedSearchCounts = result.1
    }

    // MARK: - Selection sync

    private func applySelection(_ item: SidebarItem) {
        router.activeSavedSearchID = nil
        switch item {
        case .dashboard: router.navigateToSection(.dashboard)
        case .needsAction: router.navigateToSection(.needsAction)
        case .jobsAll: router.sidebarJobFilter = nil; router.navigateToSection(.jobs)
        case let .jobs(status): router.sidebarJobFilter = status; router.navigateToSection(.jobs)
        case .resumes: router.navigateToSection(.resumes)
        case .sites: router.navigateToSection(.sites)
        case .duplicates: router.navigateToSection(.duplicates)
        case .llmQueue: router.navigateToSection(.llmQueue)
        case .dataQuality: router.navigateToSection(.dataQuality)
        case .help: router.navigateToSection(.help)
        case let .savedSearch(id):
            router.activeSavedSearchID = id
            router.sidebarJobFilter = nil
            router.navigateToSection(.jobs)
        }
    }

    private func syncSelectionFromRouter() {
        let item: SidebarItem
        switch router.selectedSection {
        case .dashboard: item = .dashboard
        case .needsAction: item = .needsAction
        case .jobs:
            if let id = router.activeSavedSearchID {
                item = .savedSearch(id)
            } else if let status = router.sidebarJobFilter {
                item = .jobs(status)
            } else {
                item = .jobsAll
            }
        case .resumes: item = .resumes
        case .sites: item = .sites
        case .duplicates: item = .duplicates
        case .llmQueue: item = .llmQueue
        case .dataQuality: item = .dataQuality
        case .help: item = .help
        }
        if listSelection != item { listSelection = item }
        // Remember the current view so the next launch restores it. Gated on didRestore so the
        // initial pre-restore default can't clobber the saved value.
        if didRestore { appServices.settings.lastSidebarSelection = item.persistedID }
    }

    /// Restore the last-viewed sidebar selection persisted from a previous session (e.g. "Pursuing").
    /// Falls back to the default view when nothing is stored or a saved search has since been deleted.
    private func restoreSelection() {
        guard let item = SidebarItem(persistedID: appServices.settings.lastSidebarSelection) else { return }
        if case let .savedSearch(id) = item, !savedSearches.contains(where: { $0.id == id }) { return }
        applySelection(item)
    }

    // MARK: - Rename sheet

    private func renameSheet(_ search: SavedSearch) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Rename Search").font(.headline)
            TextField("Search name", text: $renameText)
                .textFieldStyle(.roundedBorder)
                .onSubmit { commitRename(search) }
            HStack {
                Button("Cancel") { renamingSearch = nil }
                    .buttonStyle(.bordered)
                Spacer()
                Button("Rename") { commitRename(search) }
                    .disabled(renameText.trimmingCharacters(in: .whitespaces).isEmpty)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(minWidth: 280)
    }

    private func commitRename(_ search: SavedSearch) {
        let trimmed = renameText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        search.name = trimmed
        renamingSearch = nil
    }
}
