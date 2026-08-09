import Foundation

/// What the LLM queue is actually doing right now, for display.
///
/// The queue view used to show only counts and a Pause/Resume toggle, plus a toolbar button
/// permanently labelled "Resume Queue" — which reads as "the queue is paused" whether it is or not.
/// Three people (two of them me) chased a pause that didn't exist because of it.
///
/// `queued` is deliberately its own state rather than being folded into `running`. Work outstanding
/// with nothing executing and no pause in force is exactly the wedge TASK-657 describes, and calling
/// it "Running" would hide the one symptom that gives it away.
public enum QueueActivity: String, Sendable, Equatable {
    /// The user (or a failure policy) paused the queue. Nothing will start until it resumes.
    case paused
    /// At least one request is executing.
    case running
    /// Requests are waiting and the queue is NOT paused, but nothing is executing.
    case queued
    /// No outstanding work.
    case idle

    /// Order matters: a paused queue reports `paused` even when a request is still finishing, because
    /// "paused" is the fact that determines whether anything *else* will start.
    public static func state(isPaused: Bool, running: Int, queued: Int) -> QueueActivity {
        if isPaused { return .paused }
        if running > 0 { return .running }
        return queued > 0 ? .queued : .idle
    }

    public var label: String {
        switch self {
        case .paused: "Paused"
        case .running: "Running"
        case .queued: "Waiting"
        case .idle: "Idle"
        }
    }

    /// Spelled out, because the label alone doesn't say what it means for the user's work.
    public var explanation: String {
        switch self {
        case .paused: "The queue is paused — nothing will start until you resume it."
        case .running: "The queue is working through its requests."
        case .queued: "Requests are waiting but none are running. Use Run Queued Requests to start them."
        case .idle: "Nothing queued or running."
        }
    }
}
