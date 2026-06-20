import Foundation

/// The user-facing notification a `QueueEvent` should post, if any (TASK-542).
///
/// This is a pure, `Sendable` value so the event→notification *content* mapping is unit-testable
/// without the OS. (Actual delivery via UNUserNotificationCenter can't be unit-tested — entitlements,
/// Focus, and code-signing all affect it; verify that manually via Settings → Debug → Send Test
/// Notification.) It deliberately carries NO sound: macOS "critical" alerts need an entitlement this
/// app doesn't have, and requesting `.defaultCritical` makes `add()` fail silently — the app layer
/// always posts with `.default`.
public struct QueueNotification: Equatable, Sendable {
    public let id: String
    public let title: String
    public let body: String
    /// Routing hint the app's notification-tap handler understands: "settings-ai", "llmQueue", or nil.
    public let navigate: String?
    /// Whether the app should bounce the dock for attention (NSApp.requestUserAttention).
    public let requestsAttention: Bool
}

public extension QueueEvent {
    /// The standalone notification for this event. `.jobReady` / `.processingComplete` return nil —
    /// those are batched/summarized by the app layer (`PlatformIntegration.flushReady`).
    var notification: QueueNotification? {
        switch self {
        case let .authenticationFailed(code):
            QueueNotification(
                id: "auth-failed",
                title: "AI key rejected",
                body: "Your AI provider rejected the request (HTTP \(code)). " +
                    "Check your API key in Settings → AI Provider.",
                navigate: "settings-ai",
                requestsAttention: true
            )
        case .autoPaused:
            QueueNotification(
                id: "queue-auto-paused",
                title: "AI Queue Paused",
                body: "Auto-paused after repeated failures",
                navigate: "llmQueue",
                requestsAttention: true
            )
        case .providerNotConfigured:
            QueueNotification(
                id: "provider-not-configured",
                title: "Set up an AI provider",
                body: "Job captured — add an AI provider in Settings to enable extraction & fit scoring.",
                navigate: "settings-ai",
                requestsAttention: false
            )
        case let .queueError(message):
            QueueNotification(
                id: "queue-error",
                title: "AI Queue problem",
                body: message,
                navigate: "llmQueue",
                requestsAttention: false
            )
        case .jobReady, .processingComplete:
            nil
        }
    }
}
