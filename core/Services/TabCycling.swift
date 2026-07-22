import Foundation

/// Index math for cycling through a fixed, ordered set of tabs with wraparound (TASK-499).
/// Pure and UI-free so the job-detail ⌃Tab / ⌃⇧Tab cycling is unit-testable without the app module.
public enum TabCycling {
    /// The next index when cycling `forward` (or backward) from `index` over `count` items, wrapping
    /// at both ends. Returns 0 for an empty set.
    public static func next(count: Int, from index: Int, forward: Bool) -> Int {
        guard count > 0 else { return 0 }
        let clamped = min(max(index, 0), count - 1)
        return forward ? (clamped + 1) % count : (clamped - 1 + count) % count
    }
}
