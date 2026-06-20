import JobhuntCore
import SwiftData
import SwiftUI

// MARK: - DuplicatesView

struct DuplicatesView: View {
    @Environment(AppServices.self) private var appServices

    /// All jobs — used to build pair index; @Query drives recomputation on change
    @Query(sort: \Job.createdAt, order: .forward) private var allJobs: [Job]
    @Query private var allDecisions: [DuplicateDecision]

    @State private var searchText: String = ""
    @State private var selectedPairID: String?
    @State private var pairs: [DuplicatePair] = []
    @State private var jobIndex: [String: Job] = [:]
    @State private var actionError: String?

    /// Monotonic token guarding stale scan publishes (TASK-384). Each `refreshPairsInBackground`
    /// captures the current value; the expensive scan runs in a detached task that `.task(id:)`
    /// cancellation can't stop, so a superseded scan must not overwrite newer pair/jobIndex state.
    @State private var scanGeneration: Int = 0

    /// Stable ID for `.task(id:)` debouncing — changes whenever the jobs array or decisions
    /// change in any way that affects duplicate detection: count, status, or extractionStatus.
    /// Uses a folded hash so that status transitions (e.g. new→passed) retrigger the scan
    /// even when the job count stays the same.
    private var pairRefreshID: Int {
        var hasher = Hasher()
        hasher.combine(allDecisions.count)
        for job in allJobs {
            hasher.combine(job.id)
            hasher.combine(job.status.rawValue)
            hasher.combine(job.extractionStatus.rawValue)
        }
        return hasher.finalize()
    }

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
                    onUnmark: { handleUnmark(
                        candidateID: pair.candidate.id,
                        cleanedHash: pair.candidate.cleanedHash,
                        keepJobID: pair.original.id
                    ) },
                    onDelete: { handleDelete(candidateID: pair.candidate.id) }
                )
                .frame(minWidth: 480)
            } else {
                emptyDetail
                    .frame(minWidth: 480)
            }
        }
        .navigationTitle("Duplicates")
        .safeAreaInset(edge: .top, spacing: 0) {
            if let msg = actionError {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                    Text(msg).font(.caption).foregroundStyle(.red)
                    Spacer()
                    Button("Dismiss") { actionError = nil }.font(.caption)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.red.opacity(0.08))
            }
        }
        // SwiftUI cancels and restarts this task whenever pairRefreshID changes,
        // giving us implicit debouncing without holding a main-thread lock.
        .task(id: pairRefreshID) {
            await refreshPairsInBackground()
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
                // Match the Jobs list (inset/plain) rather than the gray source-list background.
                .listStyle(.inset)
                .accessibilityIdentifier("content.duplicates")
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
                Text("No new duplicates to review.")
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

    @MainActor
    private func refreshPairsInBackground() async {
        // Supersede any in-flight scan: bump the generation and capture it for the staleness check.
        scanGeneration += 1
        let generation = scanGeneration

        // Build job index and snapshots synchronously on the main actor (reading @Query values is free).
        // Hold the index locally and publish it together with the pairs, so a stale scan can't leave
        // jobIndex updated while pairs reverts to an older value (TASK-384).
        var index: [String: Job] = [:]
        for job in allJobs {
            index[job.id] = job
        }

        // Only surface pairs where BOTH jobs are still un-marked: a job already marked `.duplicate`
        // is resolved — keeping that record is what blocks the same URL-variation from re-creating a
        // job — so it shouldn't reappear in the review queue. Dropping marked-duplicate jobs from the
        // scan means a pair can only form between two un-marked jobs (TASK-497).
        let snapshots = allJobs.compactMap { job -> JobSnapshot? in
            guard job.status != .duplicate, let capture = job.capture else { return nil }
            return JobSnapshot(job: job, capture: capture)
        }
        let resolvedHashes = Set(allDecisions.map(\.cleanedHash))

        // Move O(N²) computation off the main thread
        let newPairs = await Task.detached(priority: .utility) {
            DuplicateDetector().duplicateGroups(snapshots: snapshots, resolvedHashes: resolvedHashes)
        }.value

        // Only publish if this is still the newest scan and the task wasn't cancelled. A detached
        // task isn't a child, so `.task(id:)` cancellation lets us resume here after a newer scan
        // already started — without this guard the older result would clobber newer state.
        guard generation == scanGeneration, !Task.isCancelled else { return }
        jobIndex = index
        pairs = newPairs
    }

    // MARK: - Actions

    private func handleUnmark(candidateID: String, cleanedHash: String?, keepJobID: String) {
        Task {
            do {
                try await appServices.jobService.unmarkDuplicate(jobID: candidateID)
                // Record a "not a duplicate" decision so automatic detection won't re-flag it.
                if let hash = cleanedHash, !hash.isEmpty {
                    try await appServices.jobService.decideDuplicate(
                        cleanedHash: hash, decision: "not_duplicate", keepJobID: keepJobID
                    )
                }
                selectedPairID = nil
                actionError = nil
                await refreshPairsInBackground()
            } catch {
                actionError = "Unmark failed: \(error.localizedDescription)"
            }
        }
    }

    private func handleDelete(candidateID: String) {
        Task {
            do {
                try await appServices.jobService.delete(jobID: candidateID)
                selectedPairID = nil
                actionError = nil
                await refreshPairsInBackground()
            } catch {
                actionError = "Delete failed: \(error.localizedDescription)"
            }
        }
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
            HStack(spacing: 8) {
                Image(systemName: "square.on.square")
                    .font(.caption)
                    .foregroundStyle(.orange)
                Text(String(format: "%.0f%% similar", pair.confidence * 100))
                    .font(.subheadline.weight(.semibold))
                Text("·")
                    .foregroundStyle(.quaternary)
                Text(pair.reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Button("Unmark") {
                    onUnmark()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .font(.caption)

                Button("Delete Candidate") {
                    showDeleteConfirmation = true
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.small)
                .font(.caption)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

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
                        other: pair.original,
                        isNewer: true,
                        onDiscard: { showDeleteConfirmation = true }
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
    var isNewer: Bool = false
    var onDiscard: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Column header
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    if isNewer {
                        Text("newer")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.1))
                            .clipShape(Capsule())
                    }
                }
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

            // Summary + skills from the job's extracted data (restored from Electron compare).
            if let job {
                let projection = JobDetailProjection(job: job)
                if let summary = projection.summary, !summary.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Summary")
                            .font(.caption2).foregroundStyle(.secondary).textCase(.uppercase)
                        Text(summary)
                            .font(.caption).foregroundStyle(.primary).lineLimit(6)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16).padding(.bottom, 8)
                }
                if !projection.skills.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Skills")
                            .font(.caption2).foregroundStyle(.secondary).textCase(.uppercase)
                        Text(projection.skills.prefix(14).joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16).padding(.bottom, 8)
                }
            }

            // Discard button
            if let onDiscard {
                Button {
                    onDiscard()
                } label: {
                    Label("Discard this one", systemImage: "trash")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
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
