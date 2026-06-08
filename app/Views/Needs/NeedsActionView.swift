import JobhuntCore
import SwiftData
import SwiftUI

// MARK: - Due date bucket

private enum DueBucket: String, CaseIterable {
    case overdue = "Overdue"
    case today = "Today"
    case upcoming = "Upcoming"
    case noDueDate = "No Due Date"
}

private extension JobAction {
    var bucket: DueBucket {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let due = cal.startOfDay(for: dueDate)
        if due < today { return .overdue }
        if due == today { return .today }
        return .upcoming
    }
}

// MARK: - Status filter options

private enum StatusFilterOption: String, CaseIterable, Identifiable {
    case all = "All"
    case active = "Active"
    case applied = "Applied"
    case interview = "Interview"

    var id: String {
        rawValue
    }

    func matches(_ status: JobStatus) -> Bool {
        switch self {
        case .all: true
        case .active: status == .saved
        case .applied: status == .applied
        case .interview: status == .interview
        }
    }
}

// MARK: - Main view

struct NeedsActionView: View {
    @Environment(Router.self) private var router
    @Environment(AppServices.self) private var appServices
    private var jobService: JobService {
        appServices.jobService
    }

    @Query(
        filter: #Predicate<JobAction> { $0.completedAt == nil },
        sort: \JobAction.dueDate
    ) private var actions: [JobAction]

    @State private var searchText: String = ""
    @State private var statusFilter: StatusFilterOption = .all
    @State private var isSnoozeAllConfirming: Bool = false
    @State private var errorMessage: String?

    /// Actions that are not snoozed into the future
    private var activeActions: [JobAction] {
        let now = Date()
        return actions.filter { action in
            if let snoozedUntil = action.snoozedUntil, snoozedUntil > now {
                return false
            }
            return true
        }
    }

    private var filteredActions: [JobAction] {
        activeActions.filter { action in
            guard let job = action.job else { return false }

            // Status filter
            if !statusFilter.matches(job.status) { return false }

            // Search filter
            let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
            if !query.isEmpty {
                let company = (job.company ?? "").lowercased()
                let title = (job.title ?? "").lowercased()
                let note = action.note.lowercased()
                if !company.contains(query) && !title.contains(query) && !note.contains(query) {
                    return false
                }
            }

            return true
        }
    }

    private var overdueActions: [JobAction] {
        filteredActions.filter { $0.bucket == .overdue }
            .sorted { $0.dueDate < $1.dueDate }
    }

    private var todayActions: [JobAction] {
        filteredActions.filter { $0.bucket == .today }
            .sorted { $0.dueDate < $1.dueDate }
    }

    private var upcomingActions: [JobAction] {
        filteredActions.filter { $0.bucket == .upcoming }
            .sorted { $0.dueDate < $1.dueDate }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar

            Divider()

            if activeActions.isEmpty {
                emptyState(
                    icon: "checkmark.circle",
                    title: "No follow-ups",
                    subtitle: "Open a job and use \"Set next action\" to schedule a check-in."
                )
            } else if filteredActions.isEmpty {
                emptyState(
                    icon: "line.3.horizontal.decrease.circle",
                    title: "No results",
                    subtitle: "No follow-ups match the current filters."
                )
            } else {
                List {
                    if !overdueActions.isEmpty {
                        sectionHeader("Overdue", color: .red, count: overdueActions.count)
                        ForEach(overdueActions, id: \.id) { action in
                            ActionRow(action: action)
                                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                    completeButton(for: action)
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    snoozeButton(for: action)
                                    viewJobButton(for: action)
                                }
                                .contextMenu {
                                    contextMenuItems(for: action)
                                }
                        }
                    }

                    if !todayActions.isEmpty {
                        sectionHeader("Today", color: .orange, count: todayActions.count)
                        ForEach(todayActions, id: \.id) { action in
                            ActionRow(action: action)
                                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                    completeButton(for: action)
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    snoozeButton(for: action)
                                    viewJobButton(for: action)
                                }
                                .contextMenu {
                                    contextMenuItems(for: action)
                                }
                        }
                    }

                    if !upcomingActions.isEmpty {
                        sectionHeader("Upcoming", color: .secondary, count: upcomingActions.count)
                        ForEach(upcomingActions, id: \.id) { action in
                            ActionRow(action: action)
                                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                    completeButton(for: action)
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    snoozeButton(for: action)
                                    viewJobButton(for: action)
                                }
                                .contextMenu {
                                    contextMenuItems(for: action)
                                }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .alert("Error", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 8) {
            // Search box
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                TextField("Search follow-ups…", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.subheadline)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            .frame(maxWidth: 240)

            // Status filter picker
            Picker("Status", selection: $statusFilter) {
                ForEach(StatusFilterOption.allCases) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()

            Spacer()

            // Snooze All Overdue button
            if !overdueActions.isEmpty {
                Button {
                    snoozeAllOverdue()
                } label: {
                    Label("Snooze All Overdue", systemImage: "moon.zzz")
                        .font(.subheadline)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Section headers

    private func sectionHeader(_ title: String, color: Color, count: Int) -> some View {
        Section {} header: {
            HStack {
                Image(systemName: "circle.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(color)
                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(count)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
        }
    }

    // MARK: - Swipe / context menu actions

    private func completeButton(for action: JobAction) -> some View {
        Button {
            complete(action)
        } label: {
            Label("Complete", systemImage: "checkmark")
        }
        .tint(.green)
    }

    private func snoozeButton(for action: JobAction) -> some View {
        Button {
            snooze(action)
        } label: {
            Label("Snooze 7d", systemImage: "moon.zzz")
        }
        .tint(.orange)
    }

    private func viewJobButton(for action: JobAction) -> some View {
        Button {
            viewJob(for: action)
        } label: {
            Label("View Job", systemImage: "briefcase")
        }
        .tint(.blue)
    }

    @ViewBuilder
    private func contextMenuItems(for action: JobAction) -> some View {
        Button {
            complete(action)
        } label: {
            Label("Complete", systemImage: "checkmark")
        }

        Button {
            snooze(action)
        } label: {
            Label("Snooze 7 Days", systemImage: "moon.zzz")
        }

        Divider()

        Button {
            viewJob(for: action)
        } label: {
            Label("View Job", systemImage: "briefcase")
        }
    }

    // MARK: - Empty state

    private func emptyState(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.largeTitle)
                .foregroundStyle(.quaternary)
            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }

    // MARK: - Actions

    private func complete(_ action: JobAction) {
        let id = action.id
        Task {
            do {
                try await jobService.completeAction(actionID: id)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func snooze(_ action: JobAction) {
        let id = action.id
        let until = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
        Task {
            do {
                try await jobService.snoozeAction(actionID: id, until: until)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func viewJob(for action: JobAction) {
        if let jobID = action.job?.id {
            router.selectedJobID = jobID
            router.selectedSection = .jobs
        }
    }

    private func snoozeAllOverdue() {
        let ids = overdueActions.map(\.id)
        let until = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
        Task {
            do {
                for id in ids {
                    try await jobService.snoozeAction(actionID: id, until: until)
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - Action row

private struct ActionRow: View {
    let action: JobAction

    private var job: Job? {
        action.job
    }

    private var dueDateText: String {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let due = cal.startOfDay(for: action.dueDate)
        let days = cal.dateComponents([.day], from: today, to: due).day ?? 0

        if days == 0 { return "Today" }
        if days == 1 { return "Tomorrow" }
        if days == -1 { return "Yesterday" }
        if days < 0 { return "\(-days)d overdue" }
        return "in \(days)d"
    }

    private var dueDateColor: Color {
        switch action.bucket {
        case .overdue: .red
        case .today: .orange
        case .upcoming: .secondary
        case .noDueDate: .secondary
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            // Due date badge
            VStack(spacing: 2) {
                Image(systemName: "clock")
                    .font(.caption2)
                Text(dueDateText)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .monospacedDigit()
            }
            .foregroundStyle(dueDateColor)
            .frame(width: 60, alignment: .center)

            // Company + title
            VStack(alignment: .leading, spacing: 2) {
                Text(job?.company ?? "Unknown Company")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Text(job?.title ?? "—")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(minWidth: 120, alignment: .leading)

            // Action note
            Text(action.note)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Status chip
            if let job {
                StatusChip(status: job.status)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Preview

#Preview {
    NeedsActionView()
        .environment(Router())
        .frame(width: 800, height: 600)
}
