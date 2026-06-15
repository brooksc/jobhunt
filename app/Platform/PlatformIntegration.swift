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

    /// Track whether we're currently in a batch so we can suppress individual
    /// notifications and summarise at .processingComplete instead.
    private var processingBatchCount = 0

    public init(router: Router, modelContainer: ModelContainer) {
        self.router = router
        self.modelContainer = modelContainer
        super.init()
    }

    /// Call once on app launch.
    public func start(queue: QueueActor) {
        requestNotificationAuthorization()
        registerNotificationDelegate()
        observeFocusRequests()
        applyWindowPolicy()

        eventTask = Task { [weak self] in
            for await event in await queue.subscribe() {
                await self?.handleEvent(event)
            }
        }
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
        switch event {
        case let .jobReady(jobNumber, title, fitScore):
            handleJobReady(jobNumber: jobNumber, title: title, fitScore: fitScore)

        case let .jobUnavailable(jobNumber):
            let body = "Job #\(jobNumber ?? 0) is no longer available"
            postNotification(
                id: "job-unavailable-\(jobNumber ?? 0)",
                title: "Job Unavailable",
                body: body,
                userInfo: jobNumber.map { ["jobNumber": $0] } ?? [:]
            )

        case let .processingComplete(processed, failed):
            processingBatchCount = 0
            if failed > 0 {
                postNotification(
                    id: "processing-complete",
                    title: "AI Processing Done",
                    body: "\(processed) processed, \(failed) failed",
                    userInfo: [:]
                )
            } else if processed > 1 {
                postNotification(
                    id: "processing-complete",
                    title: "AI Processing Done",
                    body: "\(processed) jobs processed",
                    userInfo: [:]
                )
            }

        case .autoPaused:
            processingBatchCount = 0
            postNotification(
                id: "queue-auto-paused",
                title: "AI Queue Paused",
                body: "Auto-paused after repeated failures",
                userInfo: ["navigate": "llmQueue"],
                isCritical: true
            )
            NSApp.requestUserAttention(.criticalRequest)
            router.navigateToSection(.llmQueue)

        case let .queueError(message):
            // Degraded queue state (e.g. a store read/write failure). The LLM Queue view surfaces
            // this to the user via its error banner; log it here for diagnostics.
            NSLog("PlatformIntegration: queue error: \(message)")
        }
    }

    private func handleJobReady(jobNumber: Int?, title: String?, fitScore: Int?) {
        let isStrongMatch = (fitScore ?? 0) >= 75
        if isStrongMatch, let score = fitScore {
            let jobTitle = title ?? "Job"
            let body = "\(jobTitle) — Fit \(score)%"
            postNotification(
                id: "job-ready-\(jobNumber ?? 0)",
                title: "Strong Match!",
                body: body,
                userInfo: jobNumber.map { ["jobNumber": $0] } ?? [:]
            )
        } else {
            // Batch mode: suppress individual notification; summarise at processingComplete.
            processingBatchCount += 1
        }
    }

    private func postNotification(
        id: String,
        title: String,
        body: String,
        userInfo: [AnyHashable: Any],
        isCritical: Bool = false
    ) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = isCritical ? .defaultCritical : .default
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
            name: Notification.Name("JobhuntFocusRequest"),
            object: nil
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
            } else if let jobNumber = userInfo["jobNumber"] as? Int {
                navigateToJob(number: jobNumber)
            }
        }
    }
}
