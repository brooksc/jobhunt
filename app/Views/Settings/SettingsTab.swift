import AppKit
import JobhuntCore
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct SettingsTab: View {
    let settings: SettingsStore

    @State private var isRunningAvailabilityCheck = false
    @State private var availabilityCheckMessage: String?
    @State private var customJDText: String = ""
    @State private var goneJobs: [GoneJobResult] = []
    @State private var showingExpiredConfirmation = false
    @State private var showingRestoreConfirmation = false
    @State private var pendingRestoreURL: URL?

    @Environment(Theme.self) private var theme
    @Environment(AppServices.self) private var appServices
    @Query private var allJobs: [Job]

    var body: some View {
        Form {
            appearanceSection
            locationSection
            intervalsSection
            availabilitySection
            customExtractionSection
            dataSection
            appInfoSection
        }
        .formStyle(.grouped)
        .onAppear {
            customJDText = settings.string(forKey: SettingsKey.jobDescriptionMarkdown)
        }
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
                "The app must relaunch to apply the restored data."
            )
        }
        .sheet(isPresented: $showingExpiredConfirmation) {
            ExpiredConfirmationSheet(
                goneJobs: goneJobs,
                onConfirm: { markExpired($0) },
                onDismiss: {
                    showingExpiredConfirmation = false
                    availabilityCheckMessage = "\(goneJobs.count) potential expiration(s) — none marked"
                }
            )
        }
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

    // MARK: - Data section

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
        }
    }

    // MARK: - Helpers

    private var lastAutoCheckDate: Date? {
        let str = settings.string(forKey: SettingsKey.availabilityLastAutoCheckAt)
        guard !str.isEmpty else { return nil }
        return ISO8601DateFormatter().date(from: str)
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    private var appBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }

    private func runAvailabilityCheck() async {
        isRunningAvailabilityCheck = true
        availabilityCheckMessage = nil
        defer { isRunningAvailabilityCheck = false }

        let pursuing = allJobs.filter { $0.status == .pursuing }
        guard !pursuing.isEmpty else {
            availabilityCheckMessage = "No pursuing jobs to check"
            return
        }

        availabilityCheckMessage = "Checking \(pursuing.count) jobs…"
        let found = await AvailabilityChecker.findGoneJobs(pursuing)

        let now = ISO8601DateFormatter().string(from: Date())
        settings.set(now, forKey: SettingsKey.availabilityLastAutoCheckAt)

        if found.isEmpty {
            availabilityCheckMessage = "All \(pursuing.count) jobs are still available"
        } else {
            goneJobs = found
            showingExpiredConfirmation = true
            availabilityCheckMessage = nil
        }
    }

    private func backUpData() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "sqlite") ?? .data]
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        panel.nameFieldStringValue = "jobhunt-backup-\(formatter.string(from: Date())).sqlite"
        panel.title = "Save Jobhunt Backup"
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
        panel.message = "Choose a .sqlite backup file created by Jobhunt."
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

        // Auto-backup current data before replacing.
        // If the safety backup fails, abort — do not proceed with a destructive restore.
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let autoBackupURL = storeURL.deletingLastPathComponent()
            .appendingPathComponent("pre-restore-\(formatter.string(from: Date())).sqlite")

        do {
            try BackupService.backup(storeURL: storeURL, to: autoBackupURL)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Safety Backup Failed"
            alert.informativeText =
                "Could not create a pre-restore safety backup. Restore aborted. " +
                "Please free up disk space and try again.\n\nError: \(error.localizedDescription)"
            alert.alertStyle = .critical
            alert.addButton(withTitle: "OK")
            alert.runModal()
            pendingRestoreURL = nil
            return
        }

        do {
            try BackupService.restore(from: backupURL, to: storeURL)
        } catch {
            appServices.toastStore.show("Restore failed: \(error.localizedDescription)", isError: true)
            pendingRestoreURL = nil
            return
        }

        pendingRestoreURL = nil

        // Restore is on disk; the live container still sees old data.
        // Terminate immediately — the user must relaunch to load the restored data.
        let alert = NSAlert()
        alert.messageText = "Restore Complete"
        alert.informativeText =
            "Your data has been restored from \(backupURL.lastPathComponent). " +
            "The app will now quit and must be relaunched to load the restored data."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Quit Now")
        alert.runModal()
        NSApp.terminate(nil)
    }

    private func markExpired(_ jobs: [GoneJobResult]) {
        showingExpiredConfirmation = false
        let ids = jobs.map(\.jobID)
        let count = ids.count
        Task { try? await appServices.jobService.markExpired(jobIDs: ids) }
        availabilityCheckMessage = "\(count) job(s) marked expired"
    }
}

// MARK: - ExpiredConfirmationSheet

private struct ExpiredConfirmationSheet: View {
    let goneJobs: [GoneJobResult]
    let onConfirm: ([GoneJobResult]) -> Void
    let onDismiss: () -> Void

    @State private var selected: Set<String>

    init(goneJobs: [GoneJobResult], onConfirm: @escaping ([GoneJobResult]) -> Void, onDismiss: @escaping () -> Void) {
        self.goneJobs = goneJobs
        self.onConfirm = onConfirm
        self.onDismiss = onDismiss
        _selected = State(initialValue: Set(goneJobs.map(\.jobID)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Jobs No Longer Available")
                .font(.headline)
            Text("\(goneJobs.count) of your pursuing jobs appear to be gone. Select which to mark as Expired.")
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
                            Text(friendlyReason(job.reason))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Link(job.url.absoluteString, destination: job.url)
                                .font(.caption2)
                                .foregroundStyle(.blue)
                                .lineLimit(1)
                                .truncationMode(.middle)
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

    private func friendlyReason(_ reason: String) -> String {
        if reason.hasPrefix("HTTP 404") || reason.hasPrefix("HTTP 410") { return "Listing removed (404)" }
        if reason.hasPrefix("HTTP") { return reason }
        if reason.hasPrefix("body:") { return "Page content indicates listing is gone" }
        if reason.hasPrefix("redirected to non-job page") { return "Redirected away from job listing" }
        if reason.hasPrefix("redirected page missing title") { return "Redirect destination has no job title" }
        return reason
    }
}
