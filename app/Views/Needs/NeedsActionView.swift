import JobhuntCore
import SwiftData
import SwiftUI

// MARK: - Due date bucket

private enum DueBucket: String, CaseIterable {
    case overdue = "Overdue"
    case today = "Today"
    case thisWeek = "This week"
    case later = "Later"
}

private extension JobAction {
    var bucket: DueBucket {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let due = cal.startOfDay(for: dueDate)
        let days = cal.dateComponents([.day], from: today, to: due).day ?? 0
        if due < today { return .overdue }
        if due == today { return .today }
        if days <= 7 { return .thisWeek }
        return .later
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
        case .active: status == .pursuing
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

    @Query private var allJobs: [Job]
    @Query private var allInterviews: [InterviewRecord]
    @Query private var allOffers: [OfferRecord]

    @State private var searchText: String = ""
    @State private var statusFilter: StatusFilterOption = .all
    @State private var isSnoozeAllConfirming: Bool = false
    @State private var errorMessage: String?

    private var jobsByID: [String: Job] {
        Dictionary(allJobs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// Upcoming interviews (soonest first), terminal jobs excluded — same rules as the Dashboard card
    /// via `MilestoneSchedule`, so the two can't drift (TASK-646).
    private var scheduledInterviews: [(job: Job, record: InterviewRecord)] {
        let byID = jobsByID
        let projected = allInterviews.compactMap { record -> MilestoneSchedule.Interview? in
            guard let job = byID[record.jobID] else { return nil }
            return .init(
                jobID: record.jobID, scheduledAt: record.scheduledAt,
                kind: InterviewKind(rawValue: record.kind) ?? .other,
                interviewer: record.interviewer, jobIsTerminal: job.status.isTerminal
            )
        }
        return MilestoneSchedule.upcomingInterviews(projected, now: Date()).compactMap { entry in
            guard let job = byID[entry.jobID],
                  let record = allInterviews.first(where: {
                      $0.jobID == entry.jobID && $0.scheduledAt == entry.scheduledAt
                  })
            else { return nil }
            return (job, record)
        }
    }

    private var offerDeadlines: [(job: Job, record: OfferRecord)] {
        let byID = jobsByID
        let projected = allOffers.compactMap { record -> MilestoneSchedule.OfferDeadline? in
            guard let job = byID[record.jobID], let decisionBy = record.decisionBy else { return nil }
            return .init(
                jobID: record.jobID, decisionBy: decisionBy,
                title: record.title, jobIsTerminal: job.status.isTerminal
            )
        }
        return MilestoneSchedule.offerDeadlines(projected, now: Date()).compactMap { entry in
            guard let job = byID[entry.jobID],
                  let record = allOffers.first(where: { $0.jobID == entry.jobID })
            else { return nil }
            return (job, record)
        }
    }

    private var hasScheduledMilestones: Bool {
        !scheduledInterviews.isEmpty || !offerDeadlines.isEmpty
    }

    /// Actionable follow-ups: incomplete, not snoozed into the future, linked to a job. Uses the
    /// shared predicate so this list, the sidebar badge, Dashboard, and export can't drift (TASK-576).
    private var activeActions: [JobAction] {
        let now = Date()
        return actions.filter { FollowUpVisibility.isActionable($0, now: now) }
    }

    private var filteredActions: [JobAction] {
        activeActions.filter { action in
            guard let job = action.job else { return false }

            // Status filter
            if !statusFilter.matches(job.status) { return false }

            // Search filter
            let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
            if !query.isEmpty {
                let company = (job.displayCompany ?? "").lowercased()
                let title = job.displayTitle.lowercased()
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

    private var thisWeekActions: [JobAction] {
        filteredActions.filter { $0.bucket == .thisWeek }
            .sorted { $0.dueDate < $1.dueDate }
    }

    private var laterActions: [JobAction] {
        filteredActions.filter { $0.bucket == .later }
            .sorted { $0.dueDate < $1.dueDate }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar

            Divider()

            if activeActions.isEmpty, !hasScheduledMilestones {
                emptyState(
                    icon: "checkmark.circle",
                    title: "No follow-ups",
                    subtitle: "Open a job and use \"Set next action\" to schedule a check-in."
                )
            } else if filteredActions.isEmpty, !hasScheduledMilestones {
                emptyState(
                    icon: "line.3.horizontal.decrease.circle",
                    title: "No results",
                    subtitle: "No follow-ups match the current filters."
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        NeedsActionMilestonesSection(
                            interviews: scheduledInterviews,
                            offers: offerDeadlines,
                            onSelectJob: { id in
                                router.selectedJobID = id
                                router.selectedSection = .jobs
                            }
                        )
                        if !overdueActions.isEmpty {
                            needsGroup(label: "Overdue", icon: "clock", color: .red, actions: overdueActions)
                        }
                        if !todayActions.isEmpty {
                            needsGroup(label: "Today", icon: "scope", color: .orange, actions: todayActions)
                        }
                        if !thisWeekActions.isEmpty {
                            needsGroup(
                                label: "This week",
                                icon: "calendar",
                                color: .accentColor,
                                actions: thisWeekActions
                            )
                        }
                        if !laterActions.isEmpty {
                            needsGroup(label: "Later", icon: "flag", color: .secondary, actions: laterActions)
                        }
                    }
                    .padding(16)
                }
            }
        }
        .navigationTitle("Needs Action")
        .alert(
            "Action Failed",
            isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
        ) {
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
                    .help("Clear search")
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
                    isSnoozeAllConfirming = true
                } label: {
                    Label("Snooze \(overdueActions.count) Overdue", systemImage: "moon.zzz")
                        .font(.subheadline)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.small)
                .confirmationDialog(
                    "Snooze Overdue Actions",
                    isPresented: $isSnoozeAllConfirming,
                    titleVisibility: .visible
                ) {
                    Button("Snooze All (\(overdueActions.count))", role: .destructive) {
                        snoozeAllOverdue()
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    let filterNote = (statusFilter != .all || !searchText.isEmpty) ? " matching the current filter" : ""
                    Text(
                        "Snooze all \(overdueActions.count) overdue follow-up\(overdueActions.count == 1 ? "" : "s")" +
                            "\(filterNote) for 7 days?"
                    )
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Group section

    private func needsGroup(label: String, icon: String, color: Color, actions: [JobAction]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Section header
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(color)
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                Text("\(actions.count)")
                    .font(.caption2.monospacedDigit())
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(color.opacity(0.12))
                    .foregroundStyle(color)
                    .clipShape(Capsule())
            }

            // Card
            VStack(spacing: 0) {
                ForEach(actions, id: \.id) { action in
                    NeedsActionRow(action: action) {
                        complete(action)
                    } onSnooze: { days in
                        snooze(action, days: days)
                    } onSelectJob: {
                        viewJob(for: action)
                    } onAddNote: { text in
                        addNote(text, for: action)
                    }
                    if action.id != actions.last?.id {
                        Divider()
                    }
                }
            }
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.12), lineWidth: 0.5))
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
                appServices.toastStore.show("Follow-up marked done.", actionLabel: "Undo") {
                    Task {
                        do { try await jobService.reopenAction(actionID: id) } catch {
                            appServices.toastStore.show("Couldn't undo: \(error.localizedDescription)", isError: true)
                        }
                    }
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func snooze(_ action: JobAction, days: Int) {
        let id = action.id
        let until = Calendar.current.date(byAdding: .day, value: days, to: Date()) ?? Date()
        Task {
            do {
                try await jobService.snoozeAction(actionID: id, until: until)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func addNote(_ text: String, for action: JobAction) {
        guard let jobID = action.job?.id else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        Task {
            do {
                try await jobService.addNote(trimmed, to: jobID)
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

// MARK: - Needs action row

private struct NeedsActionRow: View {
    let action: JobAction
    let onDone: () -> Void
    /// Days from today. A count rather than a date because every caller but the custom picker
    /// thinks in intervals, and the picker converts (see `SnoozeDefaults.days(until:)`).
    let onSnooze: (Int) -> Void
    let onSelectJob: () -> Void
    let onAddNote: (String) -> Void

    @State private var showNotePopover = false
    @State private var noteText = ""
    @State private var showCustomSnooze = false
    @State private var customSnoozeDate = Date()

    /// Pick a return date directly. Converted to a day count so it goes through exactly the same
    /// snooze path as the fixed intervals — a second write path for the same action is how the two
    /// would drift.
    private var customSnoozePopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            DatePicker(
                "Snooze until",
                selection: $customSnoozeDate,
                in: Date()...,
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            HStack {
                Spacer()
                Button("Cancel") { showCustomSnooze = false }
                Button("Snooze") {
                    onSnooze(SnoozeDefaults.days(until: customSnoozeDate))
                    showCustomSnooze = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
    }

    private var job: Job? {
        action.job
    }

    private var dueDateLabel: String {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let due = cal.startOfDay(for: action.dueDate)
        let days = cal.dateComponents([.day], from: today, to: due).day ?? 0
        if days < 0 { return "\(-days)d overdue" }
        if days == 0 { return "Today" }
        if days == 1 { return "Tomorrow" }
        return "in \(days)d"
    }

    private var dueDateColor: Color {
        switch action.bucket {
        case .overdue: .red
        case .today: .orange
        case .thisWeek: .accentColor
        case .later: .secondary
        }
    }

    var body: some View {
        Button(action: onSelectJob) {
            HStack(spacing: 12) {
                // Due date column (fixed 96pt)
                Text(dueDateLabel)
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(dueDateColor)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(dueDateColor.opacity(0.1))
                    .clipShape(Capsule())
                    .frame(width: 96, alignment: .center)

                // Company mark
                CompanyMarkView(name: job?.company, size: 22)

                // Action note + subtitle
                VStack(alignment: .leading, spacing: 1) {
                    Text(action.note)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    HStack(spacing: 3) {
                        Text(job?.displayCompany ?? "—")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("·")
                            .font(.caption2)
                            .foregroundStyle(.quaternary)
                        Text(job?.displayTitle ?? "—")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Status
                if let job {
                    StatusChip(status: job.status)
                }

                // Inline Note + Done + Snooze
                HStack(spacing: 4) {
                    Button {
                        showNotePopover = true
                    } label: {
                        Image(systemName: "note.text").font(.system(size: 12))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Add a note to this job")
                    .popover(isPresented: $showNotePopover) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Add note").font(.caption.weight(.semibold))
                            TextField("Note…", text: $noteText, axis: .vertical)
                                .textFieldStyle(.roundedBorder)
                                .lineLimit(2 ... 5)
                                .frame(width: 240)
                            HStack {
                                Spacer()
                                Button("Save") {
                                    onAddNote(noteText)
                                    noteText = ""
                                    showNotePopover = false
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                                .disabled(noteText.trimmingCharacters(in: .whitespaces).isEmpty)
                            }
                        }
                        .padding(12)
                    }

                    Button {
                        onDone()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .semibold))
                            Text("Done")
                                .font(.caption)
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Menu {
                        Button("3 days") { onSnooze(3) }
                        Button("1 week") { onSnooze(7) }
                        Button("2 weeks") { onSnooze(14) }
                        Button("1 month") { onSnooze(30) }
                        Divider()
                        // TASK-502 #1: the fixed intervals cover the common cases but not "they said
                        // they'd get back to me after the 14th", which is the whole reason to snooze.
                        Button("Custom date…") {
                            customSnoozeDate = SnoozeDefaults.defaultCustomDate()
                            showCustomSnooze = true
                        }
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 12))
                    }
                    .menuStyle(.button)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("Snooze…")
                    .popover(isPresented: $showCustomSnooze) {
                        customSnoozePopover
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview {
    NeedsActionView()
        .environment(Router())
        .frame(width: 800, height: 600)
}
