import Foundation

/// Character-limit constants shared between the extraction prompt builder and UI truncation.
/// Values mirror the JS constants in server/extract.js.
public enum LLMConstants {
    public static let maxDescriptionChars = 32000
    public static let maxResumeChars = 12000
    /// How much of a model's raw response to persist on a JSON-parse failure (into
    /// `LLMRequestAttempt.responsePreview`) so the failure is debuggable without storing megabytes.
    public static let maxResponsePreviewChars = 2000
}
