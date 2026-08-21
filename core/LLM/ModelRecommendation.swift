import Foundation

/// The provider/model JobHunt suggests, defined once.
///
/// Onboarding, Settings and the public help page all name a recommendation. Three copies of a string
/// that changes whenever a benchmark is re-run is three chances to disagree — and the page has
/// already been re-decided twice.
///
/// **The recommendation is a starting point, not a verdict.** Re-benchmarked 2026-08-20
/// (`docs/model-benchmark-2026-08.md`): this model passed 25/25 fit-judgement checks and changed no
/// requirement verdicts across five byte-identical runs, matching a frontier model (GPT-5.6 Sol) at
/// a sixth of the cost. It is still not deterministic — its score moved as much as 14 points on one
/// fixture. The help page carries that caveat in full; the app links to it rather than restating it.
public enum ModelRecommendation {
    public static let providerID = "openrouter"
    public static let providerLabel = "OpenRouter"
    public static let modelID = "google/gemini-3.7-flash"
    public static let modelLabel = "Gemini 3.7 Flash"

    /// Public URL, so it works identically in the sandboxed MAS build — nothing here may depend on a
    /// DMG-only helper or a local file.
    public static let helpURL = "https://jobhunt-app.com/help/which-model"

    /// Link text says what the reader gets. "Learn more" makes the reader click to find out whether
    /// the click was worth it.
    public static let linkText = "Which model should I use? — accuracy, consistency and real costs"

    /// One line for the picker, naming the trade actually being made. The cost is the figure measured
    /// in `marketing/help/which-model.html` — keep the two in step if either is re-run.
    public static var summary: String {
        "\(modelLabel) via \(providerLabel) — passed every fit-judgement check with steady verdicts, "
            + "at about $0.70 per 100 jobs. GPT-5.6 Sol scored identically for roughly 6× the cost."
    }
}
