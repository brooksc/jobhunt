import SwiftUI
import SwiftData
import JobhuntCore

// MARK: - JobsView

struct JobsView: View {
    @Environment(Router.self) private var router
    @Environment(AppServices.self) private var appServices

    private var jobService: JobService { appServices.jobService }

    @Query(sort: \Job.createdAt, order: .reverse)
    private var allJobs: [Job]

    @State private var filterState = JobsFilterState()
    @State private var selection: Set<String> = []
    @FocusState private var searchFieldFocused: Bool
    @State private var showFilterPopover = false
    @State private var showStatusPicker = false

    // Status filter pills shown at top
    private let statusPills: [(label: String, value: JobStatus?)] = [
        ("All", nil),
        ("Saved", .saved),
        ("Applied", .applied),
        ("Interview", .interview),
        ("Offer", .offer),
        ("Rejected", .rejected)
    ]

    var body: some View {
        VStack(spacing: 0) {
            toolbarBar
            Divider()
            statusPillBar
            Divider()
            jobTable
        }
        .navigationTitle("Jobs")
        .toolbar { batchToolbar }
        .onKeyPress(.init("k")) {
            searchFieldFocused = true
            return .handled
        }
    }

    // MARK: - Search + Filter Bar

    private var toolbarBar: some View {
        HStack(spacing: 8) {
            // Search field
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                TextField("Search company, title, location, #id…", text: $filterState.searchText)
                    .textFieldStyle(.plain)
                    .focused($searchFieldFocused)
                    .font(.callout)
                if !filterState.searchText.isEmpty {
                    Button {
                        filterState.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                Text("⌘K")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // Filter button
            Button {
                showFilterPopover.toggle()
            } label: {
                Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
                    .font(.callout)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .popover(isPresented: $showFilterPopover) {
                filterPopover
            }

            Spacer()

            Text("\(filteredJobs.count) job\(filteredJobs.count == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Status Pill Bar

    private var statusPillBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(statusPills, id: \.label) { pill in
                    Button {
                        if let status = pill.value {
                            if filterState.statusFilter == [status] {
                                filterState.statusFilter = nil
                            } else {
                                filterState.statusFilter = [status]
                            }
                        } else {
                            filterState.statusFilter = nil
                        }
                    } label: {
                        Text(pill.label)
                            .font(.caption)
                            .fontWeight(.medium)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(pillIsActive(pill) ? Theme.accent : Color.secondary.opacity(0.12))
                            .foregroundStyle(pillIsActive(pill) ? .white : .primary)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
    }

    private func pillIsActive(_ pill: (label: String, value: JobStatus?)) -> Bool {
        if pill.value == nil {
            return filterState.statusFilter == nil
        }
        return filterState.statusFilter == [pill.value!]
    }

    // MARK: - Table

    private var jobTable: some View {
        Table(filteredJobs, selection: $selection) {
            TableColumn("#") { job in
                Text(job.jobNumber.map { "#\($0)" } ?? "—")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            .width(min: 44, ideal: 56, max: 64)

            TableColumn("Status") { job in
                StatusChip(status: job.status)
            }
            .width(min: 80, ideal: 100, max: 120)

            TableColumn("Company") { job in
                Text(job.company ?? "—")
                    .lineLimit(1)
                    .fontWeight(job.unread ? .semibold : .regular)
            }
            .width(min: 100, ideal: 150)

            TableColumn("Title") { job in
                HStack(spacing: 4) {
                    if job.unread {
                        Circle()
                            .fill(Theme.accent)
                            .frame(width: 6, height: 6)
                    }
                    Text(job.title ?? "—")
                        .lineLimit(1)
                        .fontWeight(job.unread ? .semibold : .regular)
                }
            }
            .width(min: 150, ideal: 220)

            TableColumn("Location") { job in
                Text(job.location ?? "—")
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            }
            .width(min: 80, ideal: 140)

            TableColumn("Remote") { job in
                remoteLabel(job.remoteType)
            }
            .width(min: 60, ideal: 80, max: 100)

            TableColumn("Salary") { job in
                salaryText(job)
            }
            .width(min: 60, ideal: 90, max: 110)

            TableColumn("Fit") { job in
                if let score = job.fitScore {
                    Text("\(score)")
                        .font(.caption.monospaced())
                        .fontWeight(.semibold)
                        .foregroundStyle(fitColor(score))
                } else {
                    Text("—")
                        .font(.caption.monospaced())
                        .foregroundStyle(.tertiary)
                }
            }
            .width(min: 36, ideal: 46, max: 56)

            TableColumn("Rating") { job in
                ratingView(job.rating)
            }
            .width(min: 60, ideal: 80, max: 90)

            TableColumn("Captured") { job in
                Text(relativeDate(job.createdAt))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            .width(min: 70, ideal: 90, max: 110)
        }
        .onChange(of: selection) { _, newValue in
            guard newValue.count == 1,
                  let jobID = newValue.first,
                  let job = allJobs.first(where: { $0.id == jobID })
            else { return }
            router.selectedJobID = job.id
            Task {
                try? await jobService.markOpened(jobID: job.id)
            }
        }
    }

    // MARK: - Batch Toolbar

    @ToolbarContentBuilder
    private var batchToolbar: some ToolbarContent {
        if !selection.isEmpty {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    showStatusPicker = true
                } label: {
                    Label("Set Status", systemImage: "tag")
                }
                .help("Change status for \(selection.count) selected job\(selection.count == 1 ? "" : "s")")
                .popover(isPresented: $showStatusPicker) {
                    statusPickerPopover
                }

                Button {
                    Task { await queueAI() }
                } label: {
                    Label("Queue AI", systemImage: "cpu")
                }
                .help("Queue LLM extraction for \(selection.count) selected job\(selection.count == 1 ? "" : "s")")

                Button(role: .destructive) {
                    Task { await deleteSelected() }
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .help("Delete \(selection.count) selected job\(selection.count == 1 ? "" : "s")")

                Button {
                    selection.removeAll()
                } label: {
                    Label("Clear Selection", systemImage: "xmark.circle")
                }
                .help("Clear selection")
            }
        }
    }

    // MARK: - Popovers

    private var filterPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sort")
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("Sort by", selection: $filterState.sortKey) {
                ForEach(JobsSortKey.allCases, id: \.self) { key in
                    Text(key.displayName).tag(key)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()

            Toggle(filterState.sortAscending ? "Ascending" : "Descending",
                   isOn: $filterState.sortAscending)
                .font(.callout)
        }
        .padding(16)
        .frame(minWidth: 200)
    }

    private var statusPickerPopover: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Set status to:")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 10)
            ForEach(JobStatus.allCases, id: \.self) { status in
                Button {
                    let ids = selectedStringIDs
                    Task {
                        try? await jobService.setStatusBulk(status, jobIDs: ids)
                    }
                    showStatusPicker = false
                    selection.removeAll()
                } label: {
                    HStack {
                        StatusChip(status: status)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }
            Spacer().frame(height: 6)
        }
        .frame(minWidth: 160)
    }

    // MARK: - Computed

    private var filteredJobs: [Job] {
        let base = allJobs.filter { job in
            // Status filter
            if let statuses = filterState.statusFilter {
                guard statuses.contains(job.status) else { return false }
            }
            // Also respect router.statusFilter (sidebar quick-filter)
            if let routerFilter = router.statusFilter,
               let status = JobStatus(rawValue: routerFilter) {
                guard job.status == status else { return false }
            }
            // Search text
            let q = filterState.searchText.trimmingCharacters(in: .whitespaces)
            if !q.isEmpty {
                let qLow = q.lowercased()
                let matchNum = qLow.hasPrefix("#") ? String(qLow.dropFirst()) : qLow
                let textMatch = [job.company, job.title, job.location]
                    .compactMap { $0 }
                    .joined(separator: " ")
                    .lowercased()
                    .contains(qLow)
                let numMatch = job.jobNumber.map { String($0).contains(matchNum) } ?? false
                if !textMatch && !numMatch { return false }
            }
            return true
        }
        return JobsSortLogic.sorted(base, key: filterState.sortKey, ascending: filterState.sortAscending)
    }

    // MARK: - Batch Actions

    /// Returns the string job IDs for currently selected jobs.
    private var selectedStringIDs: [String] {
        Array(selection)
    }

    private func queueAI() async {
        let ids = selectedStringIDs
        try? await jobService.enqueueLLM(jobIDs: ids, mode: .extract)
        selection.removeAll()
    }

    private func deleteSelected() async {
        let ids = selectedStringIDs
        for id in ids {
            try? await jobService.delete(jobID: id)
        }
        selection.removeAll()
    }

    // MARK: - Helpers

    @ViewBuilder
    private func remoteLabel(_ type: RemoteType?) -> some View {
        switch type {
        case .remote:
            Text("Remote").font(.caption).foregroundStyle(.green)
        case .hybrid:
            Text("Hybrid").font(.caption).foregroundStyle(.orange)
        case .onsite:
            Text("Onsite").font(.caption).foregroundStyle(.secondary)
        case .unknown, nil:
            Text("—").font(.caption).foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private func salaryText(_ job: Job) -> some View {
        let parts: [String] = [job.salaryMin.map { formatSalary($0) }, job.salaryMax.map { formatSalary($0) }].compactMap { $0 }
        if parts.isEmpty {
            if let note = job.salaryNote {
                Text(note).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            } else {
                Text("—").font(.caption.monospaced()).foregroundStyle(.tertiary)
            }
        } else {
            Text(parts.joined(separator: "–")).font(.caption.monospaced()).foregroundStyle(.secondary)
        }
    }

    private func formatSalary(_ value: Int) -> String {
        value >= 1000 ? "$\(value / 1000)k" : "$\(value)"
    }

    @ViewBuilder
    private func ratingView(_ rating: Int?) -> some View {
        if let rating, rating > 0 {
            HStack(spacing: 2) {
                ForEach(1...5, id: \.self) { i in
                    Image(systemName: i <= rating ? "star.fill" : "star")
                        .font(.system(size: 9))
                        .foregroundStyle(i <= rating ? Color.yellow : Color.secondary.opacity(0.3))
                }
            }
        } else {
            Text("—").font(.caption).foregroundStyle(.tertiary)
        }
    }

    private func fitColor(_ score: Int) -> Color {
        if score >= 75 { return .green }
        if score >= 50 { return .yellow }
        return .red
    }

    private func relativeDate(_ date: Date) -> String {
        let calendar = Calendar.current
        let now = Date()
        let components = calendar.dateComponents([.day, .hour, .minute], from: date, to: now)
        if let days = components.day, days > 0 {
            return days == 1 ? "1d ago" : "\(days)d ago"
        }
        if let hours = components.hour, hours > 0 {
            return "\(hours)h ago"
        }
        if let minutes = components.minute, minutes > 0 {
            return "\(minutes)m ago"
        }
        return "just now"
    }
}

// MARK: - Sort key display names

private extension JobsSortKey {
    var displayName: String {
        switch self {
        case .jobNumber: return "Job #"
        case .company: return "Company"
        case .title: return "Title"
        case .status: return "Status"
        case .fitScore: return "Fit Score"
        case .rating: return "Rating"
        case .capturedAt: return "Date Captured"
        case .extractedAt: return "Date Extracted"
        }
    }
}

// Preview requires a real ModelContainer so is omitted here.
