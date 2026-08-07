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
