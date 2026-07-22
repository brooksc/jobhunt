import Foundation

/// Outcome of persisting an imported resume, mapped to what the onboarding UI should show (TASK-547).
public enum ResumeImportOutcome: Equatable {
    /// Persisted — the UI may now show the resume as imported.
    case imported(name: String, text: String)
    /// Persistence failed — the UI keeps the user on the import step and shows this (retryable) message.
    case failed(String)
}

/// Persistence seam for onboarding resume import. Extracted from the SwiftUI view so the
/// success-vs-failure outcome — the crux of TASK-547 — is unit-testable without the app module or a
/// real Keychain/store (the view has no unit-test target, and the file picker isn't automatable).
public enum ResumeImporter {
    /// Attempt to save an imported resume via `save`, returning `.imported` only if it succeeds so the
    /// UI never shows a false "imported" state, and `.failed(message)` (redacted, user-facing) on error.
    public static func save(
        name: String,
        text: String,
        using save: (_ name: String, _ text: String) async throws -> Void
    ) async -> ResumeImportOutcome {
        do {
            try await save(name, text)
            return .imported(name: name, text: text)
        } catch {
            return .failed("Couldn't save the resume: \(error.localizedDescription). Please try again.")
        }
    }
}
