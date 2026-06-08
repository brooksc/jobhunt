import JobhuntCore
import SwiftData
import SwiftUI

// MARK: - DataQualityView

struct DataQualityView: View {
    @Environment(Router.self) private var router
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Job.createdAt, order: .reverse)
    private var allJobs: [Job]

    private var activeJobs: [Job] {
        allJobs.filter {
            $0.status != .archived &&
                $0.status != .notAvailable &&
                $0.status != .duplicate
        }
    }

    @State private var selectedJobIDs: Set<String> = []
    @State private var filterKind: QualityIssueKind? // nil = all
    @State private var showReviewed = false
    @State private var errorMessage: String?

    // MARK: - Derived data

    private var issueRows: [(job: Job, issue: QualityIssue)] {
        activeJobs.compactMap { job in
            let kinds = QualityChecker.issues(for: job)
            guard !kinds.isEmpty else { return nil }
            if !showReviewed && job.qualityReview != nil { return nil }
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

    private var totalIssueCount: Int {
        issueRows.count
    }

    private var highSeverityCount: Int {
        issueRows.count(where: { $0.issue.severity >= 3 })
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
        .toolbar { toolbarContent }
        .alert("Error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Summary header

    private var summaryHeader: some View {
        HStack(spacing: 16) {
            summaryMetric(label: "Total issues", value: totalIssueCount, warning: totalIssueCount > 0)
            Divider().frame(height: 32)
            summaryMetric(label: "High severity (3+)", value: highSeverityCount, warning: highSeverityCount > 0)
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
                            filterKind = kind
                        }
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
                    .foregroundStyle(kind.isHighSeverity ? Color.red : Color.orange)
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

    // MARK: - Actions (main-context writes)

    private func markReviewedSelected() {
        let selectedJobs = activeJobs.filter { selectedJobIDs.contains($0.id) }
        do {
            for job in selectedJobs {
                if let existing = job.qualityReview {
                    existing.reviewedAt = Date()
                    existing.note = ""
                } else {
                    let review = DataQualityReview(reviewedAt: Date(), note: "")
                    review.job = job
                    modelContext.insert(review)
                }
            }
            try modelContext.save()
            selectedJobIDs = []
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func clearReviewSelected() {
        let selectedJobs = activeJobs.filter { selectedJobIDs.contains($0.id) }
        do {
            for job in selectedJobs {
                if let review = job.qualityReview {
                    modelContext.delete(review)
                }
            }
            try modelContext.save()
            selectedJobIDs = []
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func queueReextractionSelected() {
        let selectedJobs = activeJobs.filter { selectedJobIDs.contains($0.id) }
        do {
            for job in selectedJobs {
                job.extractionStatus = .pending
                job.extractionError = nil
                job.extractedAt = nil
                job.updatedAt = Date()
                let request = LLMRequest(requestType: .extract)
                request.job = job
                modelContext.insert(request)
            }
            try modelContext.save()
            selectedJobIDs = []
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - FlowLayout (wrapping HStack for issue chips)

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
