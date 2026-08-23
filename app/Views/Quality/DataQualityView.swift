import AppKit
import JobhuntCore
import SwiftData
import SwiftUI

// MARK: - DataQualityView

struct DataQualityView: View {
    @Environment(Router.self) private var router
    @Environment(AppServices.self) private var appServices

    @Query(sort: \Job.createdAt, order: .reverse)
    private var allJobs: [Job]

    @State private var selectedJobIDs: Set<String> = []
    @State private var filterKind: QualityIssueKind? // nil = all
    @State private var showReviewed = false
    @State private var errorMessage: String?

    // MARK: - Derived data

    private var issueRows: [(job: Job, issue: QualityIssue)] {
        // Shared inclusion policy with the dashboard quality count (TASK-580).
        allJobs.compactMap { job in
            guard DataQualityScope.isIncluded(
                status: job.status, hasReview: job.qualityReview != nil, showReviewed: showReviewed
            ) else { return nil }
            let kinds = QualityChecker.issues(for: job)
            guard !kinds.isEmpty else { return nil }
            return (job, QualityIssue(jobID: job.id, kinds: kinds))
        }
    }

    private var filteredRows: [(job: Job, issue: QualityIssue)] {
        guard let kind = filterKind else { return issueRows }
        return issueRows.filter { $0.issue.kinds.contains(kind) }
    }

    private var groupedByKind: [(kind: QualityIssueKind, rows: [(job: Job, issue: QualityIssue)])] {
        guard filterKind == nil else { return [] }
        var dict: [QualityIssueKind: [(job: Job, issue: QualityIssue)]] = [:]
        for row in issueRows {
            for kind in row.issue.kinds {
                dict[kind, default: []].append(row)
            }
        }
        return QualityIssueKind.allCases.compactMap { kind in
            guard let rows = dict[kind], !rows.isEmpty else { return nil }
            return (kind, rows)
        }
    }

    // TASK-457: distinguish jobs-with-issues from total issue occurrences. issueRows has one row
    // per job with ≥1 issue, so its count is JOBS, not issues.
    private var jobsWithIssuesCount: Int {
        issueRows.count
    }

    private var totalIssueOccurrences: Int {
        issueRows.reduce(0) { $0 + $1.issue.kinds.count }
    }

    // TASK-458: high severity means the job has a high-severity issue KIND, not "3+ issues".
    private var highSeverityCount: Int {
        issueRows.count(where: { $0.issue.isHighSeverity })
    }

    private func kindCount(_ kind: QualityIssueKind) -> Int {
        issueRows.count(where: { $0.issue.kinds.contains(kind) })
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            summaryHeader
            Divider()
            filterBar
            Divider()
            jobList
        }
        .accessibilityIdentifier("content.dataQuality")
        .navigationTitle("Data Quality")
        .toolbar { toolbarContent }
        .onChange(of: filterKind) { _, _ in selectedJobIDs = [] }
        .onChange(of: showReviewed) { _, _ in selectedJobIDs = [] }
        .alert("Action Failed", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .focusedSceneValue(\.qualityCommands, QualityCommandHandlers(
            hasSelection: !selectedJobIDs.isEmpty,
            markReviewed: markReviewedSelected,
            queueReextraction: queueReextractionSelected
        ))
    }

    // MARK: - Summary header

    private var summaryHeader: some View {
        HStack(spacing: 16) {
            summaryMetric(label: "Jobs with issues", value: jobsWithIssuesCount, warning: jobsWithIssuesCount > 0)
            Divider().frame(height: 32)
            summaryMetric(label: "Total issues", value: totalIssueOccurrences, warning: totalIssueOccurrences > 0)
            Divider().frame(height: 32)
            summaryMetric(label: "High severity", value: highSeverityCount, warning: highSeverityCount > 0)
            Divider().frame(height: 32)
            summaryMetric(
                label: "Extraction failed",
                value: kindCount(.extractionFailed),
                warning: true
            )
            Divider().frame(height: 32)
            summaryMetric(
                label: "Missing location",
                value: kindCount(.missingLocation),
                warning: false
            )
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func summaryMetric(label: String, value: Int, warning: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundStyle(warning && value > 0 ? Color.orange : Color.primary)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Filter bar

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                filterChip(label: "All (\(issueRows.count))", isActive: filterKind == nil) {
                    filterKind = nil
                }
                ForEach(QualityIssueKind.allCases, id: \.self) { kind in
                    let count = kindCount(kind)
                    if count > 0 {
                        filterChip(label: "\(kind.label) (\(count))", isActive: filterKind == kind) {
                            filterKind = filterKind == kind ? nil : kind
                        }
                        .accessibilityIdentifier("chip.kind.\(kind.rawValue)")
                    }
                }
                Toggle("Show Reviewed", isOn: $showReviewed)
                    .toggleStyle(.checkbox)
                    .font(.caption)
                    .padding(.leading, 8)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    private func filterChip(label: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.caption)
                .fontWeight(isActive ? .semibold : .regular)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(isActive ? Theme.accent.opacity(0.15) : Color.clear)
                .foregroundStyle(isActive ? Theme.accent : Color.secondary)
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(
                    isActive ? Theme.accent.opacity(0.4) : Color.secondary.opacity(0.3),
                    lineWidth: 1
                ))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label.components(separatedBy: " (").first ?? label)
        .accessibilityAddTraits(isActive ? .isSelected : [])
        .accessibilityValue(isActive ? "on" : "off")
    }

    // MARK: - Job list

    @ViewBuilder
    private var jobList: some View {
        if filteredRows.isEmpty {
            ContentUnavailableView(
                "No Data Quality Issues",
                systemImage: "checkmark.shield",
                description: Text(filterKind == nil
                    ? "All jobs have complete data."
                    : "No jobs match this filter.")
            )
        } else if filterKind != nil {
            List(selection: Binding(
                get: { selectedJobIDs },
                set: { selectedJobIDs = $0 }
            )) {
                ForEach(filteredRows, id: \.job.id) { row in
                    jobRow(row.job, issue: row.issue)
                        .tag(row.job.id)
                }
            }
            .listStyle(.inset)
        } else {
            List(selection: Binding(
                get: { selectedJobIDs },
                set: { selectedJobIDs = $0 }
            )) {
                ForEach(groupedByKind, id: \.kind) { group in
                    Section(group.kind.label) {
                        ForEach(group.rows, id: \.job.id) { row in
                            jobRow(row.job, issue: row.issue)
                                .tag(row.job.id)
                        }
                    }
                }
            }
            .listStyle(.inset)
        }
    }

    private func jobRow(_ job: Job, issue: QualityIssue) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(job.company ?? "—")
                        .fontWeight(.medium)
                        .lineLimit(1)
                    if let title = job.title {
                        Text("·")
                            .foregroundStyle(.secondary)
                        Text(title)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    if let urlStr = job.capture?.url ?? job.applicationURL, let url = URL(string: urlStr) {
                        Button { NSWorkspace.shared.open(url) } label: {
                            Image(systemName: "arrow.up.right.square").font(.caption2)
                        }
                        .buttonStyle(.borderless)
                        .help("Open source posting")
                    }
                    // Re-extraction is the only fix the screen used to offer, and on a posting whose
                    // source URL is dead it re-fails every time — leaving Mark Reviewed, which just
                    // hides the row. Typing the missing field in is the fix in those cases (TASK-503 #2).
                    if !QuickFixField.fields(for: issue.kinds).isEmpty {
                        QuickFixButton(job: job, kinds: issue.kinds)
                    }
                    Button { rerun(job) } label: {
                        Image(systemName: "arrow.clockwise").font(.caption2)
                    }
                    .buttonStyle(.borderless)
                    .help("Re-run AI extraction")
                    StatusChip(status: job.status)
                    if job.qualityReview != nil {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(.green)
                            .help("Marked reviewed")
                    }
                }
                issueChips(issue.kinds)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            router.selectedJobID = job.id
            router.navigateToSection(.jobs)
        }
    }

    private func issueChips(_ kinds: [QualityIssueKind]) -> some View {
        FlowLayout(spacing: 4) {
            ForEach(kinds, id: \.self) { kind in
                Text(kind.label)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(kind.isHighSeverity ? Color.red.opacity(0.12) : Color.orange.opacity(0.1))
                    // The label reads in the primary colour, not the accent one. Orange text on a
                    // pale orange tint is ~2:1 — the accessibility audit reported 86 contrast
                    // failures on this screen, essentially all of them these chips (TASK-689).
                    // Severity is still carried by the tint and the border, which are decoration
                    // either way; the word itself has to be readable.
                    .foregroundStyle(Color.primary)
                    .clipShape(Capsule())
                    .overlay(Capsule().strokeBorder(
                        kind.isHighSeverity ? Color.red.opacity(0.3) : Color.orange.opacity(0.25),
                        lineWidth: 0.5
                    ))
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if !selectedJobIDs.isEmpty {
                Text("\(selectedJobIDs.count) selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("Mark Reviewed") {
                    markReviewedSelected()
                }

                Button("Clear Review") {
                    clearReviewSelected()
                }

                Button("Queue Re-extraction") {
                    queueReextractionSelected()
                }
                .keyboardShortcut("r", modifiers: [.command])
            }
        }
    }

    // MARK: - Actions (routed through JobService)

    private func markReviewedSelected() {
        let ids = Array(selectedJobIDs)
        selectedJobIDs = []
        let svc = appServices.jobService
        Task {
            do {
                for id in ids {
                    try await svc.markDataQualityReviewed(jobID: id, notes: nil)
                }
            } catch {
                await MainActor.run { errorMessage = error.localizedDescription }
            }
        }
    }

    private func clearReviewSelected() {
        let ids = Array(selectedJobIDs)
        selectedJobIDs = []
        let svc = appServices.jobService
        Task {
            do {
                for id in ids {
                    try await svc.clearDataQualityReview(jobID: id)
                }
            } catch {
                await MainActor.run { errorMessage = error.localizedDescription }
            }
        }
    }

    private func queueReextractionSelected() {
        let ids = Array(selectedJobIDs)
        selectedJobIDs = []
        let svc = appServices.jobService
        let queue = appServices.queueActor
        Task {
            do {
                try await svc.resetExtractionBulk(jobIDs: ids)
                await queue.startProcessing()
            } catch {
                await MainActor.run { errorMessage = error.localizedDescription }
            }
        }
    }

    private func rerun(_ job: Job) {
        let id = job.id
        let svc = appServices.jobService
        let queue = appServices.queueActor
        Task {
            do {
                try await svc.resetExtractionBulk(jobIDs: [id])
                await queue.startProcessing()
            } catch {
                await MainActor.run { errorMessage = error.localizedDescription }
            }
        }
    }
}

// MARK: - FlowLayout (wrapping HStack for issue chips)

// MARK: - Quick fix

/// Fills in a missing company/title/location without leaving the screen (TASK-503 #2).
///
/// Re-extraction, the screen's only previous remedy, re-fails identically on a posting whose source
/// URL has gone — which left Mark Reviewed, and that only hides the row. When re-extraction isn't
/// viable the popover says so and shows what the extraction actually complained about, so the user
/// isn't guessing why the button won't help.
private struct QuickFixButton: View {
    @Environment(AppServices.self) private var appServices

    let job: Job
    let kinds: [QualityIssueKind]

    @State private var isPresented = false
    @State private var values: [QuickFixField: String] = [:]
    @State private var isSaving = false

    private var fields: [QuickFixField] {
        QuickFixField.fields(for: kinds)
    }

    /// True once at least one field has something worth saving — an all-whitespace entry isn't a fix.
    private var hasEntry: Bool {
        fields.contains { !(values[$0] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    var body: some View {
        Button { isPresented = true } label: {
            Image(systemName: "square.and.pencil").font(.caption2)
        }
        .buttonStyle(.borderless)
        .help("Fill in the missing details by hand")
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Fill in what's missing")
                    .font(.headline)

                ForEach(fields, id: \.self) { field in
                    TextField(field.label, text: Binding(
                        get: { values[field] ?? "" },
                        set: { values[field] = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 260)
                }

                if let error = job.extractionError, !error.isEmpty {
                    // Why re-extraction isn't the answer here. This was invisible on this screen, so
                    // "Re-run AI extraction" looked like an untried option when it had already failed.
                    Text("Extraction failed: \(error)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: 260, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack {
                    Spacer()
                    Button("Cancel") { isPresented = false }
                    Button("Save") { save() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(!hasEntry || isSaving)
                }
            }
            .padding(14)
        }
    }

    private func save() {
        guard !isSaving else { return }
        isSaving = true
        /// Only fields the user actually typed into: passing an empty string would overwrite a value
        /// some other issue on the same row depends on.
        func entry(_ field: QuickFixField) -> String?? {
            guard fields.contains(field) else { return .none }
            let trimmed = (values[field] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? .none : .some(trimmed)
        }
        let service = appServices.jobService
        let jobID = job.id
        let company = entry(.company)
        let title = entry(.title)
        let location = entry(.location)
        Task {
            try? await service.updateJobFields(
                jobID: jobID, company: company, title: title, location: location
            )
            isSaving = false
            isPresented = false
        }
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }
        return CGSize(width: maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout Void) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }
    }
}

// MARK: - Preview

#Preview {
    DataQualityView()
        .environment(Router())
        .frame(width: 900, height: 600)
}
