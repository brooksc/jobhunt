import AppKit
import JobhuntCore
import SwiftData
import SwiftUI
import UserNotifications

struct DebugTab: View {
    @Query private var jobs: [Job]
    @Query private var captures: [Capture]
    @Query private var resumes: [Resume]
    @Query private var sites: [Site]
    @Query private var llmRequests: [LLMRequest]
    @Query private var attempts: [LLMRequestAttempt]

    @Environment(AppServices.self) private var appServices
    @Environment(Router.self) private var router

    var body: some View {
        Form {
            jobStatsSection
            entityCountsSection
            llmStatsSection
            fitScoresSection
            settingsErrorSection
            recentErrorsSection
            diagnosticsSection
        }
        .formStyle(.grouped)
    }

    // MARK: - LLM stats (prompt size + processing time)

    private var llmStatsSection: some View {
        let promptChars = attempts.compactMap(\.promptChars).filter { $0 > 0 }
        let responseChars = attempts.compactMap(\.responseChars).filter { $0 > 0 }
        let durations = attempts.compactMap(\.durationMs).filter { $0 > 0 }
        return Section("LLM Stats") {
            LabeledContent("Attempts recorded") {
                Text("\(attempts.count)").foregroundStyle(.secondary).monospacedDigit()
            }
            statRow("Prompt chars (avg / max)", avg: average(promptChars), max: promptChars.max())
            statRow("Response chars (avg / max)", avg: average(responseChars), max: responseChars.max())
            statRow("Processing ms (avg / max)", avg: average(durations), max: durations.max())
        }
    }

    private func statRow(_ label: String, avg: Int?, max: Int?) -> some View {
        LabeledContent(label) {
            Text(avg == nil ? "—" : "\(avg!) / \(max ?? 0)")
                .foregroundStyle(.secondary).monospacedDigit()
        }
    }

    private func average(_ values: [Int]) -> Int? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / values.count
    }

    // MARK: - Fit scores (no-LLM recompute)

    private var fitScoresSection: some View {
        Section("Fit Scores") {
            Button("Recompute from Saved Data (no LLM)") {
                Task {
                    do {
                        let n = try await appServices.jobService.recomputeAllFitScores()
                        appServices.toastStore.show("Recomputed \(n) fit score\(n == 1 ? "" : "s")")
                    } catch {
                        appServices.toastStore.show("Recompute failed: \(error.localizedDescription)", isError: true)
                    }
                }
            }
            Text(
                "Re-applies the current scoring weights and penalties to already-scored jobs, without calling the LLM."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Job stats by status

    private var jobStatsSection: some View {
        Section("Jobs by Status") {
            ForEach(JobStatus.allCases, id: \.self) { status in
                let count = jobs.count(where: { $0.status == status })
                LabeledContent(status.rawValue.capitalized) {
                    Text("\(count)")
                        .foregroundStyle(count > 0 ? .primary : .tertiary)
                        .monospacedDigit()
                }
            }
            LabeledContent("Total") {
                Text("\(jobs.count)")
                    .fontWeight(.semibold)
                    .monospacedDigit()
            }
        }
    }

    // MARK: - Entity counts

    private var entityCountsSection: some View {
        Section("Database") {
            LabeledContent("Captures") {
                Text("\(captures.count)").foregroundStyle(.secondary).monospacedDigit()
            }
            LabeledContent("Resumes") {
                Text("\(resumes.count)").foregroundStyle(.secondary).monospacedDigit()
            }
            LabeledContent("Sites") {
                Text("\(sites.count)").foregroundStyle(.secondary).monospacedDigit()
            }
            LabeledContent("Extraction pending") {
                let pending = jobs.count(where: { $0.extractionStatus == .pending })
                Text("\(pending)").foregroundStyle(.secondary).monospacedDigit()
            }
            LabeledContent("Extraction failed") {
                let failed = jobs.count(where: { $0.extractionStatus == .failed })
                Text("\(failed)")
                    .foregroundStyle(failed > 0 ? .red : .secondary)
                    .monospacedDigit()
            }
        }
    }

    // MARK: - Settings persistence error

    @ViewBuilder
    private var settingsErrorSection: some View {
        if let err = appServices.settings.lastSettingsError {
            Section("Settings Error") {
                Text(err)
                    .font(.callout)
                    .foregroundStyle(.red)
            }
        }
    }

    // MARK: - Recent errors

    @ViewBuilder
    private var recentErrorsSection: some View {
        let errors = appServices.toastStore.recentErrors
        if !errors.isEmpty {
            Section("Recent Errors (last \(errors.count))") {
                ForEach(errors.reversed()) { record in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(record.message)
                            .font(.callout)
                        Text(record.timestamp.formatted(date: .omitted, time: .standard))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    // MARK: - Copy diagnostics

    private var diagnosticsSection: some View {
        Section("Support") {
            Button("Copy Diagnostics") {
                copyDiagnostics()
            }
            .help(
                "Copies system info, queue counts, and recent error messages. Sensitive values " +
                    "(file paths, URL query strings, API keys/tokens) are redacted on a best-effort " +
                    "basis. Does not include job descriptions or resume content. Review before sharing."
            )
            // TASK-464: re-present the onboarding flow (preview — leaves the completion flag set).
            Button("Reopen Onboarding") {
                NotificationCenter.default.post(name: .reopenOnboarding, object: nil)
            }
            .help("Show the first-run setup flow again. Dismissing keeps your setup; this is just a preview.")

            // Clear the first-run flag so the wizard behaves exactly as it does on a brand-new
            // install (re-presents now, and again on next launch until completed).
            Button("Reset First-Run Setup") {
                appServices.settings.set("", forKey: "onboarding_complete")
                NotificationCenter.default.post(name: .reopenOnboarding, object: nil)
            }
            .help("Clears the onboarding-complete flag and re-presents the first-run wizard, as on a fresh install.")

            // Delivery smoke test (TASK-542): OS notification delivery can't be unit-tested, so this
            // posts one immediately and logs the auth status, to tell "we never post" apart from
            // "macOS suppressed it" (Focus / alert style / signing-reset authorization).
            Button("Send Test Notification") {
                sendTestNotification()
            }
            .help("Posts a notification now to verify macOS delivery. If nothing appears, check " +
                "System Settings → Notifications → Jobhunt, turn off Do Not Disturb / Focus, and see " +
                "the Console for 'Jobhunt test-notification' lines (auth status + add() result).")

            Divider()
            Button("Hide Debug Tab") {
                router.settingsTab = .general
                appServices.settings.setBool(true, forKey: SettingsKey.hideDebugTab)
            }
            .help("Removes this tab from Settings. Re-enable it from General → Show Debug tab.")
        }
    }

    private func sendTestNotification() {
        let center = UNUserNotificationCenter.current()
        // Log current authorization so a "not seeing it" report can be diagnosed from Console.
        center.getNotificationSettings { settings in
            NSLog(
                "Jobhunt test-notification: authStatus=\(settings.authorizationStatus.rawValue) " +
                    "alertSetting=\(settings.alertSetting.rawValue) " +
                    "notificationCenter=\(settings.notificationCenterSetting.rawValue)"
            )
        }
        // Request authorization in case a rebuild reset it (ad-hoc signing changes the identity).
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            NSLog(
                "Jobhunt test-notification: requestAuthorization granted=\(granted) error=\(String(describing: error))"
            )
        }
        let content = UNMutableNotificationContent()
        content.title = "Jobhunt test notification"
        content.body = "If you can see this, macOS notification delivery is working."
        content.sound = .default
        let request = UNNotificationRequest(identifier: "jobhunt-test-notification", content: content, trigger: nil)
        center.add(request) { error in
            if let error {
                NSLog("Jobhunt test-notification: add() FAILED: \(error)")
            } else {
                NSLog("Jobhunt test-notification: add() succeeded")
            }
        }
    }

    private func copyDiagnostics() {
        let bundle = buildDiagnosticsText()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(bundle, forType: .string)
    }

    private func buildDiagnosticsText() -> String {
        let info = Bundle.main.infoDictionary ?? [:]
        let appVersion = info["CFBundleShortVersionString"] as? String ?? "unknown"
        let buildNumber = info["CFBundleVersion"] as? String ?? "unknown"
        let macOSVersion = ProcessInfo.processInfo.operatingSystemVersionString

        let settings = appServices.settings
        let providerType = settings.llmProvider
        let modelName = settings.llmModel
        let consentGranted = ConsentHelper.isConsented(provider: providerType, settings: settings)
        let queuePaused = settings.llmQueuePaused

        let serverStatus = appServices.serverRunning ? "running" : "stopped"
        let serverError = appServices.serverError.map { " (error: \(DiagnosticsRedactor.redact($0)))" } ?? ""

        let queued = llmRequests.count(where: { $0.status == .queued })
        let processing = llmRequests.count(where: { $0.status == .running })
        let failed = llmRequests.count(where: { $0.status == .failed || $0.status == .retryExhausted })

        let errors = appServices.toastStore.recentErrors
        let errorLines = errors.isEmpty
            ? "  (none)"
            : errors.map {
                "  [\($0.timestamp.formatted(date: .omitted, time: .standard))] \(DiagnosticsRedactor.redact($0.message))"
            }
            .joined(separator: "\n")

        return """
        === Jobhunt Diagnostics ===
        App version:        \(appVersion) (\(buildNumber))
        macOS:              \(macOSVersion)

        === LLM ===
        Provider:           \(providerType)
        Model:              \(modelName)
        Consent granted:    \(consentGranted)
        Queue paused:       \(queuePaused)

        === Server ===
        Status:             \(serverStatus)\(serverError)

        === LLM Queue ===
        Queued:             \(queued)
        Processing:         \(processing)
        Failed:             \(failed)

        === Recent Errors ===
        \(errorLines)
        """
    }
}
