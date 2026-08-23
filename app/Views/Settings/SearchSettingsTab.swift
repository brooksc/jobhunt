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
    @Environment(AppServices.self) private var appServices
    @Query(sort: \SearchSource.label) private var sources: [SearchSource]

    @State private var showingAddSource = false
    @State private var previewPassed: Int?
    @State private var previewTotal = 0
    @State private var histogram: [String: Int] = [:]
    @State private var runningSourceID: String?

    var body: some View {
        Form {
            enabledSection
            criteriaSection
            sourcesSection
            historySection
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showingAddSource) {
            AddSearchSourceSheet(onAdd: addSource)
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
            if settings.bool(forKey: SettingsKey.discoveryEnabled), noTitleKeywords {
                Label(
                    "With no title keywords, every posting on every board matches. Add at least one "
                        + "before leaving this on.",
                    systemImage: "exclamationmark.triangle"
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
                    onToggle: { setEnabled(source, $0) },
                    onRunNow: { runNow(source) },
                    onDelete: { delete(source) }
                )
            }
            Button("Add Source…") { showingAddSource = true }
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
            let result = await scheduler.runOneDueSweep(
                criteria: DiscoverySettings.criteria(from: settings),
                remainingDailyBudget: DiscoverySettings.remainingDailyBudget(settings)
            )
            if let result {
                if result.ingested > 0 {
                    DiscoverySettings.recordIngests(result.ingested, settings: settings)
                }
                appServices.toastStore.show(summary(of: result, label: label), isError: result.error != nil)
            }
            await refreshPreview()
            await refreshHistogram()
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
    let onToggle: (Bool) -> Void
    let onRunNow: () -> Void
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
                    Button("Run Now", action: onRunNow).buttonStyle(.link)
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
            // so this is the only place the user can find out.
            if source.looksMigrated {
                Label(
                    "Nothing found \(source.consecutiveEmptyRuns) times in a row — this board may "
                        + "have moved.",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.caption)
                .foregroundStyle(.orange)
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

private struct AddSearchSourceSheet: View {
    let onAdd: (_ kind: String, _ label: String, _ slug: String, _ intervalHours: Int) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var kind = "greenhouse"
    @State private var label = ""
    @State private var slug = ""
    @State private var intervalHours = 12

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add a job board").font(.headline)

            Form {
                Picker("Vendor", selection: $kind) {
                    ForEach(JobSources.all, id: \.id) { source in
                        Text(source.displayName).tag(source.id)
                    }
                }
                TextField("Company", text: $label, prompt: Text("Acme"))
                TextField(fieldLabel, text: $slug, prompt: Text(hint))
                Stepper("Check every \(intervalHours) hours", value: $intervalHours, in: 1 ... 168)
            }
            .formStyle(.grouped)

            Text(hintDetail).font(.caption).foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Add") {
                    onAdd(kind, label.isEmpty ? slug : label, slug, intervalHours)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(slug.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    private var configuration: SourceConfiguration? {
        JobSources.source(id: kind)?.configuration
    }

    private var fieldLabel: String {
        if case .boardURL = configuration {
            return "Board URL"
        }
        return "Board ID"
    }

    private var hint: String {
        switch configuration {
        case let .perCompany(slugHint): slugHint
        case let .boardURL(hint): hint
        case nil: ""
        }
    }

    /// Workday genuinely cannot be resolved from a company name — there's no rule that turns "Acme"
    /// into `acme.wd5` — so the form asks for the URL rather than pretending to guess.
    private var hintDetail: String {
        if case .boardURL = configuration {
            return "Open the company's Workday careers page and paste the address from your browser."
        }
        return "The company's ID on the vendor's site — usually the last part of their job board's "
            + "web address."
    }
}
