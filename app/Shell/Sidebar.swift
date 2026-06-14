import JobhuntCore
import SwiftData
import SwiftUI

// MARK: - Sidebar statuses shown as smart folders
private let sidebarStatuses: [JobStatus] = [.new, .pursuing, .applied, .interview, .offer, .rejected, .passed, .archived, .closed, .expired]

// Selected-row highlight (drawn manually because macOS 26's List(.sidebar) selection
// highlight doesn't render — see sidebarRow).
private let sidebarSelectionColor = Color(red: 0.0, green: 0.32, blue: 0.75)

struct Sidebar: View {
    var router: Router

    @Environment(AppServices.self) private var appServices

    @Query(filter: #Predicate<JobAction> { $0.completedAt == nil }) private var pendingActions: [JobAction]
    @Query(filter: #Predicate<Job> { $0.duplicateOfJobID != nil }) private var duplicateJobs: [Job]
    @Query private var allJobs: [Job]
    @Query(sort: \SavedSearch.sortOrder) private var savedSearches: [SavedSearch]

    @State private var listSelection: SidebarItem? = .jobsAll
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

                sidebarRow(.help, id: "sidebar.help",
                           label: Label("Help", systemImage: "questionmark.circle"))
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
        case .help:              router.navigateToSection(.help)
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
        case .help:        item = .help
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
