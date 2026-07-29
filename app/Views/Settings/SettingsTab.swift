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

    @Environment(AppServices.self) private var appServices
    @Query private var allJobs: [Job]

    var body: some View {
        Form {
            locationSection
            requirementsSection
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
        let (enabled, remote) = (settings.locationFilterEnabled, settings.locationAllowRemote)
        let (hybrid, onsite) = (settings.locationAllowHybrid, settings.locationAllowOnsite)
        do {
            let changed = try await appServices.backgroundStore.recomputeMeetsCriteria(
                preferredLocations: preferred, allowRemote: remote, allowHybrid: hybrid,
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
                    settings.set(new, forKey: SettingsKey.jobDescriptionMarkdown)
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
                    settings.set(new, forKey: SettingsKey.applicationPersonalInfo)
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
        settings.set(now, forKey: SettingsKey.availabilityLastAutoCheckAt)

        unverifiedJobs = sweep.unverified
        if sweep.gone.isEmpty {
            // Never claim jobs are "still available" when some were never actually reached — a
            // bot-challenged or rate-limited posting is unknown, not live.
            let verified = eligible.count - sweep.unverified.count
            var message = sweep.unverified.isEmpty
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

// MARK: - Data tab (backup & restore)

struct DataSettingsTab: View {
    @State private var showingRestoreConfirmation = false
    @State private var pendingRestoreURL: URL?

    @Environment(AppServices.self) private var appServices

    var body: some View {
        Form {
            dataSection
        }
        .formStyle(.grouped)
        .confirmationDialog(
            "Replace Current Data?",
            isPresented: $showingRestoreConfirmation,
            titleVisibility: .visible
        ) {
            Button("Restore and Relaunch", role: .destructive) {
                if let url = pendingRestoreURL { performRestore(from: url) }
            }
            Button("Cancel", role: .cancel) { pendingRestoreURL = nil }
        } message: {
            Text(
                "All current jobs, captures, settings, and resumes will be replaced with the backup. " +
                    "A pre-restore backup will be saved automatically. " +
                    "API keys are not part of the backup (they live in the Keychain) — you may need to " +
                    "re-enter them in AI Provider settings afterward. " +
                    "The app must relaunch to apply the restored data."
            )
        }
    }

    private var dataSection: some View {
        Section("Data") {
            HStack {
                Button {
                    backUpData()
                } label: {
                    Label("Back Up Data…", systemImage: "externaldrive.badge.checkmark")
                }

                Spacer()

                Button(role: .destructive) {
                    chooseRestoreFile()
                } label: {
                    Label("Restore from Backup…", systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                }
            }
            // TASK-378: the backup is the SQLite store only. API keys live in the macOS Keychain,
            // not the store, so they're never in the backup file — set this expectation up front.
            Text("Backups include all jobs, captures, resumes, and settings — but not your AI "
                + "provider API keys, which are stored separately in the macOS Keychain. After "
                + "restoring on a new Mac (or if the Keychain items are missing), re-enter them in "
                + "AI Provider settings.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Helpers

    private func backUpData() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "sqlite") ?? .data]
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        panel.nameFieldStringValue = "jobhunt-backup-\(formatter.string(from: Date())).sqlite"
        panel.title = "Save JobHunt Backup"
        panel.message = "Choose where to save the backup file."
        guard panel.runModal() == .OK, let dest = panel.url else { return }
        let storeURL = ModelContainerFactory.productionStoreURL()
        do {
            try BackupService.backup(storeURL: storeURL, to: dest)
            appServices.toastStore.show("Backup saved to \(dest.lastPathComponent)")
        } catch {
            appServices.toastStore.show("Backup failed: \(error.localizedDescription)", isError: true)
        }
    }

    private func chooseRestoreFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "sqlite") ?? .data]
        panel.title = "Select Backup to Restore"
        panel.message = "Choose a .sqlite backup file created by JobHunt."
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }

        guard BackupService.isValidSQLite(at: url) else {
            appServices.toastStore.show(
                "The selected file is not a valid SQLite backup.", isError: true
            )
            return
        }

        pendingRestoreURL = url
        showingRestoreConfirmation = true
    }

    private func performRestore(from backupURL: URL) {
        let storeURL = ModelContainerFactory.productionStoreURL()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let safetyBackupURL = storeURL.deletingLastPathComponent()
            .appendingPathComponent("pre-restore-\(formatter.string(from: Date())).sqlite")
        pendingRestoreURL = nil

        // Restore is async because it must QUIESCE runtime writers before swapping the single-writer
        // store (TASK-546): RestoreCoordinator stops the LLM queue / availability loop / local server
        // via appServices.shutdown(), then safety-backs-up, then replaces the store. On success or any
        // failure the app quits so the next launch opens a known store with a clean runtime — never
        // left half-restored with a partially-quiesced runtime.
        Task { @MainActor in
            do {
                try await RestoreCoordinator.perform(
                    backupURL: backupURL,
                    storeURL: storeURL,
                    safetyBackupURL: safetyBackupURL,
                    quiesceRuntime: { await appServices.shutdown() }
                )
            } catch let err as RestoreCoordinator.StageError {
                presentRestoreFailureThenQuit(stage: err.stage, error: err.underlying)
                return
            } catch {
                presentRestoreFailureThenQuit(stage: .restore, error: error)
                return
            }

            // Restore is on disk; the live container still sees old data. Quit so the next launch
            // opens the restored store cleanly (runtime is already quiesced).
            let alert = NSAlert()
            alert.messageText = "Restore Complete"
            alert.informativeText =
                "Your data has been restored from \(backupURL.lastPathComponent). " +
                "If your AI provider API keys are missing after relaunch, re-enter them in " +
                "AI Provider settings — they're kept in the Keychain, not the backup. " +
                "The app will now quit and must be relaunched to load the restored data."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "Quit Now")
            alert.runModal()
            NSApp.terminate(nil)
        }
    }

    /// Report a restore-stage failure and quit. Runtime is already quiesced, so relaunching restores
    /// normal operation against a known store (unchanged on a safety-backup failure; the safety backup
    /// is on disk if the swap itself failed).
    private func presentRestoreFailureThenQuit(stage: RestoreCoordinator.Stage, error: Error) {
        let alert = NSAlert()
        switch stage {
        case .safetyBackup:
            alert.messageText = "Safety Backup Failed"
            alert.informativeText =
                "Could not create a pre-restore safety backup, so the restore was aborted and your data " +
                "is unchanged. Free up disk space and try again. The app will now quit; relaunch to " +
                "resume.\n\nError: \(error.localizedDescription)"
        case .restore:
            alert.messageText = "Restore Failed"
            alert.informativeText =
                "The restore did not complete. A pre-restore safety backup was saved, so your original " +
                "data should be intact. The app will now quit; relaunch to resume.\n\nError: " +
                "\(error.localizedDescription)"
        }
        alert.alertStyle = .critical
        alert.addButton(withTitle: "Quit Now")
        alert.runModal()
        NSApp.terminate(nil)
    }
}

// MARK: - ExpiredConfirmationSheet

/// Internal (not private) so the main-window availability check (ContentView) can present it too.
struct ExpiredConfirmationSheet: View {
    let goneJobs: [GoneJobResult]
    /// Jobs the sweep could not verify either way. Shown so the result never reads as an exhaustive
    /// "these are the only expired ones" — a check that was blocked proves nothing.
    let unverifiedJobs: [UnverifiedJobResult]
    let onConfirm: ([GoneJobResult]) -> Void
    let onDismiss: () -> Void

    @State private var selected: Set<String>
    @State private var showingUnverifiedDetail = false

    init(
        goneJobs: [GoneJobResult],
        unverifiedJobs: [UnverifiedJobResult] = [],
        onConfirm: @escaping ([GoneJobResult]) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.goneJobs = goneJobs
        self.unverifiedJobs = unverifiedJobs
        self.onConfirm = onConfirm
        self.onDismiss = onDismiss
        _selected = State(initialValue: Set(goneJobs.map(\.jobID)))
    }

    private var sweep: AvailabilitySweep {
        AvailabilitySweep(gone: goneJobs, unverified: unverifiedJobs)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Jobs No Longer Available")
                .font(.headline)
            Text(
                "\(goneJobs.count) of your Interested or Applied jobs appear to be gone. "
                    + "Select which to mark as Expired."
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)

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
        }
        .padding(20)
        .frame(minWidth: 460)
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
