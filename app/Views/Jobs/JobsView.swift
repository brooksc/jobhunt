// Large cohesive file; splitting deferred (TASK-545).
// swiftlint:disable file_length type_body_length cyclomatic_complexity
import AppKit
import JobhuntCore
import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

// MARK: - JobsView

struct JobsView: View {
    @Binding var selectedJobIDs: Set<String>

    @Environment(Router.self) private var router
    @Environment(AppServices.self) private var appServices

    @Query(sort: \Job.createdAt, order: .reverse) private var allJobs: [Job]
    @Query(sort: \SavedSearch.sortOrder) private var savedSearches: [SavedSearch]
    @Query private var resumes: [Resume]
    /// Referral attempts across all jobs — drives the per-row referral badge (TASK-630).
    @Query private var referralAttempts: [ReferralAttempt]

    /// Derived referral summary for a job from its outreach attempts (TASK-630).
    static func referralSummary(for job: Job, attempts: [ReferralAttempt]) -> ReferralSummary {
        ReferralTracking.summary(
            jobStatus: job.status.rawValue,
            attempts: attempts.map {
                .init(
                    outcome: ReferralOutcome(rawValue: $0.outcome) ?? .requested,
                    recipientName: $0.recipientName, recipientIdentifier: $0.recipientIdentifier,
                    requestedAt: $0.requestedAt
                )
            }
        )
    }

    /// Whether a fit score could ever be produced — an AI provider is configured *and* a résumé is
    /// active. When false, rows neutralize the fit ring instead of showing a forever-pending
    /// placeholder (TASK-525).
    private var fitScoringAvailable: Bool {
        AIConfig.isConfigured(appServices.settings) && resumes.contains(where: \.active)
    }

    @State private var searchText = ""
    @State private var searchTokens: [JobSearchToken] = []
    @State private var filterState = JobsFilterState()
    @State private var showFilterPopover = false
    @State private var showSaveSheet = false
    @State private var showAddJobSheet = false
    // Availability check (Actions menu) — finds Pursuing jobs whose postings appear gone, then offers
    // to mark them Expired (same confirmation flow as Settings → Availability).
    @State private var goneJobs: [GoneJobResult] = []
    @State private var unverifiedJobs: [UnverifiedJobResult] = []
    @State private var showingExpiredConfirmation = false
    @State private var isCheckingAvailability = false
    @State private var isScanningDuplicates = false
    /// Progress for a running long task (availability check / duplicate scan), shown as a modal dialog
    /// so these aren't a silent minute (TASK-640).
    @State private var progress: TaskProgressModel?
    @State private var jobIDsToDelete: [String] = []
    /// Jobs the user just archived/re-statused/deleted, so the filtered-set reconciliation below knows
    /// their drop from the current filter is an expected consequence of the command — not a surprise
    /// worth a "no longer match the filter" toast (TASK-617).
    @State private var selfRemovedIDs: Set<String> = []
    /// The row to select once a keyboard archive/status change removes the current selection from the
    /// filtered list, so keyboard triage continues without a mouse click (TASK-616).
    @State private var pendingSelectionAnchor: String?
    /// Mirror of router.sidebarJobFilter as @State so SwiftUI reliably re-renders.
    @State private var localSidebarFilter: JobStatus?
    /// Cached filter+sort result (TASK-610). `filteredJobs` was recomputed live and read ~4× per body,
    /// so an active text search faulted each job's Capture + lowercased its ~10 KB description several
    /// times per keystroke. Recompute only when `filterSignature` changes. The signature includes
    /// `count + max(updatedAt)`, so in-place mutations (a status change) still refresh it — the exact
    /// staleness that made the previous author abandon caching.
    @State private var cachedFilteredJobs: [Job] = []

    var body: some View {
        jobListWithModifiers
            .focusedSceneValue(\.jobCommands, makeJobCommands())
            .accessibilityIdentifier("content.jobs")
    }

    /// True when every selected row is already Interested, so offering to mark them Interested is a
    /// no-op. Empty selection reads false so nothing is hidden spuriously.
    private var allSelectedAreInterested: Bool {
        guard !selectedJobIDs.isEmpty else { return false }
        let selected = allJobs.filter { selectedJobIDs.contains($0.id) }
        guard !selected.isEmpty else { return false }
        return selected.allSatisfy { $0.status == .pursuing }
    }

    private var jobListWithModifiers: some View {
        jobListWithFilterObservers
            .searchable(text: $searchText, tokens: $searchTokens, prompt: "Search jobs…") { token in
                Label(token.label, systemImage: token.systemImage)
            }
            .searchSuggestions {
                JobSearchSuggestions(searchText: searchText)
            }
            .toolbar { toolbarItems }
            .navigationTitle(navTitle)
            .sheet(isPresented: $showAddJobSheet) { AddJobSheet() }
            .sheet(isPresented: $showSaveSheet) {
                SaveSearchSheet(filterState: filterState, searchText: searchText, searchTokens: searchTokens)
            }
            .sheet(isPresented: $showingExpiredConfirmation) {
                ExpiredConfirmationSheet(
                    goneJobs: goneJobs,
                    unverifiedJobs: unverifiedJobs,
                    onConfirm: { markExpired($0) },
                    onDismiss: { showingExpiredConfirmation = false }
                )
            }
            .sheet(isPresented: Binding(get: { progress != nil }, set: { if !$0 { progress = nil } })) {
                if let progress { TaskProgressDialog(model: progress) }
            }
            // Clicking the background "jobs may be gone" macOS notification opens this review.
            .onReceive(NotificationCenter.default.publisher(for: .runAvailabilityReview)) { _ in
                guard !isCheckingAvailability else { return }
                Task { await runAvailabilityCheck() }
            }
            .confirmationDialog(
                "Delete \(jobIDsToDelete.count == 1 ? "Job" : "\(jobIDsToDelete.count) Jobs")?",
                isPresented: .init(get: { !jobIDsToDelete.isEmpty }, set: { if !$0 { jobIDsToDelete = [] } }),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    let ids = jobIDsToDelete
                    let svc = appServices.jobService
                    let toast = appServices.toastStore
                    jobIDsToDelete = []
                    Task {
                        for id in ids {
                            do { try await svc.delete(jobID: id) } catch { toast.show(
                                "Delete failed: \(error.localizedDescription)",
                                isError: true
                            ) }
                        }
                        await MainActor.run { selectedJobIDs = selectedJobIDs.subtracting(ids) }
                    }
                }
                Button("Cancel", role: .cancel) { jobIDsToDelete = [] }
            } message: {
                Text("This will permanently delete the job and all related data.")
            }
            .onChange(of: router.activeSavedSearchID) { _, id in
                if let id, let search = savedSearches.first(where: { $0.id == id }) {
                    applySavedSearch(search)
                } else if id == nil {
                    searchTokens = []
                    searchText = ""
                    filterState = JobsFilterState()
                    // #7: a sidebar/smart-folder switch clears the saved search but should keep
                    // the user's chosen sort rather than snapping back to the default.
                    applyPersistedSort()
                }
            }
            .onChange(of: router.sidebarJobFilter) { _, status in
                localSidebarFilter = status
                router.activeSavedSearchID = nil
                searchTokens = []
            }
            // Dashboard "needs a referral" card → open Jobs pre-filtered to referral-needs-outreach
            // (TASK-644). Widen to All Jobs so the funnel-status matches aren't hidden by a smart folder.
            .onChange(of: router.focusReferralOutreach) { _, on in if on { applyReferralOutreachFilter() } }
            .onAppear { if router.focusReferralOutreach { applyReferralOutreachFilter() } }
            .onChange(of: searchTokens) { _, newTokens in
                // Programmatically applying a saved search sets these exact tokens — keep it active.
                // Any user-initiated token edit diverges from the saved set and clears it (TASK-572).
                if let id = router.activeSavedSearchID,
                   let search = savedSearches.first(where: { $0.id == id }),
                   search.remainsActive(forTokenIDs: Set(newTokens.map(\.id))) {
                    return
                }
                router.activeSavedSearchID = nil
            }
            .onChange(of: filteredJobIDs) { _, newIDs in
                // Reconcile the selection when the filter changes. Only warn about selections that
                // dropped for reasons OTHER than the user's own archive/status/delete command — those
                // self-removals are expected and already get one aggregate toast (TASK-617). One keyed,
                // coalescing toast, so a bulk change can't produce a stack.
                let before = selectedJobIDs.count
                let removed = selectedJobIDs.subtracting(newIDs)
                selectedJobIDs = selectedJobIDs.intersection(newIDs)
                let unexpected = removed.subtracting(selfRemovedIDs)
                selfRemovedIDs.subtract(removed) // consume the acknowledged self-removals
                // TASK-616: after a keyboard archive/status change empties the selection, advance to the
                // pre-computed next surviving row so triage continues without a mouse click.
                if selectedJobIDs.isEmpty, !removed.isEmpty, let anchor = pendingSelectionAnchor,
                   newIDs.contains(anchor) {
                    selectedJobIDs = [anchor]
                }
                pendingSelectionAnchor = nil
                if !unexpected.isEmpty && before > 1 {
                    appServices.toastStore.show(
                        "\(unexpected.count) selected job\(unexpected.count == 1 ? "" : "s") no longer match the "
                            + "filter — \(selectedJobIDs.count) still selected.",
                        key: "selection.shrink"
                    )
                }
            }
            .onChange(of: selectedJobIDs) { _, newIDs in
                // Mark opened when exactly one job is selected
                if newIDs.count == 1, let id = newIDs.first {
                    let svc = appServices.jobService
                    // Automatic side-effect (not a user command) — log a failure rather than toast.
                    Task {
                        do { try await svc.markOpened(jobID: id) } catch {
                            NSLog("JobsView: markOpened failed for \(id): \(error)")
                        }
                    }
                }
            }
            // HIG-20: Space is not used for deselect (macOS convention)
            .onChange(of: router.showAddJobSheet) { _, show in
                if show { showAddJobSheet = true; router.showAddJobSheet = false }
            }
            .onChange(of: router.exportJobsRequested) { _, requested in
                if requested { router.exportJobsRequested = false; exportCSV() }
            }
            .onChange(of: router.focusSearch) { _, focus in
                if focus {
                    router.focusSearch = false
                    DispatchQueue.main.async {
                        guard let toolbar = NSApp.keyWindow?.toolbar else { return }
                        for item in toolbar.items {
                            if let searchItem = item as? NSSearchToolbarItem {
                                searchItem.beginSearchInteraction()
                                return
                            }
                        }
                    }
                }
            }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                showAddJobSheet = true
            } label: {
                Image(systemName: "plus")
            }
            .help("Add job by URL")

            if hasActiveFilters {
                Button {
                    showSaveSheet = true
                } label: {
                    Image(systemName: "bookmark")
                }
                .help("Save current search")
            }

            Menu {
                ForEach(JobsSortKey.allCases, id: \.self) { key in
                    Button {
                        if filterState.sortKey == key {
                            filterState.sortAscending.toggle()
                        } else {
                            filterState.sortKey = key
                            filterState.sortAscending = false
                        }
                    } label: {
                        HStack {
                            Text(key.displayName)
                            if filterState.sortKey == key {
                                Image(systemName: filterState.sortAscending ? "chevron.up" : "chevron.down")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 2) {
                    Image(systemName: "arrow.up.arrow.down")
                    Text(filterState.sortKey.displayName)
                        .font(.caption.weight(.medium))
                    Image(systemName: filterState.sortAscending ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                }
            }
            .help("Sort jobs")

            Button { showFilterPopover.toggle() } label: {
                HStack(spacing: 4) {
                    Image(systemName: "line.3.horizontal.decrease")
                    Text("Filter")
                        .font(.caption.weight(.medium))
                    if filterState.activeFilterCount > 0 {
                        Text("\(filterState.activeFilterCount)")
                            .font(.caption2.weight(.semibold))
                    }
                }
            }
            .help("Advanced filters")
            .accessibilityLabel("Advanced filters")
            .popover(isPresented: $showFilterPopover) {
                filterPopover
            }

            Menu {
                if !selectedJobIDs.isEmpty {
                    Button {
                        let ids = Array(selectedJobIDs)
                        let svc = appServices.jobService
                        let toast = appServices.toastStore
                        Task {
                            do { try await svc.resetExtractionBulk(jobIDs: ids) } catch { toast.show(
                                "Couldn't re-run AI: \(error.localizedDescription)",
                                isError: true
                            ) }
                        }
                    } label: {
                        Label("Re-run AI on \(selectedJobIDs.count) Selected", systemImage: "arrow.clockwise")
                    }
                    // Pointless when every selected job is already Interested — which is always the
                    // case on the Interested view, and also when the user hand-picks interested rows
                    // elsewhere.
                    if !allSelectedAreInterested {
                        Button {
                            let ids = Array(selectedJobIDs)
                            setStatusJobs(.pursuing, ids)
                            selectedJobIDs = []
                        } label: {
                            Label("Mark Selected as Interested", systemImage: "bookmark")
                        }
                    }
                    Button {
                        let ids = Array(selectedJobIDs)
                        archiveJobs(ids)
                        selectedJobIDs = []
                    } label: {
                        Label("Archive Selected", systemImage: "archivebox")
                    }
                    // Destructive Delete alongside Archive (TASK-604). Selection is kept until the
                    // confirmation is accepted (the dialog clears it on success) so Cancel is a no-op.
                    Button(role: .destructive) {
                        jobIDsToDelete = Array(selectedJobIDs)
                    } label: {
                        Label("Delete \(selectedJobIDs.count) Selected…", systemImage: "trash")
                    }
                    // TASK-464: bulk fit-only queue + open all source pages.
                    Button {
                        let ids = Array(selectedJobIDs)
                        let queue = appServices.queueActor
                        let toast = appServices.toastStore
                        Task {
                            do { try await queue.enqueueFitForActiveResumes(jobIDs: ids) } catch { toast.show(
                                "Couldn't queue fit scoring: \(error.localizedDescription)",
                                isError: true
                            ) }
                        }
                    } label: {
                        Label(
                            "Score Fit on \(selectedJobIDs.count) Selected",
                            systemImage: "person.crop.circle.badge.checkmark"
                        )
                    }
                    Button {
                        openSelectedPages()
                    } label: {
                        Label("Open \(selectedJobIDs.count) Pages", systemImage: "safari")
                    }
                    Divider()
                }
                Button {
                    Task { await runAvailabilityCheck() }
                } label: {
                    Label(
                        isCheckingAvailability ? "Checking availability…" : "Check Job Description Availability",
                        systemImage: "checkmark.seal"
                    )
                }
                .disabled(isCheckingAvailability)
                Button {
                    Task { await runDuplicateScan() }
                } label: {
                    Label(
                        isScanningDuplicates ? "Scanning for duplicates…" : "Scan for Duplicates",
                        systemImage: "doc.on.doc"
                    )
                }
                .disabled(isScanningDuplicates)
                Button {
                    exportCSV()
                } label: {
                    Label("Export Filtered List to CSV…", systemImage: "square.and.arrow.up")
                }
                .help(
                    "Exports the current filtered/sorted list (\(filteredJobs.count) jobs). " +
                        "Use Back Up Data in Settings for a complete backup."
                )
                Divider()
                if hasActiveFilters || !searchTokens.isEmpty {
                    Button(role: .destructive) {
                        clearAllFilters()
                    } label: {
                        Label("Clear All Filters", systemImage: "xmark.circle")
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "ellipsis.circle")
                    Text("Actions")
                        .font(.caption.weight(.medium))
                }
            }
            .help("More actions")
        }
    }

    // MARK: - Status filter bar

    // MARK: - Filter observers (extracted to reduce modifier chain length for type-checker)

    private var jobListWithFilterObservers: some View {
        jobList
            .onAppear {
                localSidebarFilter = router.sidebarJobFilter
                // #7: restore the persisted sort when no saved search is dictating one.
                if router.activeSavedSearchID == nil { applyPersistedSort() }
                cachedFilteredJobs = computeFilteredJobs()
            }
            // Recompute the filter/sort only when an input actually changes (TASK-610).
            .onChange(of: filterSignature) { _, _ in
                cachedFilteredJobs = computeFilteredJobs()
            }
            .onChange(of: filterState.sortKey) { _, newKey in
                appServices.settings.jobsSortKey = newKey.rawValue
            }
            .onChange(of: filterState.sortAscending) { _, newAsc in
                appServices.settings.jobsSortAscending = newAsc
            }
    }

    // MARK: - Job list (extracted to help compiler type-check)

    private var jobList: some View {
        VStack(spacing: 0) {
            activeFiltersBar
            jobListInner
        }
    }

    private var jobListInner: some View {
        // Compute once per render — NOT inside the row closure. `fitScoringAvailable` reads the
        // Keychain (API-key presence) via AIConfig.isConfigured, so evaluating it per row meant one
        // Keychain hit per visible job (~hundreds of ms when switching filters on a full list).
        let canScore = fitScoringAvailable
        let attemptsByJob = Dictionary(grouping: referralAttempts) { $0.jobID }
        return ScrollViewReader { proxy in
            List(filteredJobs, selection: $selectedJobIDs) { job in
                JobListRow(
                    job: job, isSelected: selectedJobIDs.contains(job.id), fitScoringAvailable: canScore,
                    referralSummary: Self.referralSummary(for: job, attempts: attemptsByJob[job.id] ?? [])
                )
                .tag(job.id)
                // Re-identify the row when extraction fills it in, so List re-measures it.
                //
                // List caches a row's height when the row is created. A job is inserted at capture
                // time with one line — just its title — and measured at 24pt. Extraction then adds
                // company, location and salary and swaps the placeholder for a 36pt fit ring, but the
                // cached 24pt stands: the ring and the entire second line render clipped, and stay
                // clipped until something rebuilds the list (changing the sort does it). That is why
                // it looked like stale data — the text was in the accessibility tree the whole time,
                // in a row too short to draw it.
                //
                // Nothing INSIDE the row fixes this: a `.frame(height:)` or `minHeight` below the
                // cached height is simply clipped, and one above it silently re-measures every row and
                // made the list 8pt taller. Changing the identity is what actually invalidates the one
                // row that needs it.
                .id("\(job.id)#\(job.extractionStatus.rawValue)")
                .contextMenu { jobContextMenu(job) }
                .accessibilityIdentifier("job.row.\(job.id)")
            }
            .listStyle(.inset)
            // The Delete key on the focused/selected row(s) opens the same confirmation dialog as the
            // context-menu / Job-menu Delete (TASK-507). Archive is keyboard-reachable via ⌃⌘A.
            .onDeleteCommand {
                let ids = Array(selectedJobIDs)
                if !ids.isEmpty { jobIDsToDelete = ids }
            }
            .overlay {
                if filteredJobs.isEmpty {
                    if allJobs.isEmpty {
                        VStack(spacing: 20) {
                            ContentUnavailableView(
                                "No jobs yet",
                                systemImage: "tray",
                                description: Text(
                                    "Capture jobs with the Chrome extension, or press ⌘N to add one manually."
                                )
                            )
                            // First-run setup checklist — hides itself once AI + résumé are configured.
                            SetupChecklistCard(settings: appServices.settings)
                                .frame(maxWidth: 440)
                                .padding(.horizontal)
                        }
                    } else {
                        ContentUnavailableView(
                            "No matching jobs",
                            systemImage: "line.3.horizontal.decrease.circle",
                            description: Text("No jobs match the current view, filters, or search.")
                        )
                    }
                }
            }
            // Scroll to a job opened via external navigation. onChange covers the already-mounted
            // case (notification while on Jobs); onAppear covers arriving from another section.
            .onChange(of: router.pendingJobScrollID) { _, target in
                scrollToPendingJob(proxy, target)
            }
            .onAppear { scrollToPendingJob(proxy, router.pendingJobScrollID) }
        }
    }

    /// Scroll the list to a job opened via external navigation (Open Job / notification deep-link),
    /// then clear the one-shot signal. Deferred a tick so the target row exists after a mount or
    /// filter change. A no-op when the job isn't in the current filtered list.
    private func scrollToPendingJob(_ proxy: ScrollViewProxy, _ target: String?) {
        guard let target else { return }
        DispatchQueue.main.async {
            withAnimation { proxy.scrollTo(target, anchor: .center) }
            router.pendingJobScrollID = nil
        }
    }

    // MARK: - Filter popover

    private var filterPopover: some View {
        VStack(spacing: 0) {
            // HIG-12: explicit dismiss control for large popover
            HStack {
                Text("Filters").font(.headline)
                Spacer()
                Button("Done") { showFilterPopover = false }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    filterSection("Remote") {
                        HStack(spacing: 6) {
                            ForEach([RemoteType.remote, .hybrid, .onsite, .unknown], id: \.self) { rt in
                                remoteToggle(rt)
                            }
                        }
                    }
                    Divider()
                    filterSection("Min Fit Score") {
                        HStack(spacing: 6) {
                            fitScoreChip(nil, label: "Any")
                            unscoredChip()
                            fitScoreChip(55, label: "55+")
                            fitScoreChip(70, label: "70+")
                            fitScoreChip(85, label: "85+")
                        }
                    }
                    Divider()
                    filterSection("Min Rating") {
                        HStack(spacing: 6) {
                            ratingChip(nil, label: "Any")
                            ForEach([3, 4, 5], id: \.self) { r in ratingChip(r, label: "\(r)★+") }
                        }
                    }
                    Divider()
                    filterSection("Min Salary") {
                        HStack(spacing: 6) {
                            salaryChip(nil, label: "Any")
                            salaryChip(100_000, label: "$100k")
                            salaryChip(150_000, label: "$150k")
                            salaryChip(200_000, label: "$200k")
                        }
                    }
                    Divider()
                    filterSection("Captured") {
                        HStack(spacing: 6) {
                            recentChip(nil, label: "Any time")
                            recentChip(7, label: "7 days")
                            recentChip(30, label: "30 days")
                            recentChip(90, label: "90 days")
                        }
                    }
                    Divider()
                    filterSection("Extraction") {
                        HStack(spacing: 6) {
                            extractionChip(nil, label: "Any")
                            extractionChip(.succeeded, label: "OK")
                            extractionChip(.pending, label: "Pending")
                            extractionChip(.failed, label: "Failed")
                        }
                    }
                    Divider()
                    filterSection("Requirements") {
                        HStack(spacing: 6) {
                            meetsCriteriaChip(nil, label: "Any")
                            meetsCriteriaChip(.meets, label: "Meets")
                            meetsCriteriaChip(.notStated, label: "Not stated")
                            meetsCriteriaChip(.doesNotMeet, label: "Doesn't meet")
                        }
                    }
                    Divider()
                    filterSection("Source") {
                        sourceMenu
                    }
                    Divider()
                    filterSection("Reading") {
                        Toggle("Unread only", isOn: Binding(
                            get: { filterState.unreadOnly },
                            set: { filterState.unreadOnly = $0 }
                        ))
                        .toggleStyle(.checkbox)
                        .font(.caption)
                    }
                    Divider()
                    filterSection("Data quality") {
                        HStack(spacing: 6) {
                            qualityChip(nil, label: "Any")
                            qualityChip(.hasIssues, label: "Any issue")
                            qualityChip(.highSeverity, label: "High severity")
                        }
                    }
                    Divider()
                    filterSection("Referral") {
                        Toggle("Needs referral outreach", isOn: Binding(
                            get: { filterState.needsReferralOutreach },
                            set: { filterState.needsReferralOutreach = $0 }
                        ))
                        .toggleStyle(.checkbox)
                        .font(.caption)
                        .help("Applied / interview / offer jobs with no referral outreach yet")
                    }
                }
            } // end ScrollView
        } // end outer VStack
        .frame(width: 280)
    }

    private func filterSection(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                .textCase(.uppercase).tracking(0.3)
            content()
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    private func remoteToggle(_ rt: RemoteType) -> some View {
        let label: String
        switch rt {
        case .remote: label = "Remote"
        case .hybrid: label = "Hybrid"
        case .onsite: label = "On-site"
        case .unknown: label = "Unknown"
        }
        let active = filterState.remoteFilter?.contains(rt) == true
        return Button {
            var set = filterState.remoteFilter ?? []
            if active { set.remove(rt) } else { set.insert(rt) }
            filterState.remoteFilter = set.isEmpty ? nil : set
        } label: {
            Text(label).font(.caption)
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(active ? Color.accentColor : Color.secondary.opacity(0.1))
                .foregroundStyle(active ? .white : .primary).clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("filter.remote.\(rt.rawValue)")
        .accessibilityValue(active ? "on" : "off")
    }

    /// The job's standing against every configured requirement. Thresholds come from settings and are
    /// applied at read time, so changing one re-filters immediately with no recompute.
    private func requirementsVerdict(for job: Job) -> JobRequirements.Verdict? {
        JobRequirements.evaluate(
            meetsCriteria: job.meetsCriteria,
            remoteType: job.remoteType,
            salaryMin: job.salaryMin,
            salaryMax: job.salaryMax,
            salaryCurrency: job.salaryCurrency,
            fitScore: job.fitScore,
            thresholds: JobRequirements.Thresholds(
                minSalary: appServices.settings.minSalary,
                minFitScore: appServices.settings.minFitScore
            )
        )
    }

    /// Tri-state location-criteria chip (TASK-649). "Doesn't meet" is the in-office review pile —
    /// `LocationCriteria` counts an unknown/absent remote type as onsite, so with onsite disallowed
    /// those postings land here. It's a heuristic for *review*, not a verdict: a posting that never
    /// states its arrangement may still be remote-friendly, so nothing is archived automatically.
    private func meetsCriteriaChip(_ value: JobFilterRules.CriteriaBucket?, label: String) -> some View {
        let active = filterState.criteriaBucket == value
        return Button { filterState.criteriaBucket = value } label: {
            Text(label).font(.caption)
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(active ? Color.accentColor : Color.secondary.opacity(0.1))
                .foregroundStyle(active ? .white : .primary).clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? .isSelected : [])
        .accessibilityValue(active ? "on" : "off")
    }

    /// Data-quality triage chips. "High severity" is the re-sourcing shortlist — missing
    /// company/title/location or a failed extraction, i.e. records thin enough that the original
    /// posting needs finding on the company's own careers site or ATS.
    private func qualityChip(_ value: JobFilterRules.QualityFilter?, label: String) -> some View {
        let active = filterState.qualityFilter == value
        return Button { filterState.qualityFilter = value } label: {
            Text(label).font(.caption)
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(active ? Color.accentColor : Color.secondary.opacity(0.1))
                .foregroundStyle(active ? .white : .primary).clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? .isSelected : [])
        .accessibilityValue(active ? "on" : "off")
    }

    /// "Not scored" — jobs that were never fit-scored. Mutually exclusive with a minimum, since an
    /// absent score is excluded by every threshold.
    private func unscoredChip() -> some View {
        let active = filterState.unscoredOnly
        return Button {
            filterState.unscoredOnly.toggle()
            if filterState.unscoredOnly { filterState.minFitScore = nil }
        } label: {
            Text("Not scored").font(.caption)
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(active ? Color.accentColor : Color.secondary.opacity(0.1))
                .foregroundStyle(active ? .white : .primary).clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? .isSelected : [])
        .accessibilityValue(active ? "on" : "off")
    }

    /// Capture hosts present in the library, most common first, with counts — so the aggregator vs
    /// ATS split is visible at a glance. Multi-select; empty selection means "any source".
    private var sourceMenu: some View {
        let counts = Dictionary(allJobs.compactMap(\.captureHost).map { ($0, 1) }, uniquingKeysWith: +)
        let hosts = counts.sorted { ($0.value, $1.key) > ($1.value, $0.key) }.prefix(12)
        let selected = filterState.sourceHosts ?? []
        return Menu {
            if !selected.isEmpty {
                Button("Clear source filter") { filterState.sourceHosts = nil }
                Divider()
            }
            ForEach(Array(hosts), id: \.key) { host, count in
                Button {
                    var next = selected
                    if next.contains(host) { next.remove(host) } else { next.insert(host) }
                    filterState.sourceHosts = next.isEmpty ? nil : next
                } label: {
                    Label(
                        "\(host) (\(count))",
                        systemImage: selected.contains(host) ? "checkmark.circle.fill" : "circle"
                    )
                }
            }
        } label: {
            Text(selected.isEmpty ? "Any source" : "\(selected.count) selected").font(.caption)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func fitScoreChip(_ value: Int?, label: String) -> some View {
        let active = filterState.minFitScore == value
        return Button {
            filterState.minFitScore = active ? nil : value
            if filterState.minFitScore != nil { filterState.unscoredOnly = false }
        } label: {
            Text(label).font(.caption)
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(active ? Color.accentColor : Color.secondary.opacity(0.1))
                .foregroundStyle(active ? .white : .primary).clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? .isSelected : [])
        .accessibilityValue(active ? "on" : "off")
    }

    private func ratingChip(_ value: Int?, label: String) -> some View {
        let active = filterState.minRating == value
        return Button { filterState.minRating = active ? nil : value } label: {
            Text(label).font(.caption)
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(active ? Color.accentColor : Color.secondary.opacity(0.1))
                .foregroundStyle(active ? .white : .primary).clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? .isSelected : [])
        .accessibilityValue(active ? "on" : "off")
    }

    private func salaryChip(_ value: Int?, label: String) -> some View {
        let active = filterState.minSalary == value
        return Button { filterState.minSalary = active ? nil : value } label: {
            Text(label).font(.caption)
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(active ? Color.accentColor : Color.secondary.opacity(0.1))
                .foregroundStyle(active ? .white : .primary).clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? .isSelected : [])
        .accessibilityValue(active ? "on" : "off")
    }

    private func extractionChip(_ value: ExtractionStatus?, label: String) -> some View {
        let active = filterState.extractionFilter == value
        return Button { filterState.extractionFilter = active ? nil : value } label: {
            Text(label).font(.caption)
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(active ? Color.accentColor : Color.secondary.opacity(0.1))
                .foregroundStyle(active ? .white : .primary).clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? .isSelected : [])
        .accessibilityValue(active ? "on" : "off")
    }

    private func recentChip(_ value: Int?, label: String) -> some View {
        let active = filterState.recentDays == value
        return Button { filterState.recentDays = active ? nil : value } label: {
            Text(label).font(.caption)
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(active ? Color.accentColor : Color.secondary.opacity(0.1))
                .foregroundStyle(active ? .white : .primary).clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? .isSelected : [])
        .accessibilityValue(active ? "on" : "off")
    }

    // MARK: - Computed

    private var navTitle: String {
        if let filter = router.sidebarJobFilter { return filter.displayName }
        if let id = router.activeSavedSearchID,
           let search = savedSearches.first(where: { $0.id == id }) { return search.name }
        return "All Jobs"
    }

    private var hasActiveFilters: Bool {
        filterState.hasActiveFilters || !searchTokens.isEmpty || !searchText.trimmingCharacters(in: .whitespaces)
            .isEmpty
    }

    /// #7: load the persisted Jobs sort into `filterState`.
    private func applyPersistedSort() {
        filterState.sortKey = JobsSortKey(rawValue: appServices.settings.jobsSortKey) ?? .capturedAt
        filterState.sortAscending = appServices.settings.jobsSortAscending
    }

    /// Consume the one-shot Router request to show referral-needs-outreach jobs (TASK-644): clear any
    /// narrowing so the funnel-status matches are visible, enable the filter, then reset the flag.
    private func applyReferralOutreachFilter() {
        router.sidebarJobFilter = nil
        router.activeSavedSearchID = nil
        searchTokens = []
        searchText = ""
        filterState.needsReferralOutreach = true
        router.focusReferralOutreach = false
    }

    // MARK: - Active filters bar (#6)

    private var anyActiveConstraint: Bool {
        localSidebarFilter != nil || router.activeSavedSearchID != nil
            || !searchTokens.isEmpty || !searchText.trimmingCharacters(in: .whitespaces).isEmpty
            || filterState.hasActiveFilters
    }

    private var savedSearchName: String {
        guard let id = router.activeSavedSearchID,
              let s = savedSearches.first(where: { $0.id == id }) else { return "Saved search" }
        return s.name
    }

    /// A visible bar listing what's currently constraining the list, so the user always knows
    /// why they're seeing a subset — each chip removes just that constraint.
    @ViewBuilder
    private var activeFiltersBar: some View {
        if anyActiveConstraint {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    if router.activeSavedSearchID != nil {
                        filterChip(savedSearchName, icon: "bookmark.fill") { router.activeSavedSearchID = nil }
                            .accessibilityIdentifier("chip.savedSearch")
                    }
                    if let status = localSidebarFilter {
                        filterChip(status.displayName, icon: "tag") { router.sidebarJobFilter = nil }
                    }
                    let q = searchText.trimmingCharacters(in: .whitespaces)
                    if !q.isEmpty {
                        filterChip("“\(q)”", icon: "magnifyingglass") { searchText = "" }
                    }
                    ForEach(searchTokens) { token in
                        filterChip(token.label, icon: token.systemImage) {
                            searchTokens.removeAll { $0 == token }
                        }
                    }
                    if router.activeSavedSearchID == nil, filterState.hasActiveFilters {
                        let n = filterState.activeFilterCount
                        filterChip("\(n) filter\(n == 1 ? "" : "s")", icon: "line.3.horizontal.decrease.circle") {
                            let key = filterState.sortKey
                            let asc = filterState.sortAscending
                            filterState = JobsFilterState()
                            filterState.sortKey = key
                            filterState.sortAscending = asc
                        }
                    }
                    Button("Clear All") { clearAllFilters() }
                        .buttonStyle(.plain)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.accentColor)
                        .padding(.leading, 2)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
            .background(.bar)
            Divider()
        }
    }

    private func filterChip(_ label: String, icon: String? = nil, onRemove: @escaping () -> Void) -> some View {
        HStack(spacing: 4) {
            if let icon { Image(systemName: icon).font(.caption2) }
            Text(label).font(.caption).lineLimit(1)
            Button(action: onRemove) {
                Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.accentColor.opacity(0.12), in: Capsule())
    }

    private var filteredJobIDs: Set<String> {
        Set(filteredJobs.map(\.id))
    }

    private var filteredJobs: [Job] {
        cachedFilteredJobs
    }

    /// Cheap per-body change signal for `cachedFilteredJobs`. O(N) over one `updatedAt` read per job
    /// (no Capture fault, no description lowercasing) — far cheaper than the full filter, and it
    /// changes whenever any input to the filter/sort could change: the query, tokens, filters, the
    /// sidebar folder, insert/delete (count), or any job edit/status change (max updatedAt).
    private var filterSignature: Int {
        var hasher = Hasher()
        hasher.combine(searchText)
        hasher.combine(localSidebarFilter)
        hasher.combine(searchTokens)
        hasher.combine(filterState)
        hasher.combine(allJobs.count)
        hasher.combine(referralAttempts.count) // re-filter when a referral is recorded/removed (TASK-630)
        var maxUpdated = Date.distantPast
        for job in allJobs where job.updatedAt > maxUpdated {
            maxUpdated = job.updatedAt
        }
        hasher.combine(maxUpdated)
        return hasher.finalize()
    }

    private func computeFilteredJobs() -> [Job] {
        let referralAttemptsByJob = Dictionary(grouping: referralAttempts) { $0.jobID }
        let base = allJobs.filter { job in
            // Sidebar smart-folder filter (use @State mirror for reliable re-render)
            if let sidebarStatus = localSidebarFilter {
                guard job.status == sidebarStatus else { return false }
            }
            // Search tokens
            for token in searchTokens {
                switch token {
                case let .status(s): if job.status != s { return false }
                case let .minFitScore(n): if (job.fitScore ?? 0) < n { return false }
                case let .minSalary(n):
                    let sal = job.salaryMin ?? job.salaryMax ?? 0
                    if sal < n { return false }
                case let .remoteType(rt): if job.remoteType != rt { return false }
                case let .minRating(n): if (job.rating ?? 0) < n { return false }
                case let .recentDays(d):
                    let cutoff = Calendar.current.date(byAdding: .day, value: -d, to: Date()) ?? Date()
                    if (job.capturedAtDenormalized ?? job.createdAt) < cutoff { return false }
                }
            }
            // Advanced filter state
            if let statuses = filterState.statusFilter {
                guard statuses.contains(job.status) else { return false }
            }
            guard JobFilterRules.matchesRemote(job.remoteType, selected: filterState.remoteFilter) else {
                return false
            }
            guard JobFilterRules.matchesFitScore(
                fitScore: job.fitScore, minimum: filterState.minFitScore,
                unscoredOnly: filterState.unscoredOnly
            ) else { return false }
            if let minRating = filterState.minRating {
                guard (job.rating ?? 0) >= minRating else { return false }
            }
            if let minSalary = filterState.minSalary {
                let salary = job.salaryMin ?? job.salaryMax ?? 0
                guard salary >= minSalary else { return false }
            }
            if let days = filterState.recentDays {
                let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
                guard (job.capturedAtDenormalized ?? job.createdAt) >= cutoff else { return false }
            }
            if let extraction = filterState.extractionFilter {
                guard job.extractionStatus == extraction else { return false }
            }
            // Location/remote criteria verdict (TASK-464; bucketed in TASK-649). A job whose verdict
            // was never computed (extraction failed) matches no bucket, rather than being silently
            // lumped in with the rejects.
            if let wanted = filterState.criteriaBucket {
                // Location + salary floor + fit floor, evaluated together (see JobRequirements).
                guard requirementsVerdict(for: job)?.bucket == wanted else { return false }
            }
            guard JobFilterRules.matchesSource(
                host: job.captureHost, selected: filterState.sourceHosts
            ) else { return false }
            if filterState.unreadOnly { guard job.unread else { return false } }
            // Data quality — computed ONLY when the filter is on: QualityChecker faults each job's
            // Capture when the byte-count caches are absent (131 of 547 jobs today), which is exactly
            // the per-keystroke cost TASK-610 removed from the search path.
            if let quality = filterState.qualityFilter {
                guard JobFilterRules.matchesQuality(
                    kinds: QualityChecker.issues(for: job), wanted: quality
                ) else { return false }
            }
            // TASK-630: only funnel jobs that still need referral outreach.
            if filterState.needsReferralOutreach {
                let summary = Self.referralSummary(for: job, attempts: referralAttemptsByJob[job.id] ?? [])
                guard summary == .needsOutreach else { return false }
            }
            // Text search — one matcher shared with saved-search badge counts so an opened saved
            // search shows exactly as many rows as its sidebar badge (TASK-573). Display fallbacks
            // keep un-extracted jobs findable by page title / capture host (TASK-525).
            if !SavedSearchCriteria.textNumberMatch(
                query: searchText,
                displayCompany: job.displayCompany,
                displayTitle: job.displayTitle,
                location: job.location,
                cleanedDescription: job.capture?.cleanedDescription,
                jobNumber: job.jobNumber
            ) {
                return false
            }
            return true
        }
        return JobsSortLogic.sorted(base, key: filterState.sortKey, ascending: filterState.sortAscending)
    }

    // MARK: - Context menu

    @ViewBuilder
    private func jobContextMenu(_ job: Job) -> some View {
        let targets: [String] = selectedJobIDs.contains(job.id) ? Array(selectedJobIDs) : [job.id]
        let label: String = targets.count > 1 ? "\(targets.count) Jobs" : "Job"

        Button { openPostingJobs(targets) }
            label: { Label(
                targets.count > 1 ? "Open \(targets.count) Postings" : "Open Posting",
                systemImage: "arrow.up.right.square"
            ) }
        Button { copyJobLink(job) }
            label: { Label("Copy Job Link", systemImage: "link") }
        // Add Note targets the right-clicked job (notes are per-job) — selects it and opens its
        // Timeline tab in the detail pane, regardless of any multi-selection.
        Button {
            selectedJobIDs = [job.id]
            router.composeNoteJobID = job.id
        }
        label: { Label("Add Note", systemImage: "note.text.badge.plus") }
        Divider()
        Menu("Set Status") {
            ForEach(JobStatus.allCases, id: \.self) { status in
                Button(status.displayName) { setStatusJobs(status, targets) }
            }
        }
        Button { archiveJobs(targets) }
            label: { Label("Archive \(label)", systemImage: "archivebox") }
            .accessibilityIdentifier("jobContextMenu.archive")
        Button { reRunJobs(targets) }
            label: { Label("Re-run AI on \(label)", systemImage: "arrow.clockwise") }
            .accessibilityIdentifier("jobContextMenu.reextract")
        Divider()
        Button(role: .destructive) { jobIDsToDelete = targets }
            label: { Label("Delete \(label)", systemImage: "trash") }
    }

    // MARK: - Selection actions (shared by the row context menu and the menu-bar Job menu)

    /// Archive a set of jobs with an Undo toast restoring each job's prior status. Rapid archives
    /// coalesce into one bell entry ("Archived N jobs") with a combined Undo-all (TASK-645).
    private func archiveJobs(_ ids: [String]) {
        guard !ids.isEmpty else { return }
        selfRemovedIDs.formUnion(ids) // these will drop from the filter by our own command (TASK-617)
        // Keep keyboard triage focused: pre-compute the row to select once these drop out (TASK-616).
        pendingSelectionAnchor = SelectionNavigation.nextSelection(order: filteredJobs.map(\.id), removing: Set(ids))
        let svc = appServices.jobService
        let toast = appServices.toastStore
        let priors: [(String, JobStatus)] = ids.compactMap { id in
            allJobs.first(where: { $0.id == id }).map { (id, $0.status) }
        }
        Task {
            do {
                try await svc.setStatusBulk(.archived, jobIDs: ids)
                await MainActor.run {
                    toast.show(
                        "Archived \(ids.count) job\(ids.count == 1 ? "" : "s")",
                        key: "archive", actionLabel: "Undo",
                        action: { Self.restore(priors, using: svc, toast: toast) },
                        itemCount: ids.count,
                        groupMessage: { "Archived \($0) job\($0 == 1 ? "" : "s")" }
                    )
                }
            } catch {
                await MainActor.run {
                    toast.show("Couldn't archive jobs: \(error.localizedDescription)", isError: true)
                }
            }
        }
    }

    /// Set status on a set of jobs with an Undo toast restoring each job's prior status. Rapid changes
    /// coalesce into one bell entry ("Updated N jobs") with a combined Undo-all (TASK-645).
    private func setStatusJobs(_ status: JobStatus, _ ids: [String]) {
        guard !ids.isEmpty else { return }
        selfRemovedIDs.formUnion(ids) // may drop from the current filter by our own command (TASK-617)
        // Keep keyboard triage focused: pre-compute the row to select once these drop out (TASK-616).
        pendingSelectionAnchor = SelectionNavigation.nextSelection(order: filteredJobs.map(\.id), removing: Set(ids))
        let svc = appServices.jobService
        let toast = appServices.toastStore
        let priors: [(String, JobStatus)] = ids.compactMap { id in
            allJobs.first(where: { $0.id == id }).map { (id, $0.status) }
        }
        Task {
            do {
                try await svc.setStatusBulk(status, jobIDs: ids)
                await MainActor.run {
                    let changed = priors.filter { $0.1 != status }
                    guard !changed.isEmpty else { return }
                    toast.show(
                        "Status set to \(status.displayName)",
                        key: "status", actionLabel: "Undo",
                        action: { Self.restore(changed, using: svc, toast: toast) },
                        itemCount: changed.count,
                        groupMessage: { "Updated \($0) job\($0 == 1 ? "" : "s")" }
                    )
                }
            } catch {
                await MainActor.run {
                    toast.show("Couldn't update job statuses: \(error.localizedDescription)", isError: true)
                }
            }
        }
    }

    /// Restore each job to its prior status (the Undo body), surfacing an error toast on any failure.
    private static func restore(_ priors: [(String, JobStatus)], using svc: JobService, toast: ToastStore) {
        Task {
            var failed = 0
            for (id, status) in priors {
                do { try await svc.setStatus(status, for: id) } catch { failed += 1 }
            }
            if failed > 0 {
                await MainActor.run {
                    toast.show("Couldn't undo \(failed) of \(priors.count) job(s).", isError: true)
                }
            }
        }
    }

    private func reRunJobs(_ ids: [String]) {
        guard !ids.isEmpty else { return }
        let svc = appServices.jobService
        let toast = appServices.toastStore
        Task {
            do { try await svc.resetExtractionBulk(jobIDs: ids) } catch { toast.show(
                "Couldn't re-run AI: \(error.localizedDescription)",
                isError: true
            ) }
        }
    }

    private func openPostingJobs(_ ids: [String]) {
        let jobs = allJobs.filter { ids.contains($0.id) }
        var opened = 0
        for job in jobs {
            if let urlStr = JobURLPolicy.displayURL(job: job), let url = URL(string: urlStr) {
                NSWorkspace.shared.open(url)
                opened += 1
            }
        }
        if opened == 0 { appServices.toastStore.show("No posting link available") }
    }

    private func copyJobLink(_ job: Job) {
        guard let urlStr = JobURLPolicy.displayURL(job: job) else {
            appServices.toastStore.show("No link available for this job")
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(urlStr, forType: .string)
        appServices.toastStore.show("Link copied")
    }

    /// Handlers published to the menu-bar Job menu; act on the current selection.
    private func makeJobCommands() -> JobCommandHandlers {
        let ids = Array(selectedJobIDs)
        return JobCommandHandlers(
            hasSelection: !ids.isEmpty,
            openPosting: { openPostingJobs(ids) },
            reRunExtraction: { reRunJobs(ids) },
            archive: { archiveJobs(ids) },
            delete: { jobIDsToDelete = ids },
            setStatus: { status in setStatusJobs(status, ids) }
        )
    }

    // MARK: - Helpers

    /// The token list a saved search maps to. Single source of truth so `applySavedSearch` and the
    /// token-change observer agree on what "the active saved search's tokens" are (TASK-572).
    private func tokens(for search: SavedSearch) -> [JobSearchToken] {
        var tokens: [JobSearchToken] = []
        for raw in search.statusFilterRaw {
            if let s = JobStatus(rawValue: raw) { tokens.append(.status(s)) }
        }
        for raw in search.remoteFilterRaw {
            if let rt = RemoteType(rawValue: raw) { tokens.append(.remoteType(rt)) }
        }
        if let fit = search.minFitScore { tokens.append(.minFitScore(fit)) }
        if let sal = search.minSalary { tokens.append(.minSalary(sal)) }
        if let rating = search.minRating { tokens.append(.minRating(rating)) }
        if let days = search.recentDays { tokens.append(.recentDays(days)) }
        return tokens
    }

    /// Apply a saved search atomically: reset the full filter state first (so prior session-only
    /// filters like extraction status / meets-criteria-only can't keep narrowing — TASK-572), then
    /// install the saved criteria as tokens + text + sort. The token-change observer recognizes these
    /// tokens as the active saved search's and leaves `activeSavedSearchID` set.
    private func applySavedSearch(_ search: SavedSearch) {
        filterState = JobsFilterState()
        filterState.sortKey = JobsSortKey(rawValue: search.sortKeyRaw) ?? .capturedAt
        filterState.sortAscending = search.sortAscending
        searchText = search.searchText
        searchTokens = tokens(for: search)
    }

    private func clearAllFilters() {
        searchTokens = []
        searchText = ""
        filterState = JobsFilterState()
        // Clear the sidebar smart-folder status too (TASK-574) — "Clear All" promised to remove all
        // constraints, but this one was managed outside this path and left the user stuck in a status
        // folder. Return sidebar selection to All Jobs.
        localSidebarFilter = nil
        router.sidebarJobFilter = nil
        applyPersistedSort() // #7: clearing filters shouldn't reset the chosen sort
        router.activeSavedSearchID = nil
    }

    /// Check every Interested/Applied job's posting for removal, showing a modal progress dialog with a
    /// live count and a Cancel (TASK-640). On completion: nothing gone → a message; some gone → the
    /// expired-confirmation sheet. A native notification fires if the app was backgrounded meanwhile.
    private func runAvailabilityCheck() async {
        let eligible = allJobs.filter { $0.status == .pursuing || $0.status == .applied }
        guard !eligible.isEmpty else {
            appServices.toastStore.show("No Interested or Applied jobs to check")
            return
        }
        isCheckingAvailability = true
        defer { isCheckingAvailability = false }

        let model = TaskProgressModel(title: "Checking availability", total: eligible.count)
        let task = Task {
            await AvailabilityChecker.findGoneJobsRotating(
                eligible, settings: appServices.settings
            ) { checked, total in
                await MainActor.run { model.current = checked; model.total = total }
            }
        }
        model.onCancel = { task.cancel() }
        progress = model
        let sweep = await task.value
        let found = sweep.gone
        guard !task.isCancelled else { progress = nil; return } // user cancelled — leave everything untouched

        appServices.settings.set(
            ISO8601DateFormatter().string(from: Date()),
            forKey: SettingsKey.availabilityLastAutoCheckAt
        )
        unverifiedJobs = sweep.unverified
        if found.isEmpty {
            // Show the result in the dialog itself (no transient toast) — the user dismisses it.
            // A blocked or deferred check proves nothing, so don't report those jobs as available.
            let verified = eligible.count - sweep.unverified.count
            var completion = sweep.unverified.isEmpty
                ? "All \(eligible.count) Interested or Applied jobs are still available."
                : "No expired postings found — \(verified) of \(eligible.count) verified."
            if let summary = sweep.unverifiedSummary { completion += " \(summary)" }
            model.completion = completion
            model.onDone = { progress = nil }
        } else {
            progress = nil
            // Let the progress sheet finish dismissing before presenting the confirmation sheet.
            try? await Task.sleep(for: .milliseconds(350))
            goneJobs = found
            showingExpiredConfirmation = true
        }
        notifyIfBackgrounded(
            title: "Availability check complete",
            body: found.isEmpty
                ? "\(eligible.count - sweep.unverified.count) of \(eligible.count) verified available"
                : "\(found.count) job(s) may be gone"
        )
    }

    /// Re-scan for duplicate pairs on demand with a modal progress spinner (TASK-600/623/640). Nothing is
    /// auto-marked — nothing to review shows a message; otherwise it jumps to the Duplicates screen.
    private func runDuplicateScan() async {
        isScanningDuplicates = true
        defer { isScanningDuplicates = false }

        let model = TaskProgressModel(title: "Scanning for duplicates", total: 0) // indeterminate: single scan
        let task = Task { () -> Int? in
            try? await appServices.backgroundStore.reviewablePairCount()
        }
        model.onCancel = { task.cancel() }
        progress = model
        let pairs = await task.value
        guard !task.isCancelled else { progress = nil; return }

        guard let pairs else {
            progress = nil
            appServices.toastStore.show("Couldn't scan for duplicates", isError: true)
            return
        }
        if pairs == 0 {
            model.completion = "No duplicate pairs to review."
            model.onDone = { progress = nil }
        } else {
            progress = nil
            router.navigateToSection(.duplicates)
        }
        notifyIfBackgrounded(
            title: "Duplicate scan complete",
            body: pairs == 0 ? "No duplicates to review" : "\(pairs) pair(s) to review"
        )
    }

    /// Post a native macOS notification only when Jobhunt isn't frontmost — so a long task that finished
    /// while the user tabbed away isn't missed (in-app UI already covers the foreground case, TASK-640).
    private func notifyIfBackgrounded(title: String, body: String) {
        guard !NSApplication.shared.isActive else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        )
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

    private func openSelectedPages() {
        let selected = filteredJobs.filter { selectedJobIDs.contains($0.id) }
        for job in selected {
            if let urlStr = JobURLPolicy.displayURL(job: job), let url = URL(string: urlStr) {
                NSWorkspace.shared.open(url)
            }
        }
    }

    private func exportCSV() {
        let csv = ExportService.jobsCSV(jobs: filteredJobs)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "jobs-filtered.csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try ExportService.write(csv, to: url)
        } catch {
            appServices.toastStore.show("Export failed: \(error.localizedDescription)", isError: true)
        }
    }
}

// MARK: - Job list row

private struct JobListRow: View {
    let job: Job
    let isSelected: Bool
    let fitScoringAvailable: Bool
    var referralSummary: ReferralSummary = .none

    var body: some View {
        HStack(spacing: 10) {
            fitRing
            jobInfo
            Spacer(minLength: 0)
            rightMeta
        }
        // A height floor, because List does NOT re-measure a row whose content grows in place.
        //
        // A freshly captured job has one line — just its title — so the row is measured at ~24pt. When
        // extraction fills in company, location and salary a second line appears, and the fit ring
        // (36pt on its own) replaces the placeholder, but the row keeps the height it was first given:
        // the ring and the whole second line render clipped, and stay clipped until something rebuilds
        // the list. Changing the sort fixes it, which is what made this look like stale data rather
        // than a layout bug — the text was in the accessibility tree the entire time, at 24pt.
        //
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }

    private var fitRing: some View {
        Group {
            if let score = job.fitScore {
                FitRingView(score: score, size: 36)
            } else if fitScoringAvailable {
                // A score can still be produced — show the awaiting-score placeholder.
                ZStack {
                    Circle().stroke(Color.secondary.opacity(0.12), lineWidth: 3)
                    Image(systemName: "sparkle").font(.system(size: 10)).foregroundStyle(.quaternary)
                }
                .frame(width: 36, height: 36)
            }
            // else: no LLM / no active résumé — render nothing so the row doesn't imply a pending
            // score forever (TASK-525).
        }
    }

    private var jobInfo: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                if job.unread {
                    Circle().fill(Color.accentColor).frame(width: 5, height: 5)
                        .accessibilityLabel("Unread")
                }
                Text(job.displayTitle)
                    .font(.subheadline.weight(job.unread ? .semibold : .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            HStack(spacing: 3) {
                if let company = job.company {
                    Text(company).font(.caption.weight(.semibold)).foregroundStyle(.primary)
                }
                if let location = job.location, !location.isEmpty {
                    Text("·").font(.caption).foregroundStyle(.quaternary)
                    Text(location).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                if let remote = job.remoteType, remote != .unknown {
                    Text("·").font(.caption).foregroundStyle(.quaternary)
                    Text(remote.displayName).font(.caption).foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var rightMeta: some View {
        VStack(alignment: .trailing, spacing: 2) {
            StatusChip(status: job.status)
            if referralSummary != .none {
                ReferralBadge(summary: referralSummary)
            }
            if let salary = salaryText {
                Text(salary).font(.caption2.monospacedDigit()).foregroundStyle(.tertiary)
            }
        }
    }

    private var salaryText: String? {
        let parts: [String] = [job.salaryMin.map { formatK($0) }, job.salaryMax.map { formatK($0) }].compactMap(\.self)
        guard !parts.isEmpty else { return nil }
        let sym = currencySymbol(job.salaryCurrency ?? "USD")
        return sym + parts.joined(separator: "–")
    }

    private func formatK(_ value: Int) -> String {
        value >= 1000 ? "\(value / 1000)k" : "\(value)"
    }

    private func currencySymbol(_ code: String) -> String {
        switch code {
        case "USD": return "$"
        case "GBP": return "£"
        case "EUR": return "€"
        default: return "$"
        }
    }
}

// MARK: - Sort key display names

private extension JobsSortKey {
    var displayName: String {
        switch self {
        case .jobNumber: "Job #"
        case .company: "Company"
        case .title: "Title"
        case .status: "Status"
        case .fitScore: "Fit Score"
        case .rating: "Rating"
        case .salaryMin: "Salary (min)"
        case .salaryMax: "Salary (max)"
        case .location: "Location"
        case .capturedAt: "Date Captured"
        case .extractedAt: "Date Extracted"
        case .lastOpenedAt: "Last Opened"
        }
    }
}
