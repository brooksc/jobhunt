import AppKit
import JobhuntCore
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

// MARK: - JobsView

struct JobsView: View {
    @Binding var selectedJobIDs: Set<String>

    @Environment(Router.self) private var router
    @Environment(AppServices.self) private var appServices

    @Query(sort: \Job.createdAt, order: .reverse) private var allJobs: [Job]
    @Query(sort: \SavedSearch.sortOrder) private var savedSearches: [SavedSearch]

    @State private var searchText = ""
    @State private var searchTokens: [JobSearchToken] = []
    @State private var filterState = JobsFilterState()
    @State private var showFilterPopover = false
    @State private var showSaveSheet = false
    @State private var showAddJobSheet = false
    @State private var jobIDsToDelete: [String] = []
    // Mirror of router.sidebarJobFilter as @State so SwiftUI reliably re-renders.
    @State private var localSidebarFilter: JobStatus?
    /// Cached result of the full filter+sort pipeline. Updated when any filter input changes.
    /// Avoids recomputing the list twice per render (once for List body, once for filteredJobIDs).
    @State private var cachedFilteredJobs: [Job] = []

    var body: some View {
        jobListWithModifiers
            .accessibilityIdentifier("content.jobs")
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
                        do { try await svc.delete(jobID: id) }
                        catch { toast.show("Delete failed: \(error.localizedDescription)", isError: true) }
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
                applySearchToTokens(search)
            } else if id == nil {
                searchTokens = []
                searchText = ""
                filterState = JobsFilterState()
            }
        }
        .onChange(of: router.sidebarJobFilter) { _, status in
            localSidebarFilter = status
            router.activeSavedSearchID = nil
            searchTokens = []
        }
        .onChange(of: searchTokens) { _, _ in
            router.activeSavedSearchID = nil
            cachedFilteredJobs = computeFilteredJobs()
        }
        .onChange(of: filteredJobIDs) { _, newIDs in
            // Remove stale selections when the filter changes — and tell the user if their
            // multi-selection just shrank, so they don't bulk-act on fewer jobs than they think.
            let before = selectedJobIDs.count
            selectedJobIDs = selectedJobIDs.intersection(newIDs)
            let dropped = before - selectedJobIDs.count
            if dropped > 0 && before > 1 {
                appServices.toastStore.show("\(dropped) selected job\(dropped == 1 ? "" : "s") no longer match the filter — \(selectedJobIDs.count) still selected.")
            }
        }
        .onChange(of: selectedJobIDs) { _, newIDs in
            // Mark opened when exactly one job is selected
            if newIDs.count == 1, let id = newIDs.first {
                let svc = appServices.jobService
                // Automatic side-effect (not a user command) — log a failure rather than toast.
                Task {
                    do { try await svc.markOpened(jobID: id) }
                    catch { NSLog("JobsView: markOpened failed for \(id): \(error)") }
                }
            }
        }
        // HIG-20: Space is not used for deselect (macOS convention)
        .onChange(of: router.showAddJobSheet) { _, show in
            if show { showAddJobSheet = true; router.showAddJobSheet = false }
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
                            do { try await svc.resetExtractionBulk(jobIDs: ids) }
                            catch { toast.show("Couldn't re-run AI: \(error.localizedDescription)", isError: true) }
                        }
                    } label: {
                        Label("Re-run AI on \(selectedJobIDs.count) Selected", systemImage: "arrow.clockwise")
                    }
                    Button {
                        let ids = Array(selectedJobIDs)
                        let svc = appServices.jobService
                        let toast = appServices.toastStore
                        let priors: [(String, JobStatus)] = ids.compactMap { id in
                            allJobs.first(where: { $0.id == id }).map { (id, $0.status) }
                        }
                        Task {
                            var failed = 0
                            for id in ids {
                                do { try await svc.archive(jobID: id) } catch { failed += 1 }
                            }
                            await MainActor.run {
                                selectedJobIDs = []
                                if failed > 0 {
                                    toast.show("Archive failed for \(failed) job(s)", isError: true)
                                } else {
                                    toast.show("Archived \(ids.count) job\(ids.count == 1 ? "" : "s")", actionLabel: "Undo") {
                                        Task { for (id, status) in priors { try? await svc.setStatus(status, for: id) } }
                                    }
                                }
                            }
                        }
                    } label: {
                        Label("Archive Selected", systemImage: "archivebox")
                    }
                    // TASK-464: bulk fit-only queue + open all source pages.
                    Button {
                        let ids = Array(selectedJobIDs)
                        let queue = appServices.queueActor
                        let toast = appServices.toastStore
                        Task {
                            do { try await queue.enqueueFitForActiveResumes(jobIDs: ids) }
                            catch { toast.show("Couldn't queue fit scoring: \(error.localizedDescription)", isError: true) }
                        }
                    } label: {
                        Label("Score Fit on \(selectedJobIDs.count) Selected", systemImage: "person.crop.circle.badge.checkmark")
                    }
                    Button {
                        openSelectedPages()
                    } label: {
                        Label("Open \(selectedJobIDs.count) Pages", systemImage: "safari")
                    }
                    Divider()
                }
                Button {
                    exportCSV()
                } label: {
                    Label("Export Filtered List to CSV…", systemImage: "square.and.arrow.up")
                }
                .help("Exports the current filtered/sorted list (\(filteredJobs.count) jobs). Use Back Up Data in Settings for a complete backup.")
                Divider()
                if hasActiveFilters || !searchTokens.isEmpty {
                    Button(role: .destructive) {
                        clearAllFilters()
                    } label: {
                        Label("Clear All Filters", systemImage: "xmark.circle")
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
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
                cachedFilteredJobs = computeFilteredJobs()
            }
            .onChange(of: allJobs) { _, _ in cachedFilteredJobs = computeFilteredJobs() }
            .onChange(of: searchText) { _, _ in cachedFilteredJobs = computeFilteredJobs() }
            .onChange(of: filterState) { _, _ in cachedFilteredJobs = computeFilteredJobs() }
            .onChange(of: localSidebarFilter) { _, _ in cachedFilteredJobs = computeFilteredJobs() }
    }

    // MARK: - Job list (extracted to help compiler type-check)

    private var jobList: some View {
        List(filteredJobs, selection: $selectedJobIDs) { job in
            JobListRow(job: job, isSelected: selectedJobIDs.contains(job.id))
                .tag(job.id)
                .contextMenu { jobContextMenu(job) }
                .accessibilityIdentifier("job.row.\(job.id)")
        }
        .listStyle(.inset)
        .overlay {
            if filteredJobs.isEmpty {
                if allJobs.isEmpty {
                    ContentUnavailableView(
                        "No jobs yet",
                        systemImage: "tray",
                        description: Text("Capture jobs with the Chrome extension, or press ⌘N to add one manually.")
                    )
                } else {
                    ContentUnavailableView(
                        "No matching jobs",
                        systemImage: "line.3.horizontal.decrease.circle",
                        description: Text("No jobs match the current view, filters, or search.")
                    )
                }
            }
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
                        ForEach([RemoteType.remote, .hybrid, .onsite], id: \.self) { rt in
                            remoteToggle(rt)
                        }
                    }
                }
                Divider()
                filterSection("Min Fit Score") {
                    HStack(spacing: 6) {
                        fitScoreChip(nil, label: "Any")
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
                filterSection("Location criteria") {
                    Toggle("Meets criteria only", isOn: Binding(
                        get: { filterState.meetsCriteriaOnly },
                        set: { filterState.meetsCriteriaOnly = $0 }
                    ))
                    .toggleStyle(.checkbox)
                    .font(.caption)
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

    private func fitScoreChip(_ value: Int?, label: String) -> some View {
        let active = filterState.minFitScore == value
        return Button { filterState.minFitScore = active ? nil : value } label: {
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
        filterState.hasActiveFilters || !searchTokens.isEmpty || !searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var filteredJobIDs: Set<String> {
        Set(cachedFilteredJobs.map(\.id))
    }

    private var filteredJobs: [Job] { cachedFilteredJobs }

    private func computeFilteredJobs() -> [Job] {
        let base = allJobs.filter { job in
            // Sidebar smart-folder filter (use @State mirror for reliable re-render)
            if let sidebarStatus = localSidebarFilter {
                guard job.status == sidebarStatus else { return false }
            }
            // Search tokens
            for token in searchTokens {
                switch token {
                case .status(let s):      if job.status != s { return false }
                case .minFitScore(let n): if (job.fitScore ?? 0) < n { return false }
                case .minSalary(let n):
                    let sal = job.salaryMin ?? job.salaryMax ?? 0
                    if sal < n { return false }
                case .remoteType(let rt): if job.remoteType != rt { return false }
                case .minRating(let n):   if (job.rating ?? 0) < n { return false }
                case .recentDays(let d):
                    let cutoff = Calendar.current.date(byAdding: .day, value: -d, to: Date()) ?? Date()
                    if (job.capturedAtDenormalized ?? job.createdAt) < cutoff { return false }
                }
            }
            // Advanced filter state
            if let statuses = filterState.statusFilter {
                guard statuses.contains(job.status) else { return false }
            }
            if let remotes = filterState.remoteFilter {
                guard let rt = job.remoteType, remotes.contains(rt) else { return false }
            }
            if let minFit = filterState.minFitScore {
                guard (job.fitScore ?? 0) >= minFit else { return false }
            }
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
            // TASK-464: only jobs that passed the location/remote criteria (nil = not computed → excluded).
            if filterState.meetsCriteriaOnly {
                guard job.meetsCriteria == true else { return false }
            }
            // Text search
            let q = searchText.trimmingCharacters(in: .whitespaces)
            if !q.isEmpty {
                let qLow = q.lowercased()
                let matchNum = qLow.hasPrefix("#") ? String(qLow.dropFirst()) : qLow
                // Cheap fields first; fall through to the (larger) cleaned description only if needed.
                let cheap = [job.company, job.title, job.location]
                    .compactMap(\.self).joined(separator: " ").lowercased()
                let textMatch = cheap.contains(qLow)
                    || (job.capture?.cleanedDescription?.lowercased().contains(qLow) ?? false)
                // Job number: exact match for a plain number ("133" → #133), substring otherwise.
                let numMatch = job.jobNumber.map { String($0) == matchNum || String($0).contains(matchNum) } ?? false
                if !textMatch && !numMatch { return false }
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
        let svc = appServices.jobService
        let toast = appServices.toastStore

        Menu("Set Status") {
            ForEach(JobStatus.allCases, id: \.self) { status in
                Button(status.displayName) {
                    Task {
                        var failed = 0
                        for id in targets {
                            do { try await svc.setStatus(status, for: id) } catch { failed += 1 }
                        }
                        if failed > 0 {
                            toast.show("Couldn't update status for \(failed) of \(targets.count) job(s)", isError: true)
                        }
                    }
                }
            }
        }
        Button {
            let priors: [(String, JobStatus)] = targets.compactMap { id in
                allJobs.first(where: { $0.id == id }).map { (id, $0.status) }
            }
            Task {
                var failed = 0
                for id in targets {
                    do { try await svc.archive(jobID: id) } catch { failed += 1 }
                }
                if failed > 0 {
                    toast.show("Couldn't archive \(failed) of \(targets.count) job(s)", isError: true)
                } else {
                    toast.show("Archived \(targets.count) job\(targets.count == 1 ? "" : "s")", actionLabel: "Undo") {
                        Task { for (id, status) in priors { try? await svc.setStatus(status, for: id) } }
                    }
                }
            }
        }
            label: { Label("Archive \(label)", systemImage: "archivebox") }
            .accessibilityIdentifier("jobContextMenu.archive")
        Button {
            Task {
                do { try await svc.resetExtractionBulk(jobIDs: targets) }
                catch { toast.show("Couldn't re-run AI: \(error.localizedDescription)", isError: true) }
            }
        }
            label: { Label("Re-run AI on \(label)", systemImage: "arrow.clockwise") }
            .accessibilityIdentifier("jobContextMenu.reextract")
        Divider()
        Button(role: .destructive) { jobIDsToDelete = targets }
            label: { Label("Delete \(label)", systemImage: "trash") }
    }

    // MARK: - Helpers

    private func applySearchToTokens(_ search: SavedSearch) {
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
        searchTokens = tokens
        searchText = search.searchText
        filterState.sortKey = JobsSortKey(rawValue: search.sortKeyRaw) ?? .capturedAt
        filterState.sortAscending = search.sortAscending
    }

    private func clearAllFilters() {
        searchTokens = []
        searchText = ""
        filterState = JobsFilterState()
        router.activeSavedSearchID = nil
    }

    /// TASK-464: open the source/display page for every selected job in the browser.
    private func openSelectedPages() {
        let selected = cachedFilteredJobs.filter { selectedJobIDs.contains($0.id) }
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

    var body: some View {
        HStack(spacing: 10) {
            fitRing
            jobInfo
            Spacer(minLength: 0)
            rightMeta
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }

    private var fitRing: some View {
        Group {
            if let score = job.fitScore {
                FitRingView(score: score, size: 36)
            } else {
                ZStack {
                    Circle().stroke(Color.secondary.opacity(0.12), lineWidth: 3)
                    Image(systemName: "sparkle").font(.system(size: 10)).foregroundStyle(.quaternary)
                }
                .frame(width: 36, height: 36)
            }
        }
    }

    private var jobInfo: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                if job.unread {
                    Circle().fill(Color.accentColor).frame(width: 5, height: 5)
                        .accessibilityLabel("Unread")
                }
                Text(job.title ?? "Untitled")
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

    private func formatK(_ value: Int) -> String { value >= 1000 ? "\(value / 1000)k" : "\(value)" }

    private func currencySymbol(_ code: String) -> String {
        switch code {
        case "USD": return "$"
        case "GBP": return "£"
        case "EUR": return "€"
        default:    return "$"
        }
    }
}

// MARK: - Sort key display names

private extension JobsSortKey {
    var displayName: String {
        switch self {
        case .jobNumber:   "Job #"
        case .company:     "Company"
        case .title:       "Title"
        case .status:      "Status"
        case .fitScore:    "Fit Score"
        case .rating:      "Rating"
        case .salaryMin:   "Salary (min)"
        case .salaryMax:   "Salary (max)"
        case .location:    "Location"
        case .capturedAt:  "Date Captured"
        case .extractedAt: "Date Extracted"
        case .lastOpenedAt: "Last Opened"
        }
    }
}
