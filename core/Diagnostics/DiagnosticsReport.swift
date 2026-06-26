import Foundation

/// Builds the human-readable diagnostics blob a user copies when reporting an issue. Pure and
/// redacted at the boundary so every caller (the Debug tab and the Help → Copy Diagnostics menu
/// item) produces identical, safe output (TASK-550–553). Sensitive values in free-text fields
/// (`serverError`, recent error messages) are passed RAW and redacted here via
/// `DiagnosticsRedactor`, so no caller can forget to redact.
public enum DiagnosticsReport {
    /// A recent-error entry for the report. `message` is raw — redaction happens in `text(...)`.
    public struct ErrorLine: Sendable {
        public let timestamp: Date
        public let message: String
        public init(timestamp: Date, message: String) {
            self.timestamp = timestamp
            self.message = message
        }
    }

    /// Assemble the diagnostics text. Free-text fields are redacted; provider/model/counts are
    /// included verbatim (they carry no secrets). Job descriptions and resume content are never
    /// included.
    public static func text(
        appVersion: String,
        buildNumber: String,
        osVersion: String,
        provider: String,
        model: String,
        consentGranted: Bool,
        queuePaused: Bool,
        serverRunning: Bool,
        serverError: String?,
        queued: Int,
        processing: Int,
        failed: Int,
        recentErrors: [ErrorLine],
        settingsError: String? = nil,
        keychainError: String? = nil,
        loadError: String? = nil
    ) -> String {
        let serverStatus = serverRunning ? "running" : "stopped"
        let serverErrorText = serverError.map { " (error: \(DiagnosticsRedactor.redact($0)))" } ?? ""

        let errorLines = recentErrors.isEmpty
            ? "  (none)"
            : recentErrors.map {
                "  [\($0.timestamp.formatted(date: .omitted, time: .standard))] " +
                    "\(DiagnosticsRedactor.redact($0.message))"
            }
            .joined(separator: "\n")

        // Settings/keychain persistence failures explain why a preference or API key didn't stick —
        // valuable for support, and these fields never carry raw setting values (TASK-552). Redacted.
        func line(_ label: String, _ value: String?) -> String? {
            value.map { "\(label) \(DiagnosticsRedactor.redact($0))" }
        }
        let persistenceLines = [
            line("Settings persist:", settingsError),
            line("Keychain write: ", keychainError),
            line("Settings load:  ", loadError)
        ].compactMap { $0 }
        let persistenceText = persistenceLines.isEmpty ? "(none)" : persistenceLines.joined(separator: "\n")

        return """
        === Jobhunt Diagnostics ===
        App version:        \(appVersion) (\(buildNumber))
        macOS:              \(osVersion)

        === LLM ===
        Provider:           \(provider)
        Model:              \(model)
        Consent granted:    \(consentGranted)
        Queue paused:       \(queuePaused)

        === Server ===
        Status:             \(serverStatus)\(serverErrorText)

        === LLM Queue ===
        Queued:             \(queued)
        Processing:         \(processing)
        Failed:             \(failed)

        === Settings / Persistence ===
        \(persistenceText)

        === Recent Errors ===
        \(errorLines)
        """
    }
}
