import AppKit
import JobhuntCore
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

// MARK: - General tab (appearance, intervals, about)

struct SettingsTab: View {
    let settings: SettingsStore

    @Environment(Theme.self) private var theme

    var body: some View {
        Form {
            appearanceSection
            intervalsSection
            appInfoSection
        }
        .formStyle(.grouped)
    }

    // MARK: - Appearance section (HIG-3: theme preference moved here from sidebar)

    private var appearanceSection: some View {
        Section("Appearance") {
            Picker("Color scheme", selection: Binding(
                get: { theme.colorSchemePreference },
                set: { theme.colorSchemePreference = $0 }
            )) {
                ForEach(Theme.ColorSchemePreference.allCases, id: \.self) { pref in
                    Label(pref.label, systemImage: pref.systemImage).tag(pref)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    // MARK: - Intervals section

    private var intervalsSection: some View {
        Section("Intervals") {
            Stepper(
                "Site review interval: \(settings.siteReviewIntervalDays) days",
                value: Binding(
                    get: { settings.siteReviewIntervalDays },
                    set: { settings.siteReviewIntervalDays = $0 }
                ),
                in: 1 ... 90
            )

            Stepper(
                "Follow-up default: \(settings.followupDefaultDays) days",
                value: Binding(
                    get: { settings.followupDefaultDays },
                    set: { settings.followupDefaultDays = $0 }
                ),
                in: 1 ... 60
            )

            // TASK-623 #11: opt-in, and off by default. A daily nudge nobody asked for is exactly
            // the pressure the recap feature is meant not to apply, so dismissing it costs nothing
            // and there is no streak to break.
            Toggle("Remind me to close out my day", isOn: Binding(
                get: { settings.dailyRecapReminderEnabled },
                set: { settings.dailyRecapReminderEnabled = $0 }
            ))
            .help("A single optional notification with the day's summary. Off by default.")

            if settings.dailyRecapReminderEnabled {
                Stepper(
                    "Remind at \(settings.dailyRecapReminderHour):00",
                    value: Binding(
                        get: { settings.dailyRecapReminderHour },
                        set: { settings.dailyRecapReminderHour = $0 }
                    ),
                    in: 0 ... 23
                )
            }
        }
    }

    // MARK: - App info

    private var appInfoSection: some View {
        Section("About") {
            LabeledContent("Version") {
                Text(appVersion)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            LabeledContent("Build") {
                Text(appBuild)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Toggle("Show Debug tab", isOn: Binding(
                get: { !settings.bool(forKey: SettingsKey.hideDebugTab) },
                set: { settings.setBool(!$0, forKey: SettingsKey.hideDebugTab) }
            ))
            .help("The Debug tab holds developer diagnostics and maintenance actions.")
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    private var appBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }
}

// MARK: - Jobs tab (location filter, availability, extraction instructions)

struct JobsSettingsTab: View {
    let settings: SettingsStore

    @State private var customJDText: String = ""
    @State private var applicationDetailsText: String = ""
    @State private var isRunningAvailabilityCheck = false
    @State private var availabilityCheckMessage: String?
    @State private var goneJobs: [GoneJobResult] = []
    @State private var unverifiedJobs: [UnverifiedJobResult] = []
    @State private var showingExpiredConfirmation = false
    /// Coverage of the run behind the sheet — see ExpiredConfirmationSheet.coverageLine.
    @State private var lastCheckedCount = 0
    @State private var lastPlannedCount = 0

    /// Internal, not private: the extracted scoring-feedback section is an extension on this view.
    @Environment(AppServices.self) var appServices
    /// How many stored requirements each correction currently matches, keyed by feedback id.
    @State var feedbackMatchCounts: [String: Int] = [:]
    /// The correction currently open in the editor sheet (TASK-654).
    @State var editingFeedback: ScoringFeedback?
    /// The prompt template open in the editor sheet (TASK-627).
    @State var editingPrompt: PromptTemplate?
    @Query private var allJobs: [Job]

    var body: some View {
        Form {
            locationSection
            requirementsSection
            scoringFeedbackSection
            customPromptsSection
            availabilitySection
            customExtractionSection
            applicationDetailsSection
        }
        .formStyle(.grouped)
        .onAppear {
            customJDText = settings.string(forKey: SettingsKey.jobDescriptionMarkdown)
            applicationDetailsText = settings.string(forKey: SettingsKey.applicationPersonalInfo)
        }
        .task(id: locationCriteriaSignature) { await recomputeCriteriaAfterEdit() }
        .sheet(isPresented: $showingExpiredConfirmation) {
            ExpiredConfirmationSheet(
                goneJobs: goneJobs,
                unverifiedJobs: unverifiedJobs,
                checkedCount: lastCheckedCount,
                plannedCount: lastPlannedCount,
                onConfirm: { markExpired($0) },
                onDismiss: {
                    showingExpiredConfirmation = false
                    availabilityCheckMessage = "\(goneJobs.count) potential expiration(s) — none marked"
                }
            )
        }
    }

    // MARK: - Location criteria recompute

    /// Every input `LocationCriteria` reads. `.task(id:)` cancels and restarts whenever one changes,
    /// so the sleep below debounces per-keystroke edits of the text fields into one recompute.
    private var locationCriteriaSignature: String {
        [
            settings.preferredLocations,
            settings.preferredMetros,
            String(settings.locationFilterEnabled),
            String(settings.locationAllowRemote),
            String(settings.locationAllowHybrid),
            String(settings.locationAllowOnsite)
        ].joined(separator: "\u{1F}")
    }

    /// Changing the location settings used to affect only jobs extracted *afterwards* — the existing
    /// library kept its old verdicts until someone ran `JobhuntMigrator --recompute-criteria`, which
    /// meant the Jobs filter silently disagreed with the settings. Re-judging is pure (no LLM calls,
    /// no network) so it just happens on save.
    ///
    /// Values are read here and passed explicitly rather than re-read inside `BackgroundStore`: the
    /// settings live in a different `ModelContext`, so a fetch there could still see the old row.
    private func recomputeCriteriaAfterEdit() async {
        try? await Task.sleep(for: .seconds(1))
        guard !Task.isCancelled else { return }

        let preferred = combinedPreferredLocations(
            locations: settings.preferredLocations, metros: settings.preferredMetros
        )
        let eligibility = settings.remoteEligibilityRegions
        let (enabled, remote) = (settings.locationFilterEnabled, settings.locationAllowRemote)
        let (hybrid, onsite) = (settings.locationAllowHybrid, settings.locationAllowOnsite)
        do {
            let changed = try await appServices.backgroundStore.recomputeMeetsCriteria(
                preferredLocations: preferred, remoteEligibilityRegions: eligibility,
                allowRemote: remote, allowHybrid: hybrid,
                allowOnsite: onsite, filterEnabled: enabled
            )
            // Silent when nothing moved — this also runs once on appear, which must not toast.
            if changed > 0 {
                appServices.toastStore.show("Criteria re-checked — \(changed) job\(changed == 1 ? "" : "s") updated")
            }
        } catch {
            appServices.toastStore.show("Could not re-check criteria: \(error.localizedDescription)", isError: true)
        }
    }

    // MARK: - Location section

    private var locationSection: some View {
        Section("Location Filter") {
            Toggle("Enable location filter", isOn: Binding(
                get: { settings.locationFilterEnabled },
                set: { settings.locationFilterEnabled = $0 }
            ))

            if settings.locationFilterEnabled {
                Toggle("Allow Remote", isOn: Binding(
                    get: { settings.locationAllowRemote },
                    set: { settings.locationAllowRemote = $0 }
                ))
                Toggle("Allow Hybrid", isOn: Binding(
                    get: { settings.locationAllowHybrid },
                    set: { settings.locationAllowHybrid = $0 }
                ))
                Toggle("Allow Onsite", isOn: Binding(
                    get: { settings.locationAllowOnsite },
                    set: { settings.locationAllowOnsite = $0 }
                ))
                TextField("Preferred locations (comma-separated)", text: Binding(
                    get: { settings.preferredLocations },
                    set: { settings.preferredLocations = $0 }
                ))
                TextField("Preferred metros (e.g. Bay Area, NYC)", text: Binding(
                    get: { settings.preferredMetros },
                    set: { settings.preferredMetros = $0 }
                ))
                Text("Metros expand to their cities/states and are combined with preferred locations for extraction.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextField("Remote eligibility (e.g. US, Canada)", text: Binding(
                    get: { settings.remoteEligibilityRegions },
                    set: { settings.remoteEligibilityRegions = $0 }
                ))
                Text(
                    "Where you can legally work remotely. Separate from preferred locations, which "
                        + "are about commuting. A remote job that names only other regions stops "
                        + "meeting criteria; one that names no region still passes. Leave empty to "
                        + "keep using preferred locations."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Requirements section

    /// Salary and fit floors feed the same Meets / Not stated / Doesn't meet buckets as the location
    /// filter, so the Jobs list can triage on all three at once. Both default to 0 (off) — a floor
    /// only applies once the user sets their own number.
    private var requirementsSection: some View {
        Section("Requirements") {
            LabeledContent("Minimum salary") {
                HStack(spacing: 6) {
                    TextField(
                        "0",
                        value: Binding(
                            get: { settings.minSalary },
                            set: { settings.minSalary = $0 }
                        ),
                        format: .number
                    )
                    .labelsHidden()
                    .frame(width: 110)
                    .multilineTextAlignment(.trailing)
                    Text(settings.minSalary > 0 ? "USD / year" : "off")
                        .foregroundStyle(.secondary)
                }
            }
            Text(
                "Compared against the TOP of a job's range, so a posting is only flagged when even its "
                    + "ceiling falls short. Jobs that don't publish a salary are never flagged — they go to "
                    + "“Not stated”. 0 turns the check off."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            LabeledContent("Minimum fit score") {
                HStack(spacing: 6) {
                    TextField(
                        "0",
                        value: Binding(
                            get: { settings.minFitScore },
                            set: { settings.minFitScore = $0 }
                        ),
                        format: .number
                    )
                    .labelsHidden()
                    .frame(width: 110)
                    .multilineTextAlignment(.trailing)
                    Text(settings.minFitScore > 0 ? "of 100" : "off")
                        .foregroundStyle(.secondary)
                }
            }
            Text(
                "Jobs scoring below this are flagged as not meeting your requirements. Unscored jobs go "
                    + "to “Not stated”. 0 turns the check off."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            Text("Filter on these in Jobs → Filter → Requirements.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Availability section

    private var availabilitySection: some View {
        Section("Availability Auto-Check") {
            Toggle("Enable auto-check", isOn: Binding(
                get: { settings.bool(forKey: SettingsKey.availabilityAutoCheckEnabled) },
                set: { settings.setBool($0, forKey: SettingsKey.availabilityAutoCheckEnabled) }
            ))

            if settings.bool(forKey: SettingsKey.availabilityAutoCheckEnabled) {
                Stepper(
                    "Check every \(settings.int(forKey: SettingsKey.availabilityAutoCheckIntervalDays)) day(s)",
                    value: Binding(
                        get: { settings.int(forKey: SettingsKey.availabilityAutoCheckIntervalDays) },
                        set: { settings.setInt($0, forKey: SettingsKey.availabilityAutoCheckIntervalDays) }
                    ),
                    in: 1 ... 30
                )

                HStack {
                    Button {
                        Task { await runAvailabilityCheck() }
                    } label: {
                        if isRunningAvailabilityCheck {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("Run Check Now", systemImage: "arrow.clockwise")
                        }
                    }
                    .disabled(isRunningAvailabilityCheck)

                    if let msg = availabilityCheckMessage {
                        Spacer()
                        Text(msg)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }

                if let lastCheck = lastAutoCheckDate {
                    LabeledContent("Last check") {
                        Text(lastCheck.formatted())
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Stepper(
                "Mark postings stale after \(settings.int(forKey: SettingsKey.availabilityStaleDays)) days",
                value: Binding(
                    get: { settings.int(forKey: SettingsKey.availabilityStaleDays) },
                    set: { settings.setInt($0, forKey: SettingsKey.availabilityStaleDays) }
                ),
                in: 7 ... 90
            )
        }
    }

    // MARK: - Custom extraction instructions

    private var customExtractionSection: some View {
        Section("Custom Extraction Instructions") {
            Text("Extra instructions appended to the LLM job extraction prompt (markdown supported).")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextEditor(text: $customJDText)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 80, maxHeight: 200)
                .border(Color(NSColor.separatorColor), width: 0.5)
                .onChange(of: customJDText) { _, new in
                    try? settings.set(new, forKey: SettingsKey.jobDescriptionMarkdown)
                }
        }
    }

    // TASK-606: personal details the Codex auto-apply prompt uses to fill application fields.
    private var applicationDetailsSection: some View {
        Section("Application Details") {
            Text("Personal details the AI \"Auto-Apply (Codex)\" prompt uses to fill application fields "
                + "(name, contact info, address, links, work authorization, voluntary EEO answers). "
                + "Stored only on this Mac; the app never sends it anywhere — but note it's copied into "
                + "the prompt you paste into Codex.")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextEditor(text: $applicationDetailsText)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 120, maxHeight: 260)
                .border(Color(NSColor.separatorColor), width: 0.5)
                .onChange(of: applicationDetailsText) { _, new in
                    try? settings.set(new, forKey: SettingsKey.applicationPersonalInfo)
                }
        }
    }

    // MARK: - Helpers

    private var lastAutoCheckDate: Date? {
        let str = settings.string(forKey: SettingsKey.availabilityLastAutoCheckAt)
        guard !str.isEmpty else { return nil }
        return ISO8601DateFormatter().date(from: str)
    }

    private func runAvailabilityCheck() async {
        isRunningAvailabilityCheck = true
        availabilityCheckMessage = nil
        defer { isRunningAvailabilityCheck = false }

        let eligible = allJobs.filter { $0.status == .pursuing || $0.status == .applied }
        guard !eligible.isEmpty else {
            availabilityCheckMessage = "No Interested or Applied jobs to check"
            return
        }

        availabilityCheckMessage = "Checking \(eligible.count) jobs…"
        let sweep = await AvailabilityChecker.findGoneJobsRotating(eligible, settings: settings)

        let now = ISO8601DateFormatter().string(from: Date())
        try? settings.set(now, forKey: SettingsKey.availabilityLastAutoCheckAt)

        let store = appServices.backgroundStore
        let outcomes = sweep.outcomes
        Task.detached { try? await store.recordAvailabilityOutcomes(outcomes) }

        unverifiedJobs = sweep.unverified
        lastCheckedCount = sweep.checkedCount
        lastPlannedCount = eligible.count
        if sweep.gone.isEmpty {
            // Never claim jobs are "still available" when some were never actually reached — a
            // bot-challenged or rate-limited posting is unknown, not live.
            // Same rule as the Jobs list: the checker reports what it reached, so an all-clear can
            // only be claimed when every job handed in was genuinely checked.
            let verified = sweep.checkedCount
            var message = verified == eligible.count
                ? "All \(eligible.count) jobs are still available"
                : "No expired postings found — \(verified) of \(eligible.count) verified"
            if let summary = sweep.unverifiedSummary { message += ". \(summary)" }
            availabilityCheckMessage = message
        } else {
            goneJobs = sweep.gone
            showingExpiredConfirmation = true
            availabilityCheckMessage = nil
        }
    }

    private func markExpired(_ jobs: [GoneJobResult]) {
        showingExpiredConfirmation = false
        let ids = jobs.map(\.jobID)
        let count = ids.count
        // TASK-515: await the result and only report success once it actually succeeds — the old
        // `try?` + immediate "marked expired" message reported success even when the write failed.
        Task {
            do {
                try await appServices.jobService.markExpired(jobIDs: ids)
                availabilityCheckMessage = "\(count) job(s) marked expired"
            } catch {
                availabilityCheckMessage = "Couldn't mark jobs expired: \(error.localizedDescription)"
            }
        }
    }
}

// MARK: - ExpiredConfirmationSheet

/// Internal (not private) so the main-window availability check (ContentView) can present it too.
struct ExpiredConfirmationSheet: View {
    let goneJobs: [GoneJobResult]
    /// Jobs the sweep could not verify either way. Shown so the result never reads as an exhaustive
    /// "these are the only expired ones" — a check that was blocked proves nothing.
    let unverifiedJobs: [UnverifiedJobResult]
    /// How many postings this run actually reached, and how many it set out to reach. Both are needed
    /// to say what "7 gone" is 7 *out of* — without that the result reads as a verdict on the whole
    /// view, which it never is.
    let checkedCount: Int
    let plannedCount: Int
    /// Jobs an EARLIER check had already flagged gone, and when each job was last checked (TASK-674).
    ///
    /// Without this the list answers "what is gone" but not "what is new", which is the question a
    /// user re-running a check actually has — and the reason two runs over an unchanged archive
    /// reporting different counts felt like a bug rather than a rotation.
    var previouslyFlagged: Set<String> = []
    var lastCheckedByJob: [String: Date] = [:]
    let onConfirm: ([GoneJobResult]) -> Void
    let onDismiss: () -> Void

    @State private var selected: Set<String>
    @State private var showingUnverifiedDetail = false

    init(
        goneJobs: [GoneJobResult],
        unverifiedJobs: [UnverifiedJobResult] = [],
        checkedCount: Int = 0,
        plannedCount: Int = 0,
        previouslyFlagged: Set<String> = [],
        lastCheckedByJob: [String: Date] = [:],
        onConfirm: @escaping ([GoneJobResult]) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.goneJobs = goneJobs
        self.unverifiedJobs = unverifiedJobs
        self.checkedCount = checkedCount
        self.plannedCount = plannedCount
        self.previouslyFlagged = previouslyFlagged
        self.lastCheckedByJob = lastCheckedByJob
        self.onConfirm = onConfirm
        self.onDismiss = onDismiss
        _selected = State(initialValue: Set(goneJobs.map(\.jobID)))
    }

    /// What this run covered, stated in the header rather than left to be inferred.
    ///
    /// "7 postings appear to be gone" out of an archive of 400 invites exactly one question — is that
    /// really all? — and the answer (how many were actually reached, and how many couldn't be) was
    /// sitting below the results inside the scroll view, where nobody scrolls past a checklist to
    /// find it. A months-old posting that answers 200 from a client-rendered page is *unverified*,
    /// not alive, and that distinction is the whole basis for trusting a short list.
    private var coverageLine: String? {
        guard checkedCount > 0 || plannedCount > 0 else { return nil }
        var parts = ["\(checkedCount) checked"]
        let deferred = unverifiedJobs.count(where: { $0.reason == .notCheckedThisRun })
        if deferred > 0 {
            parts.append("\(deferred) held for a later run")
        }
        let unresolved = unverifiedJobs.count - deferred
        if unresolved > 0 {
            parts.append("\(unresolved) couldn't be verified")
        }
        return parts.joined(separator: " · ")
    }

    private var sweep: AvailabilitySweep {
        AvailabilitySweep(gone: goneJobs, unverified: unverifiedJobs)
    }

    /// Header and footer are pinned outside the scroll view, and the sheet's height is bounded.
    ///
    /// This was one unbounded `VStack` with a row per result. That reads fine for the two or three
    /// gone jobs the scheduled sweep turns up, but the on-demand archive check found ~100 at once and
    /// the sheet simply grew past the bottom of the screen — no scrolling, and the Mark Expired and
    /// Dismiss buttons unreachable, so the only exit was cancelling the whole check.
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                resultsList
                    .padding(20)
            }
            Divider()
            footer
        }
        // Bounded so a large result set scrolls instead of growing off-screen. idealHeight keeps the
        // common small-result case from opening as a mostly-empty tall sheet.
        .frame(minWidth: 520, idealWidth: 620, minHeight: 360, idealHeight: 560, maxHeight: 720)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Jobs No Longer Available")
                .font(.headline)
            Text(
                "\(goneJobs.count) posting\(goneJobs.count == 1 ? "" : "s") appear to be gone. "
                    + "Select which to mark as Expired."
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)

            // Pinned, not buried below the results: this is what qualifies the number above it.
            if let coverageLine {
                Label(coverageLine, systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Ticking or clearing ~100 checkboxes by hand is not a workflow.
            if goneJobs.count > 1 {
                HStack(spacing: 12) {
                    Button("Select All") { selected = Set(goneJobs.map(\.jobID)) }
                        .disabled(selected.count == goneJobs.count)
                    Button("Deselect All") { selected = [] }
                        .disabled(selected.isEmpty)
                    Spacer()
                    Text("\(selected.count) of \(goneJobs.count) selected")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.link)
                .font(.caption)
            }
        }
        .padding(20)
    }

    private var footer: some View {
        HStack {
            Button("Dismiss") { onDismiss() }
                .buttonStyle(.bordered)
            Spacer()
            Button("Mark \(selected.count) Expired") {
                let toMark = goneJobs.filter { selected.contains($0.jobID) }
                onConfirm(toMark)
            }
            .buttonStyle(.borderedProminent)
            .disabled(selected.isEmpty)
        }
        .padding(20)
    }

    private var resultsList: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(spacing: 0) {
                ForEach(goneJobs, id: \.jobID) { job in
                    HStack(alignment: .top, spacing: 10) {
                        Toggle("", isOn: Binding(
                            get: { selected.contains(job.jobID) },
                            set: { if $0 { selected.insert(job.jobID) } else { selected.remove(job.jobID) } }
                        ))
                        .labelsHidden()
                        .padding(.top, 2)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(jobLabel(job)).font(.body)
                            if let company = job.company, !company.isEmpty {
                                Text(company).font(.callout).fontWeight(.medium)
                            }
                            Text(friendlyReason(job.reason))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            // "Is this new?" is the question a re-run actually has (TASK-674).
                            Text(historyNote(job))
                                .font(.caption2)
                                .foregroundStyle(
                                    previouslyFlagged.contains(job.jobID) ? Color.secondary : Color.blue
                                )
                            Link(job.url.absoluteString, destination: job.url)
                                .font(.caption2)
                                .foregroundStyle(.blue)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            // LinkedIn's guest pages are the least trustworthy "gone" signal we have:
                            // it rate-limits background checks and serves a generic/feed page that can
                            // read as removed while the posting is still live. Say so rather than let
                            // the user expire a live job (TASK-643 pacing exists for the same reason).
                            if AvailabilityChecker.isLinkedInURL(job.url) {
                                Label(
                                    "LinkedIn often hides postings from signed-out checks — "
                                        + "open it to confirm before expiring.",
                                    systemImage: "exclamationmark.triangle"
                                )
                                .font(.caption2)
                                .foregroundStyle(.orange)
                                .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Spacer()
                    }
                    .padding(.vertical, 8)

                    if job.jobID != goneJobs.last?.jobID {
                        Divider()
                    }
                }
            }
            .padding(10)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            if let summary = sweep.unverifiedSummary {
                VStack(alignment: .leading, spacing: 6) {
                    Label(summary, systemImage: "questionmark.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(showingUnverifiedDetail ? "Hide details" : "Show details") {
                        showingUnverifiedDetail.toggle()
                    }
                    .buttonStyle(.link)
                    .font(.caption)

                    if showingUnverifiedDetail {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(unverifiedJobs, id: \.jobID) { job in
                                Text("\(unverifiedLabel(job)) — \(job.reason.summary)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                        .padding(.leading, 4)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    /// Whether this posting is a new finding or one an earlier check already flagged.
    private func historyNote(_ job: GoneJobResult) -> String {
        guard previouslyFlagged.contains(job.jobID) else { return "New since your last check" }
        guard let checked = lastCheckedByJob[job.jobID] else { return "Also flagged by an earlier check" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return "Also flagged \(formatter.localizedString(for: checked, relativeTo: Date()))"
    }

    private func jobLabel(_ job: GoneJobResult) -> String {
        if let num = job.jobNumber { return "#\(num) \(job.title)" }
        return job.title
    }

    private func unverifiedLabel(_ job: UnverifiedJobResult) -> String {
        let name = [job.company, job.title].compactMap(\.self).filter { !$0.isEmpty }.joined(separator: " — ")
        if let num = job.jobNumber { return "#\(num) \(name)" }
        return name
    }

    private func friendlyReason(_ reason: String) -> String {
        if reason.hasPrefix("HTTP 404") || reason.hasPrefix("HTTP 410") { return "Listing removed (404)" }
        if reason.hasPrefix("HTTP") { return reason }
        if reason.hasPrefix("body:") { return "Page content indicates listing is gone" }
        if reason.hasPrefix("redirected to non-job page") { return "Redirected away from job listing" }
        if reason.hasPrefix("redirected page missing title") { return "Redirect destination has no job title" }
        return reason
    }
}
