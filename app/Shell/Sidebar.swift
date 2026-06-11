import JobhuntCore
import SwiftData
import SwiftUI

// MARK: - Sidebar statuses shown as smart folders
private let sidebarStatuses: [JobStatus] = [.new, .pursuing, .applied, .interview, .offer, .rejected, .passed, .closed, .expired]

struct Sidebar: View {
    var router: Router

    @Environment(\.modelContext) private var modelContext

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
            Button { listSelection = .dashboard } label: {
                Label("Dashboard", systemImage: "chart.bar")
            }
            .buttonStyle(.plain)
            .tag(SidebarItem.dashboard)
            .accessibilityIdentifier("sidebar.dashboard")
            .help("Overview and stats")

            Button { listSelection = .needsAction } label: {
                Label("Needs Action", systemImage: "bell")
            }
            .buttonStyle(.plain)
            .tag(SidebarItem.needsAction)
            .badge(pendingActions.isEmpty ? 0 : pendingActions.count)
            .accessibilityIdentifier("sidebar.needsAction")
            .help("Jobs with pending follow-up")

            Section("Jobs") {
                Button { listSelection = .jobsAll } label: {
                    Label("All Jobs", systemImage: "tray.2")
                }
                .buttonStyle(.plain)
                .tag(SidebarItem.jobsAll)
                .badge(allJobs.count)
                .accessibilityIdentifier("sidebar.jobs.all")
                .help("All captured jobs")

                ForEach(sidebarStatuses, id: \.self) { status in
                    let count = allJobs.filter { $0.status == status }.count
                    Button { listSelection = .jobs(status) } label: {
                        Label(status.displayName, systemImage: Theme.statusSymbol(status))
                    }
                    .buttonStyle(.plain)
                    .tag(SidebarItem.jobs(status))
                    .badge(count)
                    .accessibilityIdentifier("sidebar.jobs.\(status.rawValue)")
                    .help("Jobs with status: \(status.displayName)")
                }
            }

            if !savedSearches.isEmpty {
                Section("Saved Searches") {
                    ForEach(savedSearches) { search in
                        let count = allJobs.filter { search.matches($0) }.count
                        Button { listSelection = .savedSearch(search.id) } label: {
                            Label(search.name, systemImage: "pin")
                        }
                        .buttonStyle(.plain)
                        .tag(SidebarItem.savedSearch(search.id))
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
                Button { listSelection = .sites } label: {
                    Label("Sites", systemImage: "globe")
                }
                .buttonStyle(.plain)
                .tag(SidebarItem.sites)
                .accessibilityIdentifier("sidebar.sites")
                .help("Job listing sources")

                Button { listSelection = .duplicates } label: {
                    Label("Duplicates", systemImage: "doc.on.doc")
                }
                .buttonStyle(.plain)
                .tag(SidebarItem.duplicates)
                .badge(duplicateJobs.isEmpty ? 0 : duplicateJobs.count)
                .accessibilityIdentifier("sidebar.duplicates")
                .help("Duplicate job postings")
            }

            Section("Tools") {
                Button { listSelection = .llmQueue } label: {
                    Label("LLM Queue", systemImage: "cpu")
                }
                .buttonStyle(.plain)
                .tag(SidebarItem.llmQueue)
                .accessibilityIdentifier("sidebar.llmQueue")
                .help("LLM processing queue status")

                Button { listSelection = .dataQuality } label: {
                    Label("Data Quality", systemImage: "checkmark.shield")
                }
                .buttonStyle(.plain)
                .tag(SidebarItem.dataQuality)
                .accessibilityIdentifier("sidebar.dataQuality")
                .help("Data quality issues")

                Button { listSelection = .settings } label: {
                    Label("Settings", systemImage: "gear")
                }
                .buttonStyle(.plain)
                .tag(SidebarItem.settings)
                .accessibilityIdentifier("sidebar.settings")
                .help("App settings")
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
                    modelContext.delete(search)
                    searchToDelete = nil
                }
            }
            Button("Cancel", role: .cancel) { searchToDelete = nil }
        }
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
