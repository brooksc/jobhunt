import AppKit
import JobhuntCore
import SwiftData
import SwiftUI

// MARK: - Sidebar statuses shown as smart folders
private let sidebarStatuses: [JobStatus] = [.new, .pursuing, .applied, .interview, .offer, .rejected, .passed, .archived, .closed, .expired]

struct Sidebar: View {
    var router: Router

    @Environment(AppServices.self) private var appServices

    @Query(filter: #Predicate<JobAction> { $0.completedAt == nil }) private var pendingActions: [JobAction]
    @Query(filter: #Predicate<Job> { $0.duplicateOfJobID != nil }) private var duplicateJobs: [Job]
    @Query private var allJobs: [Job]
    @Query(sort: \SavedSearch.sortOrder) private var savedSearches: [SavedSearch]

    @State private var listSelection: SidebarItem?
    @State private var renamingSearch: SavedSearch?
    @State private var renameText = ""
    @State private var searchToDelete: SavedSearch?

    var body: some View {
        List(selection: $listSelection) {
            sidebarRow(.dashboard, id: "sidebar.dashboard",
                       label: Label("Dashboard", systemImage: "chart.bar"))
                .help("Overview and stats")

            sidebarRow(.needsAction, id: "sidebar.needsAction",
                       label: Label("Needs Action", systemImage: "bell"))
                .badge(pendingActions.isEmpty ? 0 : pendingActions.count)
                .help("Jobs with pending follow-up")

            Section("Jobs") {
                // Compute status counts once — avoids O(N×S) work from per-status filter calls.
                let statusCounts = Dictionary(grouping: allJobs, by: \.status).mapValues(\.count)

                sidebarRow(.jobsAll, id: "sidebar.jobs.all",
                           label: Label("All Jobs", systemImage: "tray.2"))
                    .badge(allJobs.count)
                    .help("All captured jobs")

                ForEach(sidebarStatuses, id: \.self) { status in
                    let count = statusCounts[status] ?? 0
                    sidebarRow(.jobs(status), id: "sidebar.jobs.\(status.rawValue)",
                               label: Label(status.displayName, systemImage: Theme.statusSymbol(status)))
                        .badge(count)
                        .help("Jobs with status: \(status.displayName)")
                }
            }

            if !savedSearches.isEmpty {
                Section("Saved Searches") {
                    // Compute all search counts in one pass over allJobs per search.
                    // Cached into a dictionary so each search label doesn't re-filter.
                    let searchCounts: [String: Int] = {
                        var counts = [String: Int]()
                        for search in savedSearches {
                            counts[search.id] = allJobs.count(where: { search.matches($0) })
                        }
                        return counts
                    }()
                    ForEach(savedSearches) { search in
                        let count = searchCounts[search.id] ?? 0
                        sidebarRow(.savedSearch(search.id), id: nil,
                                   label: Label(search.name, systemImage: "pin"))
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
                sidebarRow(.sites, id: "sidebar.sites",
                           label: Label("Sites", systemImage: "globe"))
                    .help("Job listing sources")

                sidebarRow(.duplicates, id: "sidebar.duplicates",
                           label: Label("Duplicates", systemImage: "doc.on.doc"))
                    .badge(duplicateJobs.isEmpty ? 0 : duplicateJobs.count)
                    .help("Duplicate job postings")
            }

            Section("Tools") {
                sidebarRow(.llmQueue, id: "sidebar.llmQueue",
                           label: Label("LLM Queue", systemImage: "cpu"))
                    .help("LLM processing queue status")

                sidebarRow(.dataQuality, id: "sidebar.dataQuality",
                           label: Label("Data Quality", systemImage: "checkmark.shield"))
                    .help("Data quality issues")

                sidebarRow(.settings, id: "sidebar.settings",
                           label: Label("Settings", systemImage: "gear"))
                    .help("App settings")
            }
        }
        .listStyle(.sidebar)
        // macOS 26 regression: List(selection:) with .sidebar style does NOT update the
        // @State binding when rows are clicked via NSOutlineView. The onChange below handles
        // the case where the binding IS updated (future macOS fixes); the
        // OutlineViewSelectionObserver background handles the macOS 26 click path via AppKit.
        .onChange(of: listSelection) { oldItem, item in
            guard let item else {
                // macOS 26 regression: selectRowIndexes fires selectionDidChangeNotification
                // which SwiftUI maps back to nil (reverse lookup fails). Re-assert the
                // previous item. If NSOutlineView row is already selected when we call
                // selectRowIndexes again, no new notification fires → loop terminates.
                if let old = oldItem { listSelection = old }
                return
            }
            applySelection(item)
            let savedCount = savedSearches.count
            DispatchQueue.main.async {
                selectSidebarOutlineViewRow(item: item, savedSearchCount: savedCount)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                selectSidebarOutlineViewRow(item: item, savedSearchCount: savedCount)
            }
        }
        .onChange(of: router.selectedSection) { _, _ in syncSelectionFromRouter() }
        .onChange(of: router.sidebarJobFilter) { _, _ in syncSelectionFromRouter() }
        .onChange(of: router.activeSavedSearchID) { _, _ in syncSelectionFromRouter() }
        .onAppear { syncSelectionFromRouter() }
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
                    if listSelection == .savedSearch(search.id) {
                        listSelection = .jobsAll
                    }
                    let id = search.id
                    Task { try? await appServices.jobService.deleteSavedSearch(id: id) }
                    searchToDelete = nil
                }
            }
            Button("Cancel", role: .cancel) { searchToDelete = nil }
        }
    }

    // MARK: - Row builder

    @ViewBuilder
    private func sidebarRow(_ item: SidebarItem, id: String?, label: some View) -> some View {
        // macOS 26 regression: List(selection:) doesn't update its @State binding or
        // NSOutlineView visual selection on mouse click.
        // - simultaneousGesture: lets NSOutlineView also receive the click so it can
        //   establish keyboard focus (needed for arrow-key navigation in tests).
        // - deferred state update: the List's internal gesture resets listSelection
        //   synchronously; deferring one run loop tick ensures our value wins.
        // - onChange(of: listSelection): calls selectSidebarOutlineViewRow for native highlight.
        label
            .accessibilityIdentifier(id ?? "")
            .accessibilityValue(listSelection == item ? "1" : "0")
            .tag(item)
            .simultaneousGesture(TapGesture().onEnded {
                applySelection(item)
                let captured = item
                DispatchQueue.main.async {
                    listSelection = captured
                }
            })
    }

    // MARK: - Selection sync

    private func applySelection(_ item: SidebarItem) {
        router.activeSavedSearchID = nil
        switch item {
        case .dashboard:         router.navigateToSection(.dashboard)
        case .needsAction:       router.navigateToSection(.needsAction)
        case .jobsAll:           router.sidebarJobFilter = nil; router.navigateToSection(.jobs)
        case .jobs(let status):  router.sidebarJobFilter = status; router.navigateToSection(.jobs)
        case .sites:             router.navigateToSection(.sites)
        case .duplicates:        router.navigateToSection(.duplicates)
        case .llmQueue:          router.navigateToSection(.llmQueue)
        case .dataQuality:       router.navigateToSection(.dataQuality)
        case .settings:          router.navigateToSection(.settings)
        case .savedSearch(let id):
            router.activeSavedSearchID = id
            router.sidebarJobFilter = nil
            router.navigateToSection(.jobs)
        }
    }

    private func syncSelectionFromRouter() {
        let item: SidebarItem
        switch router.selectedSection {
        case .dashboard:   item = .dashboard
        case .needsAction: item = .needsAction
        case .jobs:
            if let id = router.activeSavedSearchID { item = .savedSearch(id) }
            else if let status = router.sidebarJobFilter { item = .jobs(status) }
            else { item = .jobsAll }
        case .sites:       item = .sites
        case .duplicates:  item = .duplicates
        case .llmQueue:    item = .llmQueue
        case .dataQuality: item = .dataQuality
        case .settings:    item = .settings
        case .help:
            listSelection = nil
            return
        }
        if listSelection != item { listSelection = item }
    }

    // MARK: - Rename sheet

    @ViewBuilder
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

// MARK: - AppKit visual selection helper
//
// macOS 26 regression: List(selection:) binding changes do not update NSOutlineView's
// visual selected-row state. Programmatically calling selectRowIndexes gives the
// native sidebar highlight.
//
// Row indices are computed from the fixed sidebar layout (no text searching needed —
// SwiftUI sidebar labels don't render as NSTextField nodes in the NSView hierarchy).
//
// Sidebar row layout (0-based):
//   0: Dashboard
//   1: Needs Action
//   2: "Jobs" group header
//   3: All Jobs
//   4…13: sidebarStatuses (10 items: New…Expired)
//   [if savedSearchCount > 0]:
//     14: "Saved Searches" group header
//     15…14+N: saved searches
//   14+offset: "Sources" group header   (offset = N+1 if N>0, else 0)
//   15+offset: Sites
//   16+offset: Duplicates
//   17+offset: "Tools" group header
//   18+offset: LLM Queue
//   19+offset: Data Quality
//   20+offset: Settings

private func selectSidebarOutlineViewRow(item: SidebarItem, savedSearchCount: Int) {
    guard let window = NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first(where: { $0.isVisible }),
          let contentView = window.contentView else { return }
    let allOVs = collectOutlineViews(in: contentView)
    guard let sidebarOV = allOVs.min(by: {
        $0.convert($0.bounds.origin, to: nil).x < $1.convert($1.bounds.origin, to: nil).x
    }) else { return }
    let offset = savedSearchCount > 0 ? savedSearchCount + 1 : 0
    guard let row = sidebarRow(for: item, offset: offset), row < sidebarOV.numberOfRows else { return }
    sidebarOV.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
    // Without first-responder status the source-list row renders in the inactive (grey)
    // state. Make the outline view first responder briefly so the selection redraws blue,
    // then hand focus back to the window so keyboard input targets the content area.
    if sidebarOV.window?.firstResponder !== sidebarOV {
        window.makeFirstResponder(sidebarOV)
        DispatchQueue.main.async { window.makeFirstResponder(nil) }
    }
}

private func sidebarRow(for item: SidebarItem, offset: Int) -> Int? {
    switch item {
    case .dashboard:         return 0
    case .needsAction:       return 1
    case .jobsAll:           return 3
    case .jobs(let status):
        guard let idx = sidebarStatuses.firstIndex(of: status) else { return nil }
        return 4 + idx
    case .savedSearch:       return nil  // dynamic position; skip
    case .sites:             return 15 + offset
    case .duplicates:        return 16 + offset
    case .llmQueue:          return 18 + offset
    case .dataQuality:       return 19 + offset
    case .settings:          return 20 + offset
    }
}

private func collectOutlineViews(in view: NSView) -> [NSOutlineView] {
    var result: [NSOutlineView] = []
    if let ov = view as? NSOutlineView { result.append(ov) }
    for sub in view.subviews { result += collectOutlineViews(in: sub) }
    return result
}
