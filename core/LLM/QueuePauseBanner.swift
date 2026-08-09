import Foundation

/// Why the queue is paused.
///
/// The pause itself was a bare boolean, which made the two cases indistinguishable after the fact —
/// and they need entirely different responses. A user pause is a decision, and needs no more than a
/// reminder that work is waiting. An auto-pause is a *symptom*: the queue stopped itself because
/// requests kept failing, and the user usually doesn't know it happened. The reported case was
/// exactly this — four fit scores and a re-queued extraction that never ran, because an earlier
/// flaky extraction had auto-paused the queue and the only cue was a small button in a header.
public enum QueuePauseReason: String, Codable, Sendable, CaseIterable {
    /// The user pressed Pause.
    case user
    /// A failure streak tripped `QueueActor.autoPauseThreshold`.
    case repeatedFailures
    /// The provider rejected the API key (HTTP 401/403), so every request would fail identically.
    case authenticationFailed
}

/// The banner shown above the queue while it's paused, or `nil` when there's nothing to say.
///
/// Pure so the rule — which is entirely about *when* to speak up — is testable without a view.
public struct QueuePauseBanner: Equatable, Sendable {
    public let title: String
    public let detail: String
    /// Auto-pauses are styled as warnings; a deliberate pause is not a problem and shouldn't look
    /// like one.
    public let isAutomatic: Bool

    /// - Parameter waiting: requests that would run if the queue resumed.
    ///
    /// Returns `nil` when the queue is running, and also when it's paused with nothing waiting: a
    /// paused-and-empty queue costs the user nothing, and a banner that's always on screen is one
    /// people stop reading before the one time it matters.
    public static func make(
        isPaused: Bool,
        reason: QueuePauseReason,
        waiting: Int
    ) -> QueuePauseBanner? {
        guard isPaused, waiting > 0 else { return nil }
        let items = "\(waiting) item\(waiting == 1 ? "" : "s") waiting"

        switch reason {
        case .user:
            return QueuePauseBanner(
                title: "AI queue paused — \(items)",
                detail: "Nothing will run until you resume.",
                isAutomatic: false
            )
        case .repeatedFailures:
            return QueuePauseBanner(
                title: "AI queue auto-paused after repeated failures — \(items)",
                detail: "The queue stopped itself so it wouldn't keep failing. Check your AI "
                    + "provider, then resume.",
                isAutomatic: true
            )
        case .authenticationFailed:
            return QueuePauseBanner(
                title: "AI queue paused — API key rejected — \(items)",
                detail: "The provider refused the key, so every request would fail. Fix it in "
                    + "Settings → AI, then resume.",
                isAutomatic: true
            )
        }
    }
}
