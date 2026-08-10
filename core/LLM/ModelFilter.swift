import Foundation

/// Narrows a provider's model list as the user types (TASK-665).
///
/// OpenRouter returns several hundred alphabetical model ids. The picker they're rendered in ignores
/// keystrokes, so the only way to reach `deepseek/…` was scrolling — slow with a mouse and
/// impossible with a keyboard alone.
///
/// A filter field rather than in-menu type-select: type-select would jump to one entry from a
/// *prefix of the whole id*, which is the wrong shape here. Model ids are `vendor/model`, so the
/// part a user knows ("deepseek", "haiku") is often in the middle. Filtering on any segment finds it;
/// prefix type-select wouldn't.
public enum ModelFilter {
    /// Models matching `query`, order preserved.
    ///
    /// Matches on any `/`- or `-`-separated segment as well as the whole string, so "haiku" finds
    /// `anthropic/claude-haiku-4-5` and "deep" finds both `deepseek/deepseek-v4-flash` and
    /// `deepseek/deepseek-r2`. An empty query returns everything — an empty field means "no filter",
    /// not "no results".
    public static func matching(_ query: String, in models: [String]) -> [String] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return models }
        return models.filter { matches(needle, $0.lowercased()) }
    }

    private static func matches(_ needle: String, _ model: String) -> Bool {
        if model.hasPrefix(needle) { return true }
        return model
            .split(whereSeparator: { $0 == "/" || $0 == "-" || $0 == ":" || $0 == "." })
            .contains { $0.hasPrefix(needle) }
    }

    /// Below this a filter isn't worth the extra control — the menu is already scannable, and an
    /// always-present filter field on a five-item list is clutter.
    public static let showFilterAbove = 12

    public static func shouldOfferFilter(modelCount: Int) -> Bool {
        modelCount > showFilterAbove
    }
}
