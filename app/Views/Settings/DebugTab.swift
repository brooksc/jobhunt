import AppKit
import JobhuntCore
import SwiftData
import SwiftUI

struct DebugTab: View {
    @Query private var jobs: [Job]
    @Query private var captures: [Capture]
    @Query private var resumes: [Resume]
    @Query private var sites: [Site]
    @Query private var llmRequests: [LLMRequest]

    @Environment(AppServices.self) private var appServices

    var body: some View {
        Form {
            jobStatsSection
            entityCountsSection
            fitScoresSection
            settingsErrorSection
            recentErrorsSection
            diagnosticsSection
        }
        .formStyle(.grouped)
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
            Text("Re-applies the current scoring weights and penalties to already-scored jobs, without calling the LLM.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Job stats by status

    private var jobStatsSection: some View {
        Section("Jobs by Status") {
            ForEach(JobStatus.allCases, id: \.self) { status in
                let count = jobs.filter { $0.status == status }.count
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
                let pending = jobs.filter { $0.extractionStatus == .pending }.count
                Text("\(pending)").foregroundStyle(.secondary).monospacedDigit()
            }
            LabeledContent("Extraction failed") {
                let failed = jobs.filter { $0.extractionStatus == .failed }.count
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
                "Copies system info, queue counts, and sanitized recent error types. " +
                    "Does not include job descriptions or resume content."
            )
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
        let serverError = appServices.serverError.map { " (error: \($0))" } ?? ""

        let queued = llmRequests.count(where: { $0.status == .queued })
        let processing = llmRequests.count(where: { $0.status == .running })
        let failed = llmRequests.count(where: { $0.status == .failed || $0.status == .retryExhausted })

        let errors = appServices.toastStore.recentErrors
        let errorLines = errors.isEmpty
            ? "  (none)"
            : errors.map {
                "  [\($0.timestamp.formatted(date: .omitted, time: .standard))] \(redactDiagnosticString($0.message))"
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

    // MARK: - Diagnostic redaction

    /// Strips known sensitive patterns from a string before including it in the support bundle.
    /// Replaces file paths, URL query strings, and common secret prefixes with [redacted].
    private func redactDiagnosticString(_ s: String) -> String {
        var result = s

        // File paths: /Users/..., /private/..., /var/..., /tmp/...
        let pathPattern = #"(/Users/|/private/|/var/|/tmp/)[^\s\"\']+"#
        if let regex = try? NSRegularExpression(pattern: pathPattern) {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: "[redacted]")
        }

        // URL query strings: strip everything after '?' in http/https URLs
        let queryPattern = #"(https?://[^\s\?]+)\?[^\s]*"#
        if let regex = try? NSRegularExpression(pattern: queryPattern) {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: "$1?[redacted]")
        }

        // Common secret prefixes: Bearer tokens, OpenAI-style keys, Google API keys
        let secretPattern = #"(Bearer\s+|sk-|AIza)[A-Za-z0-9\-_\.]{8,}"#
        if let regex = try? NSRegularExpression(pattern: secretPattern) {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: "[redacted]")
        }

        return result
    }
}
