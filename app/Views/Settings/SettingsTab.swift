import JobhuntCore
import SwiftUI

struct SettingsTab: View {
    let settings: SettingsStore

    @State private var isRunningAvailabilityCheck = false
    @State private var availabilityCheckMessage: String?
    @State private var customJDText: String = ""

    var body: some View {
        Form {
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
            }

            Stepper(
                "Mark postings stale after \(settings.int(forKey: SettingsKey.availabilityStaleDays)) days",
                value: Binding(
                    get: { settings.int(forKey: SettingsKey.availabilityStaleDays) },
                    set: { settings.setInt($0, forKey: SettingsKey.availabilityStaleDays) }
                ),
                in: 7 ... 90
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
        let now = ISO8601DateFormatter().string(from: Date())
        settings.set(now, forKey: SettingsKey.availabilityLastAutoCheckAt)
        availabilityCheckMessage = "Check started"
    }
}
