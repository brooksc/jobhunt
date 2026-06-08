import JobhuntCore
import SwiftData
import SwiftUI

// MARK: - DuplicatesView

struct DuplicatesView: View {
    @Environment(\.modelContext) private var modelContext

    /// All jobs — used to compute pairs and to look up originals by ID
    @Query(sort: \Job.createdAt, order: .forward) private var allJobs: [Job]

    @State private var searchText: String = ""
    @State private var selectedPairID: String?
    @State private var pairs: [DuplicatePair] = []
    @State private var jobIndex: [String: Job] = [:]

    var body: some View {
        HSplitView {
            pairList
                .frame(minWidth: 320)

            if let pairID = selectedPairID,
               let pair = pairs.first(where: { pairKey($0) == pairID }) {
                CompareView(
                    pair: pair,
                    originalJob: jobIndex[pair.original.id],
                    candidateJob: jobIndex[pair.candidate.id],
                    onUnmark: { handleUnmark(candidateID: pair.candidate.id) },
                    onDelete: { handleDelete(candidateID: pair.candidate.id) }
                )
                .frame(minWidth: 480)
            } else {
                emptyDetail
                    .frame(minWidth: 480)
            }
        }
        .onChange(of: allJobs) { _, _ in
            refreshPairs()
        }
        .onAppear {
            refreshPairs()
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Text("\(filteredPairs.count) pair\(filteredPairs.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Pair list

    private var pairList: some View {
        VStack(spacing: 0) {
            searchBar
            Divider()
            if filteredPairs.isEmpty {
                emptyList
            } else {
                List(selection: $selectedPairID) {
                    ForEach(filteredPairs, id: \.self) { pairID in
                        if let pair = pairs.first(where: { pairKey($0) == pairID }) {
                            PairRow(
                                pair: pair,
                                originalJob: jobIndex[pair.original.id],
                                candidateJob: jobIndex[pair.candidate.id]
                            )
                            .tag(pairID)
                        }
                    }
                }
                .listStyle(.sidebar)
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.caption)
            TextField("Search duplicate pairs…", text: $searchText)
                .textFieldStyle(.plain)
                .font(.body)
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
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var emptyList: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.on.doc")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            if searchText.isEmpty {
                Text("No duplicate pairs need review.")
                    .foregroundStyle(.secondary)
            } else {
                Text("No pairs match your search.")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyDetail: some View {
        VStack(spacing: 8) {
            Image(systemName: "arrow.left")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            Text("Select a pair to compare")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Filtered pairs

    private var filteredPairs: [String] {
        let q = searchText.lowercased().trimmingCharacters(in: .whitespaces)
        if q.isEmpty {
            return pairs.map { pairKey($0) }
        }
        return pairs.filter { pair in
            let fields = [
                pair.original.company, pair.original.title,
                pair.candidate.company, pair.candidate.title,
                pair.reason
            ]
            return fields.contains(where: { ($0 ?? "").lowercased().contains(q) })
        }.map { pairKey($0) }
    }

    // MARK: - Helpers

    private func pairKey(_ pair: DuplicatePair) -> String {
        "\(pair.original.id)||\(pair.candidate.id)"
    }

    private func refreshPairs() {
        // Build job index
        var index: [String: Job] = [:]
        for job in allJobs {
            index[job.id] = job
        }
        jobIndex = index

        // Compute pairs via DuplicateDetector
        do {
            pairs = try DuplicateDetector().duplicateGroups(context: modelContext)
        } catch {
            pairs = []
        }
    }

    // MARK: - Actions

    private func handleUnmark(candidateID: String) {
        guard let job = jobIndex[candidateID] else { return }
        job.duplicateOfJobID = nil
        job.status = .saved
        job.updatedAt = Date()
        try? modelContext.save()
        selectedPairID = nil
        refreshPairs()
    }

    private func handleDelete(candidateID: String) {
        guard let job = jobIndex[candidateID] else { return }
        modelContext.delete(job)
        try? modelContext.save()
        selectedPairID = nil
        refreshPairs()
    }
}

// MARK: - PairRow

private struct PairRow: View {
    let pair: DuplicatePair
    let originalJob: Job?
    let candidateJob: Job?

    private var confidencePct: String {
        String(format: "%.0f%%", pair.confidence * 100)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Original
            jobSummaryLine(
                label: "Original",
                company: pair.original.company,
                title: pair.original.title
            )
            // Candidate
            jobSummaryLine(
                label: "Candidate",
                company: pair.candidate.company,
                title: pair.candidate.title
            )
            // Meta row
            HStack(spacing: 8) {
                Text(confidencePct)
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Text(pair.reason)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            // Captured date (candidate)
            if let job = candidateJob {
                Text("Captured \(job.createdAt.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }

    private func jobSummaryLine(label: String, company: String?, title: String?) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 56, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text(company ?? "Unknown company")
                    .font(.callout)
                    .fontWeight(.medium)
                    .lineLimit(1)
                if let title {
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }
}

// MARK: - CompareView

struct CompareView: View {
    let pair: DuplicatePair
    let originalJob: Job?
    let candidateJob: Job?
    let onUnmark: () -> Void
    let onDelete: () -> Void

    @State private var showDeleteConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            // Header bar
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Compare Pair")
                        .font(.headline)
                    HStack(spacing: 4) {
                        Text(String(format: "%.0f%% match", pair.confidence * 100))
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        Text("·")
                            .foregroundStyle(.tertiary)
                        Text(pair.reason)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                Button("Unmark as Duplicate") {
                    onUnmark()
                }
                .buttonStyle(.bordered)

                Button("Delete Candidate") {
                    showDeleteConfirmation = true
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            // Two-column comparison
            ScrollView {
                HStack(alignment: .top, spacing: 0) {
                    JobCompareColumn(
                        label: "Original",
                        snapshot: pair.original,
                        job: originalJob,
                        other: pair.candidate
                    )
                    Divider()
                    JobCompareColumn(
                        label: "Candidate",
                        snapshot: pair.candidate,
                        job: candidateJob,
                        other: pair.original
                    )
                }
            }
        }
        .alert("Delete Candidate?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                onDelete()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete the candidate job and cannot be undone.")
        }
    }
}

// MARK: - JobCompareColumn

private struct JobCompareColumn: View {
    let label: String
    let snapshot: JobSnapshot
    let job: Job?
    let other: JobSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Column header
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                HStack(spacing: 8) {
                    Text(snapshot.company ?? "Unknown company")
                        .font(.title3)
                        .fontWeight(.semibold)
                    if let job {
                        StatusChip(status: job.status)
                    }
                }
                if let sourceURL = URL(string: snapshot.sourceURL) {
                    Link(destination: sourceURL) {
                        Text(shortURL(snapshot.sourceURL))
                            .font(.caption)
                            .foregroundStyle(Color.accentColor)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            // Fields grid
            VStack(spacing: 0) {
                compareRow(
                    field: "Title",
                    value: snapshot.title ?? "—",
                    differs: normalizeField(snapshot.title) != normalizeField(other.title)
                )
                compareRow(
                    field: "Company",
                    value: snapshot.company ?? "—",
                    differs: normalizeField(snapshot.company) != normalizeField(other.company)
                )
                compareRow(
                    field: "Location",
                    value: snapshot.location ?? "—",
                    differs: normalizeField(snapshot.location) != normalizeField(other.location)
                )
                compareRow(
                    field: "Remote",
                    value: snapshot.remoteType ?? "—",
                    differs: normalizeField(snapshot.remoteType) != normalizeField(other.remoteType)
                )
                compareRow(
                    field: "Salary",
                    value: salaryString(snapshot),
                    differs: salaryString(snapshot) != salaryString(other)
                )
                compareRow(
                    field: "Employment",
                    value: snapshot.employmentType ?? "—",
                    differs: normalizeField(snapshot.employmentType) != normalizeField(other.employmentType)
                )
                compareRow(
                    field: "Seniority",
                    value: snapshot.seniority ?? "—",
                    differs: normalizeField(snapshot.seniority) != normalizeField(other.seniority)
                )
                if let job {
                    compareRow(
                        field: "Status",
                        value: job.status.rawValue.capitalized,
                        differs: job.status.rawValue != (other.status.lowercased())
                    )
                    compareRow(
                        field: "Captured",
                        value: job.createdAt.formatted(date: .abbreviated, time: .shortened),
                        differs: false
                    )
                }
            }
            .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func compareRow(field: String, value: String, differs: Bool) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Text(field)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)
                .padding(.leading, 16)
                .padding(.vertical, 7)

            Text(value)
                .font(.callout)
                .fontWeight(differs ? .semibold : .regular)
                .foregroundStyle(differs ? Color.accentColor : Color.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 16)
                .padding(.vertical, 7)
        }
        .background(differs ? Color.accentColor.opacity(0.07) : Color.clear)
        Divider()
            .padding(.leading, 16)
    }

    private func normalizeField(_ value: String?) -> String {
        (value ?? "").trimmingCharacters(in: .whitespaces).lowercased()
    }

    private func salaryString(_ snap: JobSnapshot) -> String {
        guard let min = snap.salaryMin else { return "—" }
        let currency = snap.salaryCurrency ?? ""
        if let max = snap.salaryMax {
            return "\(currency)\(min)–\(max)"
        }
        return "\(currency)\(min)+"
    }

    private func shortURL(_ urlString: String) -> String {
        let cleaned = urlString
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
        return String(cleaned.prefix(60))
    }
}
