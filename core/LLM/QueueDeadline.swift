import Foundation

// MARK: - Request deadline (TASK-657)

/// Raised when a request outlives its wall-clock budget.
public struct LLMRequestTimeout: Error, LocalizedError {
    public let seconds: Double
    public var errorDescription: String? {
        "The AI provider didn't finish within \(Int(seconds))s, so the request was cancelled and requeued."
    }
}

extension QueueActor {
    /// How long a row may sit in `running` before the reaper treats it as orphaned.
    ///
    /// Comfortably beyond the per-request deadline so a legitimately slow request is never reaped
    /// mid-flight: the deadline cancels and requeues at 1.5× the timeout, so anything still `running`
    /// at 3× has escaped that path entirely — which is exactly the orphan this guards against
    /// (observed live at 11+ minutes against a 300s setting, with no connection open and no attempt
    /// row written).
    func orphanReapSeconds() async -> Double {
        await requestDeadlineSeconds() * 2
    }

    /// Return rows stuck in `running` past the bound to `queued`, releasing their concurrency slots.
    ///
    /// `requeueRunningOnLaunch` only runs at launch or from a Debug-tab button most users never open,
    /// so a row orphaned mid-session sat there until a restart. Worse than the stalled job: each
    /// orphan permanently leaks a slot from the adaptive pool, so several would throttle the queue
    /// toward serial and present as "the LLM queue is slow" with nothing in the logs.
    ///
    /// Returns the number reaped so the caller can decide whether to tell the user.
    @discardableResult
    public func reapOrphanedRunning() async throws -> Int {
        let cutoff = await Date(timeIntervalSinceNow: -orphanReapSeconds())
        var reaped: [String] = []
        try await store.update(LLMRequest.self, predicate: nil) { req in
            // A row with no startedAt can't be aged, so it's left alone rather than guessed at.
            guard req.status == LLMRequestStatus.running, let started = req.startedAt, started < cutoff else { return }
            req.status = .queued
            req.startedAt = nil
            req.finishedAt = nil
            // Defect 2: the orphan that prompted this left NO evidence — empty error, no attempt row.
            // Whatever happens next, the reason it was reaped is now recorded on the row.
            req.error = "Requeued automatically: no result after \(Int(cutoff.timeIntervalSinceNow * -1))s."
            reaped.append(req.id)
        }
        guard !reaped.isEmpty else { return 0 }
        // The slots those rows were holding are gone with them; re-seed so the pool doesn't stay
        // throttled by orphans that no longer exist.
        resetAdaptiveConcurrency()
        emit(.requestsReaped(count: reaped.count))
        return reaped.count
    }

    /// Total time one request may take, derived from the user's timeout setting rather than adding a
    /// second knob. The multiplier covers a provider that is legitimately slow — measured requests ran
    /// 16–139s against a 300s setting — while still bounding the pathological case.
    func requestDeadlineSeconds() async -> Double {
        let configured = await Double(readExtractionSettings().llmTimeout)
        let base = configured > 0 ? configured : 300
        return base * 1.5
    }

    /// Run `operation`, cancelling it if it outlives `seconds`.
    ///
    /// Deliberately a race rather than a `URLSession` timeout: the transport's `timeoutInterval`
    /// measures the gap between packets, so it never fires for a call that stalls after receiving
    /// some bytes — which is the case that wedged the queue.
    func withRequestDeadline<T: Sendable>(
        seconds: Double,
        _ operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(for: .seconds(seconds))
                throw LLMRequestTimeout(seconds: seconds)
            }
            defer { group.cancelAll() }
            // Whichever finishes first wins; the loser is cancelled by the deferred cancelAll.
            guard let result = try await group.next() else {
                throw LLMRequestTimeout(seconds: seconds)
            }
            return result
        }
    }
}
