import AppKit
import JobhuntCore
import JobhuntServer
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

    /// The local server is an actor, so its port is loaded async into here on appear.
    @State private var serverPort: UInt16 = 0

    var body: some View {
        Form {
            environmentSection
            demoSection
            maintenanceSection
            llmStatsSection
            settingsErrorSection
            recentErrorsSection
            diagnosticsSection
        }
        .formStyle(.grouped)
        .task { serverPort = await appServices.server.port }
    }

    // MARK: - Environment (ground-truth runtime state that's hard to see elsewhere)

    private var environmentSection: some View {
        let storeURL = ModelContainerFactory.productionStoreURL()
        let settings = appServices.settings
        let queued = llmRequests.count(where: { $0.status == .queued })
        let running = llmRequests.count(where: { $0.status == .running })
        let failed = llmRequests.count(where: { $0.status == .failed || $0.status == .retryExhausted })
        let keyAvailability = settings.apiKeyAvailability(forProvider: settings.llmProvider)
        return Section("Environment") {
            LabeledContent("Store") {
                Text(storeURL.path)
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
            }
            LabeledContent("Store size") { mono(storeSizeString(storeURL)) }
            LabeledContent("Sandboxed") {
                Text(storeURL.path.contains("/Containers/") ? "Yes (MAS)" : "No (DMG)").foregroundStyle(.secondary)
            }
            LabeledContent("Data") {
                mono(
                    "\(jobs.count) jobs · \(captures.count) captures · \(resumes.count) résumés · \(sites.count) sites"
                )
            }

            Divider()
            LabeledContent("AI provider") { Text(settings.llmProvider).foregroundStyle(.secondary) }
            LabeledContent("AI model") {
                Text(settings.llmModel.isEmpty ? "—" : settings.llmModel).foregroundStyle(.secondary)
            }
            apiKeyRow(keyAvailability)
            statusRow("AI ready", ok: AIConfig.isConfigured(settings), okText: "Yes", badText: "No")

            Divider()
            statusRow(
                "Local server",
                ok: appServices.serverRunning,
                okText: "Running · port \(serverPort)",
                badText: appServices.serverError ?? "Stopped"
            )
            statusRow(
                "MCP token",
                ok: FileManager.default.fileExists(atPath: MCPTokenManager.tokenURL.path),
                okText: "Present",
                badText: "Missing"
            )
            LabeledContent("Queue") {
                mono("\(queued) queued · \(running) running · \(failed) failed" +
                    (settings.llmQueuePaused ? " · paused" : ""))
            }

            Button("Reveal Store in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([storeURL])
            }
        }
    }

    private func mono(_ string: String) -> some View {
        Text(string).foregroundStyle(.secondary).monospacedDigit()
    }

    /// Three-state API-key diagnostic (TASK-569): a Keychain read failure is shown distinctly from a
    /// genuinely unset key, with its OSStatus, so support can tell "no key" from "key inaccessible".
    private func apiKeyRow(_ availability: APIKeyAvailability) -> some View {
        let (text, icon, color): (String, String, Color) = switch availability {
        case .present: ("Present", "checkmark.circle.fill", .green)
        case .missing: ("Not set", "exclamationmark.triangle.fill", .orange)
        case let .unavailable(status): ("Unavailable (Keychain error \(status))", "xmark.octagon.fill", .red)
        }
        return LabeledContent("API key") {
            Label(text, systemImage: icon)
                .labelStyle(.titleAndIcon)
                .font(.caption)
                .foregroundStyle(color)
        }
    }

    private func statusRow(_ label: String, ok: Bool, okText: String, badText: String) -> some View {
        LabeledContent(label) {
            Label(ok ? okText : badText, systemImage: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .labelStyle(.titleAndIcon)
                .font(.caption)
                .foregroundStyle(ok ? Color.green : Color.orange)
        }
    }

    private func storeSizeString(_ url: URL) -> String {
        let fm = FileManager.default
        let total = [url.path, url.path + "-wal", url.path + "-shm"].reduce(Int64(0)) { sum, path in
            sum + ((try? fm.attributesOfItem(atPath: path))?[.size] as? Int64 ?? 0)
        }
        return ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
    }

    // MARK: - Maintenance (safe, recurring actions — NOT one-time data ops; those are CLI-only)

    private var maintenanceSection: some View {
        Section("Maintenance") {
            Button("Back Up Store Now") { backUpNow() }
                .help("Writes a timestamped snapshot to ~/Documents/jobhunt-backups (safe while the app runs).")

            Button("Recompute Fit Scores (no LLM)") {
                runMaintenance("Recomputed fit scores") {
                    let n = try await appServices.jobService.recomputeAllFitScores()
                    return "Recomputed \(n) fit score\(n == 1 ? "" : "s")"
                }
            }
            .help("Re-applies the current scoring weights to already-scored jobs, without calling the LLM.")

            Button("Requeue Stuck “Running”") {
                runMaintenance("Requeued stuck requests") {
                    try await appServices.queueActor.requeueRunningOnLaunch()
                    return "Requeued stuck requests"
                }
            }
            .help("Resets any request left in 'running' (e.g. after a crash) back to queued.")

            Button("Clear Finished Requests") {
                runMaintenance("Cleared finished requests") {
                    try await appServices.queueActor.clearCompleted()
                    return "Cleared finished requests"
                }
            }
            .help("Deletes completed / failed / cancelled rows from the LLM queue history.")

            Divider()
            Button("Seed Demo Data") {
                runMaintenance("Seeded demo data") {
                    try await DemoSeeder.seedDemo(into: appServices.backgroundStore)
                    return "Seeded demo data"
                }
            }
            .help(
                "Adds sample jobs / résumés / sites to THIS store, and only when it has no jobs yet — "
                    + "on a store with data it does nothing. To show the app to someone, use Demo Mode below."
            )
        }
    }

    // MARK: - Demo mode

    /// A demo can't swap the live store in place — SwiftData binds the container at launch, and the
    /// store is single-writer — so this opens a SECOND instance against the isolated demo store
    /// instead. That instance never touches Application Support, carries no API keys (settings come
    /// from its own store), and is wiped and re-seeded on every launch.
    private var demoSection: some View {
        Section("Demo Mode") {
            LabeledContent("This window") {
                Text(isDemoInstance ? "Demo data (isolated)" : "Your real data")
                    .foregroundStyle(isDemoInstance ? Color.orange : .secondary)
            }

            Button("Open Demo Window") { launchDemoInstance() }
                .help("Launches a second Jobhunt with ~15 sample jobs. Your real data is untouched.")

            Text(
                "Opens a second window with sample jobs across every status — for screen-sharing or "
                    + "showing someone the app. It uses a separate, throwaway store: nothing you do there "
                    + "affects your real data, and it resets each launch. Quit your real window first if "
                    + "you want browser capture to work in the demo, since only one can hold the local port."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var isDemoInstance: Bool {
        CommandLine.arguments.contains("--ui-test-store")
    }

    private func launchDemoInstance() {
        let config = NSWorkspace.OpenConfiguration()
        config.arguments = ["--ui-test-store", "--seed-demo-data"]
        // Without this the running instance is merely activated and the arguments are ignored.
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: config) { _, error in
            Task { @MainActor in
                if let error {
                    appServices.toastStore.show(
                        "Couldn't open demo window: \(error.localizedDescription)", isError: true
                    )
                } else {
                    appServices.toastStore.show("Demo window opened — your real data is untouched")
                }
            }
        }
    }

    /// Run an async maintenance action and toast the result/error.
    private func runMaintenance(_: String, _ action: @escaping () async throws -> String) {
        Task {
            do {
                let message = try await action()
                appServices.toastStore.show(message)
            } catch {
                appServices.toastStore.show("Failed: \(error.localizedDescription)", isError: true)
            }
        }
    }

    private func backUpNow() {
        let storeURL = ModelContainerFactory.productionStoreURL()
        Task {
            do {
                let dir = URL.homeDirectory.appending(path: "Documents/jobhunt-backups")
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyyMMdd-HHmmss"
                let dest = dir.appending(path: "jobhunt-\(formatter.string(from: Date())).store")
                try BackupService.backup(storeURL: storeURL, to: dest)
                appServices.toastStore.show("Backed up to \(dest.lastPathComponent)")
            } catch {
                appServices.toastStore.show("Backup failed: \(error.localizedDescription)", isError: true)
            }
        }
    }

    // MARK: - LLM stats (prompt size + processing time — aggregate diagnostics, not a view duplicate)

    private var llmStatsSection: some View {
        let promptChars = attempts.compactMap(\.promptChars).filter { $0 > 0 }
        let responseChars = attempts.compactMap(\.responseChars).filter { $0 > 0 }
        let durations = attempts.compactMap(\.durationMs).filter { $0 > 0 }
        // Actual provider-reported tokens, shown only when some provider supplied usage (TASK-538).
        let promptTokens = attempts.compactMap(\.promptTokens).filter { $0 > 0 }
        let completionTokens = attempts.compactMap(\.completionTokens).filter { $0 > 0 }
        return Section("LLM Stats") {
            LabeledContent("Attempts recorded") { mono("\(attempts.count)") }
            statRow("Prompt chars (avg / max)", avg: average(promptChars), max: promptChars.max())
            statRow("Response chars (avg / max)", avg: average(responseChars), max: responseChars.max())
            statRow("Processing ms (avg / max)", avg: average(durations), max: durations.max())
            if !promptTokens.isEmpty {
                statRow("Prompt tokens (avg / max)", avg: average(promptTokens), max: promptTokens.max())
            }
            if !completionTokens.isEmpty {
                statRow("Completion tokens (avg / max)", avg: average(completionTokens), max: completionTokens.max())
            }
        }
    }

    private func statRow(_ label: String, avg: Int?, max: Int?) -> some View {
        LabeledContent(label) {
            Text(avg.map { "\($0) / \(max ?? 0)" } ?? "—")
                .foregroundStyle(.secondary).monospacedDigit()
        }
    }

    private func average(_ values: [Int]) -> Int? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / values.count
    }

    // MARK: - Settings persistence error

    @ViewBuilder
    private var settingsErrorSection: some View {
        if let err = appServices.settings.lastSettingsError {
            Section("Settings Error") {
                Text(err).font(.callout).foregroundStyle(.red)
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
                        // Redact on display so a screenshot/screen-share of this support surface can't
                        // leak file paths / URLs / tokens — same classes as Copy Diagnostics (TASK-553).
                        Text(DiagnosticsRedactor.redact(record.message)).font(.callout)
                        Text(record.timestamp.formatted(date: .omitted, time: .standard))
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    // MARK: - Support / diagnostics

    private var diagnosticsSection: some View {
        Section("Support") {
            Button("Copy Diagnostics") { copyDiagnostics() }
                .help(
                    "Copies system info, queue counts, and recent error messages. Sensitive values " +
                        "(file paths, URL query strings, API keys/tokens) are redacted on a best-effort " +
                        "basis. Does not include job descriptions or resume content. Review before sharing."
                )

            // Delivery smoke test (TASK-542): OS notification delivery can't be unit-tested, so this
            // posts one immediately and logs the auth status, to tell "we never post" apart from
            // "macOS suppressed it" (Focus / alert style / signing-reset authorization).
            Button("Send Test Notification") { sendTestNotification() }
                .help("Posts a notification now to verify macOS delivery. If nothing appears, check " +
                    "System Settings → Notifications → JobHunt, turn off Do Not Disturb / Focus, and see " +
                    "the Console for 'Jobhunt test-notification' lines (auth status + add() result).")

            Divider()
            // TASK-464: re-present the onboarding flow (preview — leaves the completion flag set).
            Button("Reopen Onboarding") {
                NotificationCenter.default.post(name: .reopenOnboarding, object: nil)
            }
            .help("Show the first-run setup flow again. Dismissing keeps your setup; this is just a preview.")

            Button("Reset First-Run Setup") {
                appServices.settings.set("", forKey: "onboarding_complete")
                NotificationCenter.default.post(name: .reopenOnboarding, object: nil)
            }
            .help("Clears the onboarding-complete flag and re-presents the first-run wizard, as on a fresh install.")

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
        content.title = "JobHunt test notification"
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
        Task { @MainActor in
            let text = await appServices.diagnosticsText()
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            appServices.toastStore.show("Diagnostics copied to clipboard")
        }
    }
}
