import Foundation

/// Keyboard-triage selection navigation (TASK-616): where focus should land after rows are removed
/// from an ordered list (e.g. archiving the selected job from a filtered view).
public enum SelectionNavigation {
    /// The row to focus after `removing` rows leave `order`: the first surviving row AFTER the last
    /// removed row, else the nearest preceding surviving row; nil if none survive. Deterministic and
    /// computed from the pre-mutation order so it's stable across the async status change.
    public static func nextSelection(order: [String], removing: Set<String>) -> String? {
        guard let lastIndex = order.lastIndex(where: removing.contains) else { return nil }
        if lastIndex + 1 < order.count,
           let after = order[(lastIndex + 1)...].first(where: { !removing.contains($0) }) {
            return after
        }
        return order[..<lastIndex].last(where: { !removing.contains($0) })
    }
}
