import JobhuntCore
import SwiftData
import SwiftUI

/// The Search tab: what to look for, where to look, and what happened (TASK-693, M4).
///
/// Until this shipped, automatic search was debug-only on purpose. The failure mode this feature
/// has is *silence* — criteria that are quietly too strict produce zero results and look identical
/// to criteria that are working — so the switch stays off until the user can see and edit what a
/// sweep will do. The live preview is the single most valuable control here for exactly that
/// reason: it turns "no results in a week" into a number you can see before the week starts.
struct SearchSettingsTab: View {
    let settings: SettingsStore
    /// Not `private`: the market section is an extension in its own file, to keep this one under
    /// the file-length limit, and it needs the same services.
    @Environment(AppServices.self) var appServices
    @Query(sort: \SearchSource.label) private var sources: [SearchSource]
    /// Not `private`: the market section lives in its own file to keep this one under the file-length
    /// limit, and an extension in another file can't see a private stored property.
    @Query var marketState: [MarketSweepState]

    @State private var showingAddSource = false
    @State private var previewPassed: Int?
    @State private var previewTotal = 0
    @State private var histogram: [String: Int] = [:]
    @State private var runningSourceID: String?
    @State private var showingSuggestions = false
    @State private var pendingRepoint: PendingRepoint?

    /// A board re-resolution waiting on the user. See `reresolve`.
    struct PendingRepoint: Identifiable, Equatable {
        let id: String
        let label: String
        let company: String
        let board: ResolvedBoard
    }

    var body: some View {
        Form {
            enabledSection
            criteriaSection
            sourcesSection
            marketSection
            historySection
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showingAddSource) {
            AddSearchSourceSheet(onAdd: addSource)
        }
        .sheet(isPresented: $showingSuggestions) {
            SuggestedCompaniesSheet(onAdd: addSource)
        }
        .alert(
            "Point \(pendingRepoint?.label ?? "this source") at a different board?",
            isPresented: Binding(
                get: { pendingRepoint != nil },
                set: { if !$0 { pendingRepoint = nil } }
            ),
            presenting: pendingRepoint
        ) { pending in
            Button("Use This Board") { applyRepoint(pending) }
            Button("Keep Current", role: .cancel) { pendingRepoint = nil }
        } message: { pending in
            Text(
                "Found \(pending.board.displayName) board “\(pending.board.suggestedCompany)” "
                    + "with \(pending.board.jobCount) open role"
                    + "\(pending.board.jobCount == 1 ? "" : "s").\n\n\(pending.board.boardURL)\n\n"
                    + "Jobhunt matched this by name, so check it really is \(pending.company) "
                    + "before using it."
            )
        }
        .task(id: criteriaSignature) { await refreshPreview() }
        .task { await refreshHistogram() }
        .onAppear { DiscoverySettings.seedIfNeeded(settings) }
    }

    // MARK: - Master switch

    private var enabledSection: some View {
        Section {
            Toggle("Automatic search", isOn: Binding(
                get: { settings.bool(forKey: SettingsKey.discoveryEnabled) },
                set: { settings.setBool($0, forKey: SettingsKey.discoveryEnabled) }
            ))
            if noTitleKeywords {
                // Not advice — a statement of what is currently happening. The interlock is what
                // makes it safe for this to be on by default, but a user staring at an enabled
                // toggle that isn't doing anything deserves to be told why.
                Label(
                    "Paused: add at least one job title below. Without one, every posting on every "
                        + "board would match.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            }
        } footer: {
            Text("Jobhunt checks your boards on a schedule and files anything matching your criteria. "
                + "It never contacts an employer.")
                .font(.caption)
        }
    }

    private var noTitleKeywords: Bool {
        DiscoverySettings.list(settings.string(forKey: SettingsKey.discoveryTitleInclude)).isEmpty
    }

    // MARK: - What I'm looking for

    private var criteriaSection: some View {
        Section("What I'm looking for") {
            listField(
                "Title contains any of", key: SettingsKey.discoveryTitleInclude,
                prompt: "Program Manager, Product Manager, TPM"
            )
            listField(
                "…but none of", key: SettingsKey.discoveryTitleExclude,
                prompt: "Intern, Junior, Graduate"
            )
            listField(
                "Locations allowed", key: SettingsKey.discoveryLocationAllow,
                prompt: "Remote, United States"
            )
            listField(
                "Locations blocked", key: SettingsKey.discoveryLocationBlock,
                prompt: "India, EMEA, Brazil"
            )

            DisclosureGroup("More location rules") {
                listField(
                    "Always allowed", key: SettingsKey.discoveryLocationAlwaysAllow,
                    prompt: "Remote, United States"
                )
                listField(
                    "Never allowed", key: SettingsKey.discoveryLocationBlockHard,
                    prompt: "Brazil"
                )
                Text(
                    "A posting listing several places is kept if any of them is *always allowed* — "
                        + "so “Stockholm · London · Madrid” survives a London block. *Never allowed* "
                        + "is the one rule that beats that, for countries where there's no such thing "
                        + "as a false rejection."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            numberField(
                "Minimum salary, when published", key: SettingsKey.discoveryMinSalary,
                help: "Postings that don't publish a salary are always kept."
            )
            numberField(
                "Maximum age in days", key: SettingsKey.discoveryMaxAgeDays,
                help: "0 for no limit. Postings with no date are always kept."
            )

            previewRow
        }
    }

    /// The control the whole tab exists for. Replays the gate over the rows the last sweep actually
    /// returned, so "too strict" is a number rather than a week of silence.
    @ViewBuilder
    private var previewRow: some View {
        if previewTotal == 0 {
            Text("Run a source once to preview how these criteria would score a real board.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if let passed = previewPassed {
            HStack {
                Image(systemName: passed == 0 ? "exclamationmark.triangle" : "checkmark.circle")
                    .foregroundStyle(passed == 0 ? Color.orange : Color.green)
                Text("These criteria would pass **\(passed)** of \(previewTotal) postings "
                    + "from the last sweep.")
                    .foregroundStyle(.primary)
            }
            .font(.callout)
        }
    }

    // MARK: - Where to look

    private var sourcesSection: some View {
        Section("Where to look") {
            if sources.isEmpty {
                Text("No sources yet. Add a company's job board to start.")
                    .foregroundStyle(.secondary)
            }
            ForEach(sources) { source in
                SearchSourceRow(
                    source: source,
                    isRunning: runningSourceID == source.id,
                    canSweep: DiscoverySettings.canSweep(settings),
                    onToggle: { setEnabled(source, $0) },
                    onRunNow: { runNow(source) },
                    onReresolve: { reresolve(source) },
                    onDelete: { delete(source) }
                )
            }
            HStack {
                Button("Add Source…") { showingAddSource = true }
                // The zero-effort path: companies already in the library that nothing is watching.
                Button("Suggest From My Jobs…") { showingSuggestions = true }
            }
        }
    }

    // MARK: - What happened

    private var historySection: some View {
        Section("What happened") {
            if histogram.isEmpty {
                Text("Nothing swept yet.").foregroundStyle(.secondary)
            } else {
                ForEach(histogram.sorted(by: { $0.value > $1.value }), id: \.key) { entry in
                    LabeledContent(label(for: entry.key), value: "\(entry.value)")
                }
                Text(
                    "If nearly everything is rejected on title, your keywords are the thing to "
                        + "change — that filter does most of the work."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            numberField(
                "Max new jobs per sweep", key: SettingsKey.discoveryMaxIngestsPerSweep,
                help: "A safety limit, not a target."
            )
            numberField(
                "Max new jobs per day", key: SettingsKey.discoveryMaxIngestsPerDay,
                help: "Each new job costs one extraction and one fit score."
            )
        }
    }

    private func label(for key: String) -> String {
        switch key {
        case "ingested": "Added"
        case "hydrationFailed": "Couldn't read the posting"
        case "rejected.title": "Rejected — title"
        case "rejected.location": "Rejected — location"
        case "rejected.salary": "Rejected — salary"
        case "rejected.stale": "Rejected — too old"
        default: key
        }
    }

    // MARK: - Field helpers

    private func listField(_ title: String, key: String, prompt: String) -> some View {
        TextField(title, text: Binding(
            get: { settings.string(forKey: key) },
            // Non-keychain key, so this write cannot fail — see SettingsStore.set.
            set: { try? settings.set($0, forKey: key) }
        ), prompt: Text(prompt))
    }

    private func numberField(_ title: String, key: String, help: String) -> some View {
        LabeledContent(title) {
            VStack(alignment: .trailing, spacing: 2) {
                TextField(title, value: Binding(
                    get: { settings.int(forKey: key) },
                    set: { settings.setInt(max(0, $0), forKey: key) }
                ), format: .number)
                    .labelsHidden()
                    .frame(width: 110)
                Text(help).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Preview

    /// Every input the gate reads. `.task(id:)` restarts on any change, so the sleep debounces
    /// per-keystroke edits into one recompute.
    private var criteriaSignature: String {
        [
            SettingsKey.discoveryTitleInclude, SettingsKey.discoveryTitleExclude,
            SettingsKey.discoveryLocationAllow, SettingsKey.discoveryLocationAlwaysAllow,
            SettingsKey.discoveryLocationBlock, SettingsKey.discoveryLocationBlockHard,
            SettingsKey.discoveryMinSalary, SettingsKey.discoveryMaxAgeDays
        ].map { settings.string(forKey: $0) }.joined(separator: "\u{1F}")
    }

    private func refreshPreview() async {
        try? await Task.sleep(for: .seconds(1))
        guard !Task.isCancelled else { return }
        let criteria = DiscoverySettings.criteria(from: settings)
        guard let rows = try? await appServices.backgroundStore.retainedRawPostings() else { return }
        previewTotal = rows.count
        previewPassed = rows.count { criteria.evaluate($0) == .pass }
    }

    private func refreshHistogram() async {
        histogram = await (try? appServices.backgroundStore.discoveryOutcomeCounts()) ?? [:]
    }

    // MARK: - Source actions

    private func addSource(kind: String, label: String, slug: String, intervalHours: Int) {
        Task {
            do {
                _ = try await appServices.backgroundStore.addSearchSource(
                    kind: kind, label: label,
                    config: SourceConfig(slug: slug, company: label),
                    intervalHours: intervalHours
                )
                appServices.toastStore.show("Added \(label)")
            } catch {
                appServices.toastStore.show("Could not add source", isError: true)
            }
        }
    }

    private func setEnabled(_ source: SearchSource, _ enabled: Bool) {
        let id = source.id
        Task { try? await appServices.backgroundStore.setSearchSourceEnabled(id: id, enabled: enabled) }
    }

    private func delete(_ source: SearchSource) {
        let id = source.id
        Task { try? await appServices.backgroundStore.deleteSearchSource(id: id) }
    }

    /// Sweeps immediately rather than waiting for the scheduler — the point of the button is to find
    /// out now whether a source works, which is also when a wrong slug is cheapest to fix.
    private func runNow(_ source: SearchSource) {
        guard runningSourceID == nil else { return }
        let id = source.id
        let label = source.label
        runningSourceID = id
        Task {
            defer { runningSourceID = nil }
            try? await appServices.backgroundStore.markSearchSourceDue(id: id)

            let store = appServices.backgroundStore
            let scheduler = DiscoveryScheduler(
                store: store,
                sweeper: DiscoverySweeper(
                    store: store, jobService: appServices.jobService,
                    caps: DiscoverySettings.caps(from: settings)
                )
            )
            // Reserve/run/release as one transaction, and by source id rather than "whatever is
            // due" — see `withBudget` and `runSweep`.
            let result: SweepResult? = await DiscoverySettings.withBudget(settings) { budget in
                let swept = await scheduler.runSweep(
                    sourceID: id,
                    criteria: DiscoverySettings.criteria(from: settings),
                    remainingDailyBudget: budget,
                    alreadyCaptured: (try? store.capturedDedupKeys()) ?? []
                )
                guard let swept else { return nil as (result: SweepResult, ingested: Int)? }
                return (swept, swept.ingested)
            }
            if let result {
                appServices.toastStore.show(summary(of: result, label: label), isError: result.error != nil)
            } else {
                appServices.toastStore.show(
                    DiscoverySettings.canSweep(settings)
                        ? "Daily new-job limit reached — automatic search resumes tomorrow."
                        : "Add at least one job title in Search settings first.",
                    isError: true
                )
            }
            await refreshPreview()
            await refreshHistogram()
        }
    }

    /// Offer a replacement board for a source that has gone quiet.
    ///
    /// Only ever *offers*. Silently repointing a source at a board that merely shares a name is how
    /// a user ends up tracking the wrong company without ever being told, so the toast reports what
    /// was found and the config only changes when the vendor or slug actually differs.
    private func reresolve(_ source: SearchSource) {
        let id = source.id
        let label = source.label
        let kind = source.kind
        let slug = source.config.slug
        let company = source.config.company ?? source.label
        Task {
            let result = await SourceResolver.reresolve(
                currentKind: kind, currentSlug: slug, companyName: company
            )
            switch result {
            case let .resolved(board) where board.kind == kind && board.slug == slug:
                // The board is fine — the company simply isn't posting. Saying so is the useful
                // answer here; "repaired" would be a lie.
                appServices.toastStore.show(
                    "\(label): the board is still there with \(board.jobCount) open role"
                        + "\(board.jobCount == 1 ? "" : "s"). It just had nothing matching."
                )
            case let .resolved(board):
                // Asked, not applied. The resolver matches on a slug derived from the company
                // name and never establishes that the board it found belongs to that employer, so
                // repointing silently is how a user ends up tracking a different company's jobs
                // under their own label — with nothing on screen that would ever say so.
                pendingRepoint = PendingRepoint(
                    id: id, label: label, company: company, board: board
                )
            case .failed(.noBoardFound):
                appServices.toastStore.show(
                    "\(label): no board found on any supported vendor.", isError: true
                )
            case .failed(.boardsFoundButEmpty):
                appServices.toastStore.show("\(label): the board exists but lists nothing today.")
            case let .failed(.inconclusive(detail)):
                appServices.toastStore.show("\(label): couldn't check (\(detail))", isError: true)
            case let .failed(.unusableName(detail)):
                appServices.toastStore.show("\(label): \(detail)", isError: true)
            }
        }
    }

    private func applyRepoint(_ pending: PendingRepoint) {
        pendingRepoint = nil
        Task {
            try? await appServices.backgroundStore.updateSearchSourceConfig(
                id: pending.id, kind: pending.board.kind,
                config: SourceConfig(slug: pending.board.slug, company: pending.company)
            )
            appServices.toastStore.show(
                "\(pending.label): moved to \(pending.board.displayName) — "
                    + "\(pending.board.jobCount) open roles"
            )
        }
    }

    /// Says what happened in one line, including the truncation — a cap that goes unmentioned reads
    /// as "nothing more was found".
    private func summary(of result: SweepResult, label: String) -> String {
        if let error = result.error {
            return "\(label): \(error)"
        }
        var line = "\(label): \(result.found) found, \(result.ingested) added"
        if result.truncatedByCap > 0 {
            line += " — stopped at the cap, \(result.truncatedByCap) more matched"
        }
        if result.hydrationFailures > 0 {
            line += " — \(result.hydrationFailures) couldn't be read"
        }
        return line
    }
}

// MARK: - Source row

private struct SearchSourceRow: View {
    let source: SearchSource
    let isRunning: Bool
    let canSweep: Bool
    let onToggle: (Bool) -> Void
    let onRunNow: () -> Void
    let onReresolve: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Circle()
                    .fill(dotColor)
                    .frame(width: 8, height: 8)
                    .accessibilityLabel(statusText)
                Text(source.label).fontWeight(.medium)
                Text(source.source?.displayName ?? source.kind)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if isRunning {
                    ProgressView().controlSize(.small)
                } else {
                    // Disabled while the title interlock is closed: the button cannot sweep, and
                    // offering it suggests otherwise.
                    Button("Run Now", action: onRunNow)
                        .buttonStyle(.link)
                        .disabled(!canSweep)
                        .help(canSweep ? "" : "Add at least one job title first.")
                }
                Toggle("Enabled", isOn: Binding(get: { source.enabled }, set: onToggle))
                    .labelsHidden()
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Remove \(source.label)")
            }
            Text(detailLine).font(.caption).foregroundStyle(.secondary)

            // The signal a board migrated. It never errors — it just answers with nothing, forever —
            // so this is the only place the user can find out, and the button is the only way to
            // act on it without hand-editing anything.
            if source.looksMigrated {
                HStack(spacing: 6) {
                    Label(
                        "Nothing found \(source.consecutiveEmptyRuns) times in a row — this board "
                            + "may have moved.",
                        systemImage: "exclamationmark.triangle"
                    )
                    .foregroundStyle(.orange)
                    Button("Re-resolve", action: onReresolve).buttonStyle(.link)
                }
                .font(.caption)
            }
            if let error = source.lastError {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
        .padding(.vertical, 2)
    }

    private var detailLine: String {
        guard let lastRun = source.lastRunAt else {
            return "Every \(source.intervalHours)h · never run"
        }
        let when = lastRun.formatted(.relative(presentation: .named))
        return "Every \(source.intervalHours)h · \(when) · "
            + "\(source.lastFoundCount) found → \(source.lastPassedCount) matched → "
            + "\(source.lastIngestedCount) added"
    }

    private var dotColor: Color {
        switch source.status {
        case .ok: .green
        case .never: .secondary
        case .empty, .truncated: .orange
        case .unreachable, .rateLimited, .misconfigured: .red
        }
    }

    private var statusText: String {
        switch source.status {
        case .ok: "Healthy"
        case .never: "Not yet run"
        case .empty: "Found nothing"
        case .truncated: "Incomplete"
        case .unreachable: "Unreachable"
        case .rateLimited: "Rate limited"
        case .misconfigured: "Misconfigured"
        }
    }
}

// MARK: - Add sheet

/// Adds a board by **company name**, not by vendor and slug (TASK-694, M5).
///
/// The previous form asked which ATS the company used and what its board ID was. Both are things a
/// user has no reason to know, and getting either wrong produced a source that silently found
/// nothing — indistinguishable from a company that isn't hiring. So the form asks for the name,
/// probes the vendors, and shows the live job count *before* anything is saved.
///
/// A pasted URL works too, which is the only route for Workday: no rule turns "Acme" into
/// `acme.wd5`, so the address bar is the only place that information exists.
private struct AddSearchSourceSheet: View {
    let onAdd: (_ kind: String, _ label: String, _ slug: String, _ intervalHours: Int) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var intervalHours = 12
    @State private var isSearching = false
    @State private var found: ResolvedBoard?
    @State private var emptyBoards: [ResolvedBoard] = []
    @State private var failureMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add a job board").font(.headline)

            Form {
                TextField("Company or board address", text: $query, prompt: Text("Acme"))
                    .onSubmit { search() }
                Stepper("Check every \(intervalHours) hours", value: $intervalHours, in: 1 ... 168)
            }
            .formStyle(.grouped)

            resultView

            HStack {
                Button(isSearching ? "Searching…" : "Find Board") { search() }
                    .disabled(isSearching || query.trimmingCharacters(in: .whitespaces).isEmpty)
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Add") { add() }
                    .keyboardShortcut(.defaultAction)
                    // Never save a board that resolved to nothing without the user choosing it
                    // explicitly — that is exactly how a dead slug gets in and then looks, forever,
                    // like a company that stopped hiring.
                    .disabled(found == nil)
            }
        }
        .padding(20)
        .frame(width: 480)
    }

    @ViewBuilder
    private var resultView: some View {
        if isSearching {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Checking Greenhouse, Ashby and Lever…").foregroundStyle(.secondary)
            }
            .font(.callout)
        } else if let found {
            Label(
                "\(found.displayName) — \(found.jobCount) open role\(found.jobCount == 1 ? "" : "s")",
                systemImage: "checkmark.circle.fill"
            )
            .foregroundStyle(.green)
            Text(found.boardURL).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            // A pasted URL identifies its own board. A *name* was turned into a slug and probed
            // vendor by vendor, and nothing checks that the board found belongs to the employer
            // meant — two companies with similar names share one slug and the tick looks the same.
            if !query.trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("http") {
                Text("Matched by name — open the link to check it's the right company.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else if !emptyBoards.isEmpty {
            // A real board with nothing on it today. Worth offering, but the user has to say so.
            ForEach(emptyBoards, id: \.boardURL) { board in
                VStack(alignment: .leading, spacing: 2) {
                    Label(
                        "Found a \(board.displayName) board, but it lists no jobs right now.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(.orange)
                    Button("Add it anyway") {
                        onAdd(board.kind, displayLabel, board.slug, intervalHours)
                        dismiss()
                    }
                    .buttonStyle(.link)
                }
            }
        } else if let failureMessage {
            Label(failureMessage, systemImage: "xmark.circle").foregroundStyle(.secondary)
        } else {
            Text("Type a company name, or paste the address of their job board.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// What the source is called, and what becomes `SourceConfig.company`.
    ///
    /// A pasted URL has no company name in it worth showing, so the resolver's employer hint stands
    /// in. Not the slug: for Workday the slug is the entire URL, and this value ends up as the
    /// company on every job the source discovers.
    private var displayLabel: String {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if trimmed.lowercased().hasPrefix("http") {
            return found?.suggestedCompany ?? trimmed
        }
        return trimmed
    }

    private func search() {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !isSearching else { return }
        isSearching = true
        found = nil
        emptyBoards = []
        failureMessage = nil

        Task {
            defer { isSearching = false }
            let result = trimmed.lowercased().hasPrefix("http")
                ? await SourceResolver.resolve(boardURL: trimmed)
                : await SourceResolver.resolve(companyName: trimmed)

            switch result {
            case let .resolved(board):
                found = board
            case let .failed(.boardsFoundButEmpty(boards)):
                emptyBoards = boards
            case .failed(.noBoardFound):
                failureMessage = "No Greenhouse, Ashby or Lever board found for “\(trimmed)”. "
                    + "If they use Workday, paste their careers page address instead."
            case let .failed(.inconclusive(detail)):
                // Never reported as "no board" — absence was not established, and a retry is the
                // right suggestion for this one and the wrong one for a genuine absence.
                failureMessage = "Couldn't check every board (\(detail)). Try again in a moment."
            case let .failed(.unusableName(detail)):
                failureMessage = detail
            }
        }
    }

    private func add() {
        guard let found else { return }
        onAdd(found.kind, displayLabel, found.slug, intervalHours)
        dismiss()
    }
}

// MARK: - Suggested companies

/// Offers the companies already in the library that nothing is watching (TASK-695, M6).
///
/// The leverage this exists for: a user who captured one posting at a company can turn that into a
/// source watching its entire board, forever, without knowing what an ATS is. Measured against real
/// boards, one captured Databricks posting becomes 821 roles under continuous watch.
///
/// Most suggestions cost no network request at all — the job's own URL already names the vendor and
/// the board. Only companies whose postings came from a careers page jobhunt can't read need
/// probing, and that is deliberately bounded.
private struct SuggestedCompaniesSheet: View {
    let onAdd: (_ kind: String, _ label: String, _ slug: String, _ intervalHours: Int) -> Void
    @Environment(AppServices.self) private var appServices
    @Environment(\.dismiss) private var dismiss

    @State private var suggestions: [CompanySuggestion] = []
    @State private var added: Set<String> = []
    @State private var isLoading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Companies you're not watching").font(.headline)
            Text("You have jobs from these companies but nothing is checking their boards.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if isLoading {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Looking through your jobs…").foregroundStyle(.secondary)
                }
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else if suggestions.isEmpty {
                Text("Nothing to suggest — every company in your library is already watched, or "
                    + "their boards couldn't be identified.")
                    .foregroundStyle(.secondary)
            } else {
                List(suggestions) { suggestion in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(suggestion.company).fontWeight(.medium)
                            Text(detail(for: suggestion))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if added.contains(suggestion.id) {
                            Label("Added", systemImage: "checkmark").foregroundStyle(.green)
                        } else {
                            Button("Watch") {
                                onAdd(suggestion.board.kind, suggestion.company, suggestion.board.slug, 12)
                                added.insert(suggestion.id)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(minHeight: 220)
            }

            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 520)
        .task {
            suggestions = await CompanyDiscovery(store: appServices.backgroundStore).suggestions()
            isLoading = false
        }
    }

    /// The open-role count is only known for a board that was probed; a board read straight off a
    /// job's URL was never fetched, so it says nothing rather than claiming zero.
    private func detail(for suggestion: CompanySuggestion) -> String {
        var parts = [suggestion.board.displayName]
        if suggestion.board.jobCount > 0 {
            parts.append("\(suggestion.board.jobCount) open roles")
        }
        let saved = suggestion.existingJobCount
        parts.append("\(saved) job\(saved == 1 ? "" : "s") saved")
        return parts.joined(separator: " · ")
    }
}
