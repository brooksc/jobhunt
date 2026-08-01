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

    /// Starts at `floor` (a conservative number of in-flight requests) and probes UP toward `ceiling`
    /// after sustained success, rather than starting at the ceiling (TASK-609). This makes the raised
    /// per-provider ceilings safe on low-quota keys: a free tier hits a 429 partway up and self-limits,
    /// while a paid tier keeps climbing to the ceiling — no need to detect the account's tier.
    /// `promoteAfter` is 4, not 10: each step costs that many consecutive successes, so climbing
    /// 3→8 took 50 requests and a typical batch finished still at the floor. Four keeps the probe
    /// cautious — a 429 still collapses to 1 immediately — while letting a healthy key actually
    /// reach its ceiling within a normal run.
    public init(ceiling: Int, floor: Int = 3, promoteAfter: Int = 4) {
        let clampedCeiling = max(1, ceiling)
        self.ceiling = clampedCeiling
        self.promoteAfter = max(1, promoteAfter)
        effective = min(max(1, floor), clampedCeiling)
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
