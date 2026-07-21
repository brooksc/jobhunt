import Foundation

/// Upper bounds on how much captured job text / résumé text is sent to the model. These are a safety
/// cap against pathological input (e.g. a giant accidental paste), NOT a model-context limit. The old
/// values (32000 / 12000) were ported verbatim from the legacy JS server and silently truncated real
/// résumés and postings — e.g. a 16 KB résumé lost its skills/keyword tail — on models with huge
/// context (Gemini ≈1M tokens, Claude 200K) for no reason. Raised to comfortably fit any realistic
/// résumé/posting.
/// NOTE: still model-agnostic — a tiny local model with, say, an 8K-token context could overflow (the
/// old values already could). A proper fix would budget these by the *selected* model's context window.
public enum LLMConstants {
    public static let maxDescriptionChars = 48000
    public static let maxResumeChars = 40000
    /// How much of a model's raw response to persist on a JSON-parse failure (into
    /// `LLMRequestAttempt.responsePreview`) so the failure is debuggable without storing megabytes.
    public static let maxResponsePreviewChars = 2000
}
