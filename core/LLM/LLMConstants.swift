import Foundation

/// Upper bounds on how much captured job text / résumé text is sent to the model — a guard against
/// pathological input (a giant accidental paste), NOT a model-context limit. Every current cloud model
/// has a ~1M-token window (~4M chars): OpenAI GPT-5.x, Claude Opus 4.8 / Sonnet 5, Gemini 2.5/3.x — so
/// a real résumé (~5K tokens) + posting (~4K) is <1% of the window and is never truncated. The old
/// values (32000 / 12000) were ported verbatim from the legacy JS server and silently cut a real
/// résumé's skills/keyword tail for no reason. These caps now sit far above any realistic document
/// while still bounding a runaway paste.
/// NOTE: still model-agnostic — a small LOCAL model (Ollama / LM Studio, 8–32K-token context) could
/// overflow. Those expose their real window via their own API (Ollama `/api/show`, LM Studio
/// `/api/v0/models`); budget by the selected model's context there if/when local models are supported.
public enum LLMConstants {
    public static let maxDescriptionChars = 100_000
    public static let maxResumeChars = 100_000
    /// How much of a model's raw response to persist on a JSON-parse failure (into
    /// `LLMRequestAttempt.responsePreview`) so the failure is debuggable without storing megabytes.
    public static let maxResponsePreviewChars = 2000
}
