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
    /// Where the pair being resolved sat in the list, so the next one can take its place once the
    /// list actually updates. See `refreshAndAdvance`.
    @State private var pendingAdvanceIndex: Int?
    /// The pair being resolved, so a not-yet-refreshed list isn't mistaken for a refreshed one.
    @State private var resolvedPairID: String?
    /// Persisted width of the pair-list pane so the compare panel's width is sticky across selections
    /// and launches, and defaults wide enough to use the space (TASK-625).
    @AppStorage("duplicates.listPaneWidth") private var listWidth: Double = 440
    /// List-pane width captured at the start of a divider drag.
    @State private var dragStartWidth: Double?

    private static let listWidthRange: ClosedRange<Double> = 300 ... 760

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
        // A manual split (not HSplitView) so the pair-list width is persisted + draggable, keeping the
        // compare panel's width sticky across selections and launches (TASK-625).
        HStack(spacing: 0) {
            pairList
                .frame(width: listWidth)
            resizeDivider
            detailPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        // The resolved pair leaves the list twice: once when the explicit refresh after the action
        // publishes, and again when the `@Query` write lands and re-triggers the scan above. The
        // second one is the reason advancing can't be done once at the point of action — the row
        // is often still present then, because the write hasn't propagated yet. So the advance is
        // driven by the list actually changing.
        .onChange(of: filteredPairs) { _, _ in
            advanceIfSelectionResolved()
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Text("\(filteredPairs.count) pair\(filteredPairs.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Detail pane + resizable divider

    @ViewBuilder
    private var detailPane: some View {
        if let pairID = selectedPairID,
           let pair = pairs.first(where: { pairKey($0) == pairID }) {
            CompareView(
                pair: pair,
                originalJob: jobIndex[pair.original.id],
                candidateJob: jobIndex[pair.candidate.id],
                onMarkDuplicate: { handleMarkDuplicate(
                    candidateID: pair.candidate.id,
                    cleanedHash: pair.candidate.cleanedHash,
                    keepJobID: pair.original.id,
                    confidence: pair.confidence
                ) },
                onUnmark: { handleUnmark(
                    candidateID: pair.candidate.id,
                    cleanedHash: pair.candidate.cleanedHash,
                    keepJobID: pair.original.id
                ) }
            )
        } else {
            emptyDetail
        }
    }

    /// Thin draggable divider that resizes (and persists) the pair-list pane width.
    private var resizeDivider: some View {
        Divider()
            .frame(width: 6)
            .contentShape(Rectangle())
            .onHover { inside in
                if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        let start = dragStartWidth ?? listWidth
                        if dragStartWidth == nil { dragStartWidth = start }
                        listWidth = min(
                            Self.listWidthRange.upperBound,
                            max(Self.listWidthRange.lowerBound, start + value.translation.width)
                        )
                    }
                    .onEnded { _ in dragStartWidth = nil }
            )
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
                .accessibilityHidden(true)
            TextField("Search duplicate pairs…", text: $searchText)
                .accessibilityLabel("Search duplicate pairs")
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
                .accessibilityLabel("Clear the duplicate-pair search")
                .help("Clear search")
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

        // Only surface pairs where BOTH jobs are still un-marked (a marked `.duplicate` job is
        // resolved). Shared rule with the sidebar badge and dashboard card (TASK-497/581).
        let snapshots = DuplicateDetector.reviewSnapshots(jobs: allJobs)
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

    /// Soft-mark the candidate as a duplicate (TASK-624): links it to the original + `.duplicate`
    /// status (reversible), and records a "duplicate" decision so it stays resolved.
    private func handleMarkDuplicate(candidateID: String, cleanedHash: String?, keepJobID: String, confidence: Double) {
        Task {
            do {
                try await appServices.jobService.markDuplicate(
                    jobID: candidateID, ofJobID: keepJobID, confidence: confidence
                )
                if let hash = cleanedHash, !hash.isEmpty {
                    try await appServices.jobService.decideDuplicate(
                        cleanedHash: hash, decision: "duplicate", keepJobID: keepJobID
                    )
                }
                actionError = nil
                await refreshAndAdvance()
            } catch {
                actionError = "Mark as duplicate failed: \(error.localizedDescription)"
            }
        }
    }

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
                actionError = nil
                await refreshAndAdvance()
            } catch {
                actionError = "Keep Both failed: \(error.localizedDescription)"
            }
        }
    }

    /// Resolve, then move to the next pair, so the queue can be worked through without reaching for
    /// the list between every decision (TASK-625).
    ///
    /// This records *where* the resolved pair was and lets `advanceIfSelectionResolved` do the move
    /// when the row actually disappears. Two things defeat doing it here:
    ///
    /// - The refresh below reads `allJobs`, a `@Query`, and the write that resolved the pair has
    ///   usually not propagated yet — so the resolved row is often still in the list at this point.
    /// - Pair ids are `original||candidate`, and resolving one pair re-runs the grouping over a
    ///   corpus with one job removed, which can re-key the *others*. Advancing to a remembered id
    ///   therefore missed often, and the fallback was `filteredPairs.last` — jumping to the end of
    ///   the queue rather than to the next item, which is what this was supposed to prevent.
    @MainActor
    private func refreshAndAdvance() async {
        pendingAdvanceIndex = selectedPairID.flatMap { filteredPairs.firstIndex(of: $0) } ?? 0
        resolvedPairID = selectedPairID
        await refreshPairsInBackground()
        advanceIfSelectionResolved()
    }

    /// Select whatever now occupies the resolved pair's position — by index, not by id, because the
    /// list is rebuilt rather than edited. Removing item *n* means item *n* is the next one, and
    /// clamping to the end handles resolving the last pair.
    @MainActor
    private func advanceIfSelectionResolved() {
        guard let index = pendingAdvanceIndex else { return }
        // Still showing the pair that was just resolved: the refresh hasn't caught up, so wait for
        // the change that removes it rather than selecting it again.
        if let resolvedPairID, filteredPairs.contains(resolvedPairID) {
            return
        }
        pendingAdvanceIndex = nil
        resolvedPairID = nil
        guard !filteredPairs.isEmpty else {
            selectedPairID = nil
            return
        }
        selectedPairID = filteredPairs[min(index, filteredPairs.count - 1)]
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
                jobNumber: originalJob?.jobNumber,
                company: pair.original.company,
                title: pair.original.title
            )
            // Candidate
            jobSummaryLine(
                label: "Candidate",
                jobNumber: candidateJob?.jobNumber,
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

    private func jobSummaryLine(label: String, jobNumber: Int?, company: String?, title: String?) -> some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                // Job ID (e.g. #123) so a specific pair is easy to reference when reporting an issue.
                if let jobNumber {
                    Text(JobNumberDisplay.label(jobNumber))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
            }
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
    let onMarkDuplicate: () -> Void
    let onUnmark: () -> Void

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
                // Keep Both: not a duplicate — dismiss so it won't resurface.
                Button("Keep Both") {
                    onUnmark()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .font(.caption)

                // Mark as Duplicate (primary): reversible — links the candidate to the original and
                // hides it from active lists, but keeps the record so the same posting can't be
                // re-captured into the review queue (Unmark from All Jobs to undo). Deleting is
                // deliberately NOT offered here — it would lose that re-capture protection (TASK-625);
                // a genuine junk job can still be deleted from the Jobs list.
                Button("Mark as Duplicate") {
                    onMarkDuplicate()
                }
                .buttonStyle(.borderedProminent)
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
                        other: pair.candidate,
                        otherJob: candidateJob
                    )
                    Divider()
                    JobCompareColumn(
                        label: "Candidate",
                        snapshot: pair.candidate,
                        job: candidateJob,
                        other: pair.original,
                        otherJob: originalJob,
                        isNewer: true
                    )
                }
            }
        }
    }
}

// MARK: - JobCompareColumn

private struct JobCompareColumn: View {
    let label: String
    let snapshot: JobSnapshot
    let job: Job?
    let other: JobSnapshot
    /// The other side's Job, for the fields `JobSnapshot` doesn't carry — it exists for duplicate
    /// *detection*, where fit and posting dates are irrelevant, so extending it would put
    /// review-only concerns into the matching path.
    var otherJob: Job?
    var isNewer: Bool = false

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
                        value: job.status.displayName,
                        differs: job.status.rawValue != (other.status.lowercased())
                    )
                    // Two postings that scored differently against the same résumé are usually two
                    // different roles, whatever their titles share — and when they really are the
                    // same posting, this is what says which copy to keep.
                    compareRow(
                        field: "Fit",
                        value: fitText(job),
                        differs: job.fitScore != otherJob?.fitScore
                    )
                    compareRow(
                        field: "Job #",
                        value: snapshot.jobNumber.map { "#\($0)" } ?? "—",
                        differs: false
                    )
                    compareRow(
                        field: "Captured",
                        value: job.createdAt.formatted(date: .abbreviated, time: .shortened),
                        differs: false
                    )
                }
            }
            .padding(.bottom, 8)

            // Summary + skills from the job's extracted data — the two fields that actually tell
            // the two postings apart when the titles and companies are identical.
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
                    skillsSection(projection.skills)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func fitText(_ job: Job) -> String {
        if let score = job.fitScore {
            return "\(score)"
        }
        switch job.fitStatus {
        case .succeeded: return "—"
        case .none: return "not scored"
        default: return job.fitStatus.rawValue
        }
    }

    /// Skills the *other* posting doesn't list, marked.
    ///
    /// The single most decisive thing on this screen when two postings share a company and most of
    /// a title. "Senior Technical Program Manager" and "Senior Technical Program Manager, Game
    /// Security" read as near-identical in every field above and score 62% similar — but one asks
    /// for Anti-Cheat and Threat Assessment and the other for Cloud Infrastructure. Plain lists
    /// leave the reader to diff two paragraphs of comma-separated text by eye.
    @ViewBuilder
    private func skillsSection(_ skills: [String]) -> some View {
        let otherSkills = Set(
            (otherJob.map { JobDetailProjection(job: $0).skills } ?? []).map { $0.lowercased() }
        )
        let shown = skills.prefix(14)
        let uniqueCount = shown.count { !otherSkills.contains($0.lowercased()) }

        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text("Skills")
                    .font(.caption2).foregroundStyle(.secondary).textCase(.uppercase)
                if !otherSkills.isEmpty, uniqueCount > 0 {
                    Text("\(uniqueCount) not in the other")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
            // One Text built from styled runs rather than a wrapping stack of chips: it keeps the
            // existing dense layout, and the whole point is to read the list as a list.
            Text(
                shown.enumerated().reduce(into: AttributedString()) { result, item in
                    if item.offset > 0 {
                        result += AttributedString(" · ")
                    }
                    var run = AttributedString(item.element)
                    if !otherSkills.isEmpty, !otherSkills.contains(item.element.lowercased()) {
                        run.foregroundColor = .orange
                        run.inlinePresentationIntent = .stronglyEmphasized
                    } else {
                        run.foregroundColor = .secondary
                    }
                    result += run
                }
            )
            .font(.caption)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16).padding(.bottom, 8)
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
