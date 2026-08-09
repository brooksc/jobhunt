import Foundation

/// The provider/model JobHunt suggests, defined once.
///
/// Onboarding, Settings and the public help page all name a recommendation. Three copies of a string
/// that changes whenever a benchmark is re-run is three chances to disagree — and the page has
/// already been re-decided twice.
///
/// **The recommendation is a starting point, not a verdict.** Measured on byte-identical input, this
/// model's score moved 19 points across five runs (TASK-661), so it is chosen for being cheap, fast
/// and no less consistent than the alternatives at its price — not for being reliable in absolute
/// terms. The help page carries that caveat in full; the app links to it rather than restating it.
public enum ModelRecommendation {
    public static let providerID = "openrouter"
    public static let providerLabel = "OpenRouter"
    public static let modelID = "mistralai/ministral-14b-2512"
    public static let modelLabel = "Ministral 14B"

    /// Public URL, so it works identically in the sandboxed MAS build — nothing here may depend on a
    /// DMG-only helper or a local file.
    public static let helpURL = "https://jobhunt-app.com/help/which-model"

    /// Link text says what the reader gets. "Learn more" makes the reader click to find out whether
    /// the click was worth it.
    public static let linkText = "Which model should I use? — accuracy, consistency and real costs"

    /// One line for the picker, naming the trade actually being made. The cost is the figure measured
    /// in `marketing/help/which-model.html` — keep the two in step if either is re-run.
    public static var summary: String {
        "\(modelLabel) via \(providerLabel) — passed both accuracy fixtures at about $0.12 per 100 jobs. "
            + "Claude Haiku 4.5 gives steadier answers for roughly 6× the cost."
    }
}
