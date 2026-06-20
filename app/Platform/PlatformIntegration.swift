import AppKit
import JobhuntCore
import SwiftData
import UserNotifications

/// Observes engine events + unread count changes; drives macOS integration.
@MainActor
public final class PlatformIntegration: NSObject, ObservableObject {
    private let router: Router
    private let modelContainer: ModelContainer
    private var eventTask: Task<Void, Never>?
    /// Guards against repeated `start(queue:)` calls duplicating observers/subscriptions/prompts
    /// (TASK-429). `stop()` clears it so a restart is possible.
    public private(set) var isStarted = false
    private let focusNotificationName = Notification.Name("JobhuntFocusRequest")

    /// Jobs that became ready during the current drain, keyed by job number (TASK-482). `jobReady`
    /// fires twice per job (after extraction with a nil fit, then after fit with the score), so we
    /// accumulate and de-dup here, then decide individual-vs-summary at `.processingComplete`.
    private struct PendingReadyJob { var title: String?; var fitScore: Int? }
    private var pendingReady: [Int: PendingReadyJob] = [:]
    /// A single capture (or a handful) notifies per job; a larger drain summarizes instead of firing
    /// one banner per job. 3 keeps interactive captures individual while taming bulk re-extractions.
    private let maxIndividualReadyNotifications = 3
    private let strongMatchThreshold = 75

    public init(router: Router, modelContainer: ModelContainer) {
        self.router = router
        self.modelContainer = modelContainer
        super.init()
    }

    /// Call once on app launch. Idempotent — a second call while already started is a no-op, so it
    /// can't duplicate the queue subscription, notification observer/delegate, or OS prompts.
    public func start(queue: QueueActor) {
        guard !isStarted else { return }
        isStarted = true

        requestNotificationAuthorization()
        registerNotificationDelegate()
        observeFocusRequests()
        observeAvailabilityExpiry()
        applyWindowPolicy()

        eventTask = Task { [weak self] in
            for await event in await queue.subscribe() {
                await self?.handleEvent(event)
            }
        }
    }

    /// Cancel the queue subscription and unregister the focus observer + notification delegate.
    /// Safe to call repeatedly; after `stop()`, `start(queue:)` can run again (TASK-429).
    public func stop() {
        guard isStarted else { return }
        isStarted = false

        eventTask?.cancel()
        eventTask = nil
        NotificationCenter.default.removeObserver(self, name: focusNotificationName, object: nil)
        NotificationCenter.default.removeObserver(self, name: .jobUnavailable, object: nil)
        if UNUserNotificationCenter.current().delegate === self {
            UNUserNotificationCenter.current().delegate = nil
        }
    }

    deinit {
        // Best-effort teardown if the owner drops us without calling stop().
        eventTask?.cancel()
        NotificationCenter.default.removeObserver(self)
    }

    private func applyWindowPolicy() {
        // Set minimum window size once at launch. The scene declares defaultSize(1200×750)
        // for first run; we only enforce the floor, not force-resize user-restored windows.
        NSApp.mainWindow?.minSize = NSSize(width: 900, height: 600)
    }

    /// Update dock badge to unread job count.
    public func updateDockBadge(count: Int) {
        NSApp.dockTile.badgeLabel = count > 0 ? "\(count)" : ""
    }

    /// Handle jobhunt://jobs/N deep link.
    public func handleDeepLink(_ url: URL) {
        guard url.scheme == "jobhunt",
              url.host == "jobs",
              let numberString = url.pathComponents.dropFirst().first,
              let jobNumber = Int(numberString) else { return }
        navigateToJob(number: jobNumber)
    }

    /// Handle /api/app/focus notification from HTTP server (task-047).
    @objc public func handleFocusRequest(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
        if let userInfo = notification.userInfo,
           let jobNumber = userInfo["job_number"] as? Int {
            navigateToJob(number: jobNumber)
        }
    }

    // MARK: - Private

    /// Resolve a public job number to its `Job.id` and select it. Falls back to the
    /// Jobs section with no selection if the number doesn't resolve, so callers never
    /// land on a stale/empty selection silently.
    private func navigateToJob(number: Int) {
        var descriptor = FetchDescriptor<Job>(predicate: #Predicate { $0.jobNumber == number })
        descriptor.fetchLimit = 1
        if let job = try? modelContainer.mainContext.fetch(descriptor).first {
            router.selectJob(id: job.id)
        } else {
            router.navigateToSection(.jobs)
        }
    }

    private func handleEvent(_ event: QueueEvent) async {
        // The notification CONTENT comes from the pure, unit-tested `QueueEvent.notification` mapping
        // (Core) so it can't drift from the tests. Delivery + side-effects (banner, navigation,
        // dock bounce) stay here in the app layer.
        if let spec = event.notification {
            postNotification(
                id: spec.id,
                title: spec.title,
                body: spec.body,
                userInfo: spec.navigate.map { ["navigate": $0] } ?? [:]
            )
            if spec.requestsAttention { NSApp.requestUserAttention(.criticalRequest) }
        }

        switch event {
        case let .jobReady(jobNumber, title, fitScore):
            // A success means the provider/key is working again — clear any standing queue alert.
            router.queueAlert = nil
            accumulateReady(jobNumber: jobNumber, title: title, fitScore: fitScore)

        case let .processingComplete(_, failed):
            flushReady(failed: failed)

        case .autoPaused:
            router.navigateToSection(.llmQueue)

        case let .authenticationFailed(statusCode):
            // App-wide banner so it's visible from any screen, not only the LLM Queue (TASK-542).
            router.queueAlert = QueueAlert(
                message: "API key rejected (HTTP \(statusCode)) — check your AI provider key in " +
                    "Settings → AI Provider.",
                showsAISettings: true
            )

        case let .queueError(message):
            // Degraded queue state — the notification above surfaces it on any screen; log for
            // diagnostics too (message is already sanitized — no secrets / file paths).
            NSLog("PlatformIntegration: queue error: \(message)")

        case .providerNotConfigured:
            break
        }
    }

    /// Record a ready job for the current drain, de-duping the two `jobReady` emits per job
    /// (extraction → nil fit, then fit → score). A non-nil score always wins (TASK-482).
    private func accumulateReady(jobNumber: Int?, title: String?, fitScore: Int?) {
        guard let number = jobNumber else {
            // No number to key/de-dup on — post a generic ready notification immediately.
            postReadyNotification(jobNumber: nil, title: title, fitScore: fitScore)
            return
        }
        var entry = pendingReady[number] ?? PendingReadyJob(title: title, fitScore: nil)
        if let title { entry.title = title }
        if let fitScore { entry.fitScore = fitScore }
        pendingReady[number] = entry
    }

    /// At the end of a drain, notify about the ready jobs: one "ready to review" per job for a small
    /// batch (strong matches highlighted), or a single summary for a bulk run (TASK-482).
    private func flushReady(failed: Int) {
        let ready = pendingReady
        pendingReady = [:]

        if ready.isEmpty {
            if failed > 0 {
                postNotification(
                    id: "processing-complete",
                    title: "AI Processing",
                    body: "\(failed) job\(failed == 1 ? "" : "s") failed",
                    userInfo: ["navigate": "llmQueue"]
                )
            }
            return
        }

        if ready.count <= maxIndividualReadyNotifications {
            for (number, job) in ready {
                postReadyNotification(jobNumber: number, title: job.title, fitScore: job.fitScore)
            }
            if failed > 0 {
                postNotification(
                    id: "processing-failed",
                    title: "AI Processing",
                    body: "\(failed) job\(failed == 1 ? "" : "s") failed",
                    userInfo: ["navigate": "llmQueue"]
                )
            }
        } else {
            let strong = ready.values.count(where: { ($0.fitScore ?? 0) >= strongMatchThreshold })
            var body = "\(ready.count) jobs ready to review"
            if strong > 0 { body += " · \(strong) strong match\(strong == 1 ? "" : "es")" }
            if failed > 0 { body += " · \(failed) failed" }
            postNotification(
                id: "processing-complete",
                title: "AI Processing Done",
                body: body,
                userInfo: [:]
            )
        }
    }

    /// One "ready to review" notification for a single job; strong matches (≥75%) are titled
    /// "Strong Match!". Clicking deep-links to the job via its number (TASK-482).
    private func postReadyNotification(jobNumber: Int?, title: String?, fitScore: Int?) {
        let jobTitle = title ?? "Job"
        let isStrong = (fitScore ?? 0) >= strongMatchThreshold
        let body: String = if let fitScore {
            "\(jobTitle) — Fit \(fitScore)%"
        } else {
            jobTitle
        }
        postNotification(
            id: "job-ready-\(jobNumber ?? 0)",
            title: isStrong ? "Strong Match!" : "Ready to Review",
            body: body,
            userInfo: jobNumber.map { ["jobNumber": $0] } ?? [:]
        )
    }

    private func postNotification(
        id: String,
        title: String,
        body: String,
        userInfo: [AnyHashable: Any]
    ) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        // Always .default: `.defaultCritical` requires the (Apple-approval-only) critical-alerts
        // entitlement, which this app doesn't have — using it made `add()` fail silently, so the
        // "critical" auto-pause / auth notifications never appeared. Extra urgency comes from the
        // dock bounce (NSApp.requestUserAttention) and the app-wide banner instead (TASK-542).
        content.sound = .default
        content.userInfo = userInfo

        let request = UNNotificationRequest(
            identifier: id,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                NSLog("PlatformIntegration: notification error: \(error)")
            }
        }
    }

    private func requestNotificationAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error {
                NSLog("PlatformIntegration: notification auth error: \(error)")
            } else {
                NSLog("PlatformIntegration: notification auth granted=\(granted)")
            }
        }
    }

    private func registerNotificationDelegate() {
        UNUserNotificationCenter.current().delegate = self
    }

    private func observeFocusRequests() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleFocusRequest(_:)),
            name: focusNotificationName,
            object: nil
        )
    }

    /// Bridge the background availability auto-expiry into a user notification (TASK-511).
    /// `AvailabilityChecker.checkJobs` marks pursuing jobs expired and posts `.jobUnavailable`; the
    /// queue never emits `QueueEvent.jobUnavailable`, so this NotificationCenter observer is the live
    /// path — without it the status change is silent.
    private func observeAvailabilityExpiry() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleJobUnavailable(_:)),
            name: .jobUnavailable,
            object: nil
        )
    }

    /// Posted by `AvailabilityChecker` off the main thread — stay `nonisolated`, pull the Sendable
    /// primitives out of `userInfo`, then hop to the main actor to post the notification.
    @objc private nonisolated func handleJobUnavailable(_ note: Notification) {
        let jobNumber = note.userInfo?[JobUnavailableKey.jobNumber] as? Int
        let title = note.userInfo?[JobUnavailableKey.title] as? String
        Task { @MainActor [weak self] in
            self?.postJobUnavailableNotification(jobNumber: jobNumber, title: title)
        }
    }

    private func postJobUnavailableNotification(jobNumber: Int?, title: String?) {
        let name = title.flatMap { $0.isEmpty ? nil : $0 }
            ?? jobNumber.map { "Job #\($0)" }
            ?? "A pursued job"
        postNotification(
            id: "job-unavailable-\(jobNumber ?? 0)",
            title: "Job Unavailable",
            body: "\(name) is no longer available",
            userInfo: jobNumber.map { ["jobNumber": $0] } ?? [:]
        )
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension PlatformIntegration: UNUserNotificationCenterDelegate {
    /// Show notifications even when app is in foreground.
    public nonisolated func userNotificationCenter(
        _: UNUserNotificationCenter,
        willPresent _: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    /// Handle notification click.
    public nonisolated func userNotificationCenter(
        _: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        await MainActor.run {
            NSApp.activate(ignoringOtherApps: true)
            if let navigate = userInfo["navigate"] as? String, navigate == "llmQueue" {
                router.navigateToSection(.llmQueue)
            } else if let navigate = userInfo["navigate"] as? String, navigate == "settings-ai" {
                // Deep-link straight to the AI Provider tab so a key/provider fix is one click away
                // (TASK-542/543). Set the tab before opening so SettingsView lands on it.
                router.settingsTab = .llm
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            } else if let navigate = userInfo["navigate"] as? String, navigate == "settings" {
                // Settings is the standard preferences window now, not an in-window section.
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            } else if let jobNumber = userInfo["jobNumber"] as? Int {
                navigateToJob(number: jobNumber)
            }
        }
    }
}
