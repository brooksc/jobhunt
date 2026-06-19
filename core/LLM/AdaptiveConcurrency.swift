import Foundation

/// Per-session runtime concurrency that backs off on rate limits and recovers on sustained success
/// (TASK-463, Electron parity with `onRateLimit`/`CONCURRENCY_PROMOTE_AFTER`).
///
/// The provider's static `concurrencyLimit` is the CEILING. On any in-flight HTTP 429 the effective
/// limit drops to 1; after `promoteAfter` consecutive successes it steps back up one toward the
/// ceiling. Pure value type — no I/O, no persistence (resets each session); the QueueActor owns one
/// and reads `effective` where it used to read the provider ceiling.
public struct AdaptiveConcurrency: Equatable {
    public let ceiling: Int
    public let promoteAfter: Int
    public private(set) var effective: Int
    private var consecutiveSuccesses: Int

    public init(ceiling: Int, promoteAfter: Int = 10) {
        let clampedCeiling = max(1, ceiling)
        self.ceiling = clampedCeiling
        self.promoteAfter = max(1, promoteAfter)
        effective = clampedCeiling
        consecutiveSuccesses = 0
    }

    /// A 429 was observed: collapse to a single in-flight request and reset the promotion streak.
    public mutating func onRateLimit() {
        effective = 1
        consecutiveSuccesses = 0
    }

    /// A request succeeded: after `promoteAfter` in a row, step the limit up one toward the ceiling.
    public mutating func onSuccess() {
        guard effective < ceiling else {
            consecutiveSuccesses = 0
            return
        }
        consecutiveSuccesses += 1
        if consecutiveSuccesses >= promoteAfter {
            effective = min(ceiling, effective + 1)
            consecutiveSuccesses = 0
        }
    }

    /// A non-rate-limit failure: break the promotion streak but don't collapse concurrency.
    public mutating func onFailure() {
        consecutiveSuccesses = 0
    }
}
