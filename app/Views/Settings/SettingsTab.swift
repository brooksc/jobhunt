import JobhuntCore
import SwiftData
import SwiftUI

struct SettingsTab: View {
    let settings: SettingsStore

    @State private var isRunningAvailabilityCheck = false
    @State private var availabilityCheckMessage: String?
    @State private var customJDText: String = ""
    @State private var goneJobs: [GoneJobResult] = []
    @State private var showingExpiredConfirmation = false

    @Environment(Theme.self) private var theme
    @Environment(\.modelContext) private var modelContext
    @Query private var allJobs: [Job]

    var body: some View {
        Form {
            appearanceSection
            locationSection
            intervalsSection
            availabilitySection
            customExtractionSection
            appInfoSection
        }
        .formStyle(.grouped)
        .onAppear {
            customJDText = settings.string(forKey: SettingsKey.jobDescriptionMarkdown)
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
                TextField("Preferred metros (comma-separated)", text: Binding(
                    get: { settings.preferredMetros },
                    set: { settings.preferredMetros = $0 }
                ))
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

    private func markExpired(_ jobs: [GoneJobResult]) {
        showingExpiredConfirmation = false
        let ids = Set(jobs.map(\.jobID))
        for job in allJobs where ids.contains(job.id) {
            job.status = .expired
            job.updatedAt = Date()
        }
        try? modelContext.save()
        availabilityCheckMessage = "\(jobs.count) job(s) marked expired"
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
