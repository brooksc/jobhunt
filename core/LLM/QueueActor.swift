// swiftlint:disable file_length function_body_length type_body_length cyclomatic_complexity
import Foundation
import SwiftData

// MARK: - QueueEvent

/// Domain events emitted by the queue, consumed by platform integration.
public enum QueueEvent: Sendable {
    case jobReady(jobNumber: Int?, title: String?, fitScore: Int?)
    case processingComplete(processed: Int, failed: Int)
    case autoPaused
    /// The queue could not read its work from the store (a degraded state — NOT an empty queue).
    /// Carries a user-facing message for diagnostics/surfacing.
    case queueError(String)
    /// Work is queued but no usable AI provider is configured (a key-requiring provider with no key).
    /// Emitted once per unconfigured episode so the user can be told to set one up, instead of letting
    /// the requests fail repeatedly into an auto-pause (TASK-483). Pending work is left queued.
    case providerNotConfigured
    /// A request failed with HTTP 401/403 — the provider rejected the API key (invalid/expired/
    /// deleted). Every request will fail the same way, so the queue pauses immediately and emits this
    /// so the user is told to fix the key (rather than silently exhausting the batch). Carries the
    /// status code for the message (TASK-542).
    case authenticationFailed(statusCode: Int)
}

// MARK: - QueueActor

public actor QueueActor {
    // MARK: - Fan-out event subscriptions

    private var continuations: [UUID: AsyncStream<QueueEvent>.Continuation] = [:]

    /// Subscribe to queue events. Each caller gets their own independent stream.
    /// Supports multiple concurrent consumers without dropping events.
    public func subscribe() -> AsyncStream<QueueEvent> {
        let id = UUID()
        return AsyncStream { [weak self] continuation in
            Task { [weak self] in
                await self?.addContinuation(continuation, for: id)
            }
            continuation.onTermination = { [weak self] _ in
                Task { [weak self] in
                    await self?.removeContinuation(for: id)
                }
            }
        }
    }

    private func addContinuation(_ continuation: AsyncStream<QueueEvent>.Continuation, for id: UUID) {
        continuations[id] = continuation
    }

    private func removeContinuation(for id: UUID) {
        continuations.removeValue(forKey: id)
    }

    private func emit(_ event: QueueEvent) {
        for continuation in continuations.values {
            continuation.yield(event)
        }
    }

    // MARK: - Dependencies

    private let store: BackgroundStore
    /// Build a provider from current settings. Async + Sendable so the implementation can snapshot
    /// the (non-Sendable) SettingsStore on the main actor rather than reading it from queue isolation.
    private let providerFactory: @Sendable () async -> any LLMProvider
    /// Read the current queue-paused flag. Implementations should dispatch to @MainActor.
    private let isPaused: @Sendable () async -> Bool
    /// Write the queue-paused flag. Implementations should dispatch to @MainActor.
    private let onSetPaused: @Sendable (Bool) async -> Void
    /// Snapshot extraction-relevant settings. Implementations should dispatch to @MainActor.
    private let readExtractionSettings: @Sendable () async -> ExtractionSettings
    /// Whether a usable AI provider is configured (TASK-483). Returns false when the selected provider
    /// requires an API key but none is set; true otherwise (incl. local providers that need no key).
    /// Defaults to always-configured so existing call sites (tests) are unaffected.
    private let isProviderConfigured: @Sendable () async -> Bool

    // MARK: - State

    private var isRunning = false
    /// Consecutive failure count across the whole queue (reset on success).
    private var failureStreak = 0
    /// Debounces the `.providerNotConfigured` event to one per unconfigured episode (TASK-483):
    /// set when emitted, cleared once a drain pass sees a configured provider.
    private var didEmitNotConfigured = false
    /// Active in-flight request count per provider id.
    private var activeCounts: [String: Int] = [:]
    /// Runtime concurrency that backs off on 429 and recovers on success (TASK-463). Re-seeded when
    /// the provider's static ceiling changes; resets each session (no persistence).
    private var adaptive: AdaptiveConcurrency?

    static let maxRetries = 3
    /// Consecutive *provider* failures before the queue auto-pauses. A single flaky response (e.g. a
    /// fast model occasionally returning unparseable JSON) shouldn't pause the whole queue and cancel
    /// unrelated in-flight work, so this is deliberately forgiving. Cancellations and rate-limits
    /// don't count toward it (see ProcessOutcome).
    static let autoPauseThreshold = 4
    /// Clamp for honoring a server Retry-After (seconds) so a hostile/huge value can't stall the queue.
    static let maxRetryAfterSeconds: Double = 60

    // MARK: - Init

    public init(
        store: BackgroundStore,
        isPaused: @escaping @Sendable () async -> Bool,
        onSetPaused: @escaping @Sendable (Bool) async -> Void,
        readExtractionSettings: @escaping @Sendable () async -> ExtractionSettings,
        providerFactory: @escaping @Sendable () async -> any LLMProvider,
        isProviderConfigured: @escaping @Sendable () async -> Bool = { true }
    ) {
        self.store = store
        self.isPaused = isPaused
        self.onSetPaused = onSetPaused
        self.readExtractionSettings = readExtractionSettings
        self.providerFactory = providerFactory
        self.isProviderConfigured = isProviderConfigured
    }

    // MARK: - Public API

    /// Enqueue new LLM extraction requests for a set of job IDs.
    /// Fetches all needed Job objects in a single query and saves all LLMRequest rows at once.
    public func enqueue(jobIDs: [String], mode: LLMRequestType) async throws {
        // TASK-526: the fetch + relationship link happens inside the store actor; we pass ids only.
        let inserted = try await store.insertRequests(jobIDs: jobIDs, mode: mode)
        // Kick the drain loop in case it's not yet running (only when something new was queued).
        if inserted { Task { await startProcessing() } }
    }

    /// Enqueue fit-scoring requests for a set of job IDs against a specific resume.
    /// Also creates/updates a JobFitScore record for each (job, resume) pair with fitStatus = .pending.
    /// Batch is inserted atomically — a single save, so partial enqueue is impossible.
    public func enqueueFit(jobIDs: [String], resumeID: String) async throws {
        guard !jobIDs.isEmpty else { return }
        // TASK-526: the store actor fetches the resume/jobs and links them; a missing resume throws
        // FitEnqueueError.resumeNotFound from inside insertFitBatch.
        try await store.insertFitBatch(jobIDs: jobIDs, resumeID: resumeID)
        // Kick the drain loop in case it's not yet running.
        Task { await startProcessing() }
    }

    /// Queue fit scoring against all active resumes for the given jobs. No-op for a job
    /// with no active resume. Skips (job, resume) pairs already in flight.
    public func enqueueFitForActiveResumes(jobIDs: [String]) async throws {
        guard !jobIDs.isEmpty else { return }
        var anyQueued = false
        for jobID in jobIDs {
            let n = try await store.enqueueFitForActiveResumes(jobID: jobID)
            if n > 0 { anyQueued = true }
        }
        if anyQueued { Task { await startProcessing() } }
    }

    /// On app launch, reset any requests stuck in "running" back to "queued",
    /// then prune old history so fetchQueuedRequests stays fast.
    public func requeueRunningOnLaunch() async throws {
        // Fetch all then filter in-memory — SwiftData predicates cannot compare enum cases.
        try await store.update(LLMRequest.self, predicate: nil) { req in
            guard req.status == .running else { return }
            req.status = .queued
            req.startedAt = nil
            req.finishedAt = nil
            req.error = nil
        }
        try await pruneFinishedRequests()
    }

    /// Delete terminal (succeeded/failed/cancelled/retryExhausted) LLMRequest history
    /// older than `days` days. Keeps the table bounded so fetchQueuedRequests is fast.
    public func pruneFinishedRequests(olderThan days: Int = 30) async throws {
        let cutoff = Date(timeIntervalSinceNow: -Double(days) * 86400)
        let terminal: Set<LLMRequestStatus> = [.succeeded, .failed, .retryExhausted, .cancelled]
        // Predicate filters to rows with a finishedAt (excludes all queued/running).
        // Date and status checks happen in Swift — SwiftData predicates cannot compare enum cases.
        try await store.deleteFiltered(
            LLMRequest.self,
            predicate: #Predicate { $0.finishedAt != nil },
            where: { req in
                guard let finished = req.finishedAt else { return false }
                return finished < cutoff && terminal.contains(req.status)
            }
        )
    }

    /// Pause the queue (prevents new requests from being processed).
    public func pauseQueue() async {
        await onSetPaused(true)
    }

    /// Resume the queue and restart the drain loop.
    public func resumeQueue() async {
        await onSetPaused(false)
        failureStreak = 0
        await startProcessing()
    }

    /// Restart the drain loop WITHOUT enqueuing new work — for callers that inserted queued requests
    /// directly into the store (e.g. atomic capture ingestion) and just need processing to (re)start
    /// (TASK-491). Fire-and-forget + idempotent: `startProcessing` no-ops if already running and
    /// respects the paused flag, so this never resumes a deliberately-paused queue.
    public func kick() {
        Task { await startProcessing() }
    }

    /// Cancel a specific request by id.
    public func cancelRequest(id: String) async throws {
        try await store.update(
            LLMRequest.self,
            predicate: #Predicate { $0.id == id }
        ) { req in
            req.status = .cancelled
            req.finishedAt = Date()
        }
        // TASK-527: a cancelled fit request must not leave its JobFitScore stuck .running/.pending.
        _ = try? await store.reconcileOrphanedFitScores()
    }

    /// Cancel all queued and running requests.
    public func cancelAll() async throws {
        // Fetch all then filter in-memory — SwiftData predicates cannot compare enum cases.
        try await store.update(LLMRequest.self, predicate: nil) { req in
            guard req.status == .queued || req.status == .running else { return }
            req.status = .cancelled
            req.finishedAt = Date()
        }
        _ = try? await store.reconcileOrphanedFitScores()
    }

    /// Permanently delete specific requests by ID.
    public func deleteRequests(ids: [String]) async throws {
        let set = Set(ids)
        try await store.delete(LLMRequest.self, predicate: #Predicate { set.contains($0.id) })
        _ = try? await store.reconcileOrphanedFitScores()
    }

    /// Permanently delete all requests (all statuses).
    public func deleteAll() async throws {
        try await store.deleteAll(LLMRequest.self)
        _ = try? await store.reconcileOrphanedFitScores()
    }

    /// Permanently delete all finished (terminal) requests — succeeded/failed/exhausted/cancelled —
    /// leaving queued and running requests intact. Terminal rows are exactly those with a
    /// `finishedAt` timestamp.
    public func clearCompleted() async throws {
        try await store.delete(LLMRequest.self, predicate: #Predicate { $0.finishedAt != nil })
    }

    /// Reset a failed request back to queued so it can be retried.
    public func resetRequest(id: String) async throws {
        try await store.update(
            LLMRequest.self,
            predicate: #Predicate { $0.id == id }
        ) { req in
            req.status = .queued
            req.attempt = 1
            req.error = nil
            req.startedAt = nil
            req.finishedAt = nil
        }
    }

    // MARK: - Processing loop

    /// Start the drain loop. Call once after launch.
    public func startProcessing() async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }

        var totalProcessed = 0
        var totalFailed = 0

        while true {
            // External cancellation (app shutdown) — exit cleanly instead of busy-looping over rows
            // that processRequest keeps requeuing while the task stays cancelled. (Auto-pause cancels
            // only the in-batch child tasks, not this loop, so it still exits via the isPaused check.)
            if Task.isCancelled { break }
            guard await !isPaused() else { break }

            let provider = await providerFactory()
            // TASK-463: dispatch at the adaptive runtime concurrency (drops to 1 after a 429, recovers
            // toward the provider's static ceiling after sustained success). Re-seed if the ceiling
            // changed (e.g. the user switched providers).
            let ceiling = provider.concurrencyLimit
            if adaptive?.ceiling != ceiling { adaptive = AdaptiveConcurrency(ceiling: ceiling) }
            let limit = adaptive?.effective ?? ceiling

            let requests: [QueuedItem]
            do {
                requests = try await fetchQueuedRequests(limit: limit)
            } catch {
                // A store-read failure is NOT an empty queue. Don't fall through to the normal
                // processingComplete path (which would report "all done") — surface it as a
                // degraded state and stop this drain pass.
                NSLog("QueueActor: queued-request fetch failed: \(error)")
                emit(.queueError("Couldn't read the LLM queue: \(error.localizedDescription)"))
                return
            }
            guard !requests.isEmpty else { break }

            // TASK-483: there's work but no usable provider (a key-requiring provider with no key).
            // Don't burn the requests into failures + an auto-pause — emit a one-shot notice telling
            // the user to set up a provider and leave the work queued for when they do.
            if await !isProviderConfigured() {
                if !didEmitNotConfigured {
                    didEmitNotConfigured = true
                    emit(.providerNotConfigured)
                }
                break
            }
            didEmitNotConfigured = false

            await withTaskGroup(of: ProcessOutcome.self) { group in
                for req in requests {
                    group.addTask {
                        await self.processRequest(req, provider: provider)
                    }
                }
                for await outcome in group {
                    switch outcome {
                    case .succeeded:
                        totalProcessed += 1
                        failureStreak = 0
                        adaptive?.onSuccess()
                    case .providerFailure:
                        totalProcessed += 1
                        totalFailed += 1
                        failureStreak += 1
                        adaptive?.onFailure()
                        if failureStreak >= Self.autoPauseThreshold {
                            await onSetPaused(true)
                            emit(.autoPaused)
                            // TASK-449: cancel the rest of this batch so still-running sibling tasks
                            // stop before (or during) their provider call — auto-pause shouldn't keep
                            // spending on cloud requests after deciding to stop.
                            group.cancelAll()
                            break
                        }
                    case let .authFailure(code):
                        // TASK-542: the key was rejected — every queued request will fail the same way.
                        // Pause now (don't burn the whole batch) and emit a distinct event so the user
                        // is told to fix the key, then cancel the rest of this batch like auto-pause.
                        totalProcessed += 1
                        totalFailed += 1
                        await onSetPaused(true)
                        emit(.authenticationFailed(statusCode: code))
                        group.cancelAll()
                    case .rateLimited:
                        // TASK-463: a 429 is transient — collapse concurrency to 1 and let the request
                        // retry (it was requeued with a Retry-After-honoring backoff). Not counted as a
                        // provider failure, so a rate-limit burst can't trip auto-pause.
                        adaptive?.onRateLimit()
                    case .cancelled, .skipped:
                        // TASK-450: not a provider failure — don't count it or touch the streak,
                        // so a user cancellation can't push the queue toward auto-pause.
                        break
                    }
                }
            }

            if await isPaused() { break }
        }

        // Electron parity: detect & persist domain duplicates. Run once after draining rather
        // than per-extraction — it's a global O(N^2) scan, so batching avoids quadratic blowup
        // when many jobs are extracted in one session.
        if totalProcessed > 0 {
            _ = try? await store.detectAndPersistDomainDuplicates()
        }

        emit(.processingComplete(processed: totalProcessed, failed: totalFailed))
    }

    // MARK: - Private processing

    /// The classified result of processing one request. Only `.providerFailure` counts toward the
    /// auto-pause failure streak — a user cancellation or a skipped/stale row is not a provider
    /// failure and must not trigger auto-pause (TASK-450).
    private enum ProcessOutcome {
        case succeeded
        case providerFailure
        case rateLimited // HTTP 429 — transient; drops adaptive concurrency, retried, not a failure
        case authFailure(statusCode: Int) // HTTP 401/403 — bad key; pause immediately, tell the user
        case cancelled // user-cancelled in flight, or the row was already cancelled/taken
        case skipped // couldn't claim the row (store error / not queued) — neutral
    }

    /// Throws on a store-read failure so the drain loop can distinguish "queue couldn't be read"
    /// (a degraded state) from "queue is genuinely empty" (normal completion). Swallowing the error
    /// as an empty result made storage failures look like all work was done.
    private func fetchQueuedRequests(limit: Int) async throws -> [QueuedItem] {
        // SwiftData predicates cannot compare enum cases, but can filter by finishedAt == nil.
        // This excludes all terminal rows (succeeded/failed/cancelled/retryExhausted) at the
        // DB level, then in-memory enum filter picks out .queued from {queued, running}.
        // No fetchLimit here — the predicate keeps the result set small without risking
        // starvation (old terminal rows can no longer block newer queued ones).
        let descriptor = FetchDescriptor<LLMRequest>(
            predicate: #Predicate { $0.finishedAt == nil },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        let all = try await store.fetch(descriptor)
        let requests = all.filter { $0.status == .queued }.prefix(limit)
        return requests.map { req in
            QueuedItem(
                id: req.id,
                requestType: req.requestType,
                attempt: req.attempt,
                jobID: req.job?.id,
                jobNumber: req.job?.jobNumber,
                jobTitle: req.job?.title,
                resumeID: req.resume?.id
            )
        }
    }

    private func processRequest(_ item: QueuedItem, provider: any LLMProvider) async -> ProcessOutcome {
        // TASK-316: Conditionally mark as running — don't overwrite if cancelled between snapshot and here
        let itemID = item.id
        do {
            try await store.update(
                LLMRequest.self,
                predicate: #Predicate { $0.id == itemID }
            ) { req in
                guard req.status == .queued else { return }
                req.status = .running
                req.startedAt = Date()
            }
        } catch {
            return .skipped
        }

        // Verify the transition actually happened
        let current = try? await store.fetch(
            FetchDescriptor<LLMRequest>(predicate: #Predicate { $0.id == itemID })
        ).first
        guard current?.status == .running else {
            // The row was cancelled or claimed between snapshot and transition — not a failure.
            return .cancelled
        }

        // TASK-449: if the batch was cancelled (auto-pause) before this task reached its provider
        // call, bail now and put the row back to queued so it isn't lost — don't spend on the call.
        if Task.isCancelled {
            try? await store.update(LLMRequest.self, predicate: #Predicate { $0.id == itemID }) { req in
                guard req.status == .running else { return }
                req.status = .queued
                req.startedAt = nil
            }
            return .cancelled
        }

        let startedAt = Date()

        do {
            let succeeded: Bool
            switch item.requestType {
            case .extract:
                succeeded = try await processExtractRequest(item: item, provider: provider, startedAt: startedAt)
            case .fit:
                succeeded = try await processFitRequest(item: item, provider: provider, startedAt: startedAt)
            }
            if succeeded { return .succeeded }
            // The processor returned false without throwing. Classify by the row's final status:
            // a user cancellation (or missing job → markRequestCancelled) leaves it .cancelled;
            // anything else (consent revoked, missing resume → .failed) is a real failure.
            let finalStatus = try? await store.requestStatus(id: itemID)
            return finalStatus == .cancelled ? .cancelled : .providerFailure
        } catch {
            // Auto-pause's `group.cancelAll()` (or app shutdown) can cancel a request mid-provider-call.
            // That is NOT a provider failure: requeue the row so it resumes when the queue does, and
            // don't record a "Swift.CancellationError" failure or count it toward the auto-pause streak.
            if error is CancellationError || Task.isCancelled {
                await requeueAfterCancellation(id: itemID)
                return .cancelled
            }
            await markRequestFailed(item: item, error: error, startedAt: startedAt)
            // TASK-463: a 429 is a transient rate limit, not a provider failure — the inner processor
            // already requeued the row with a Retry-After-honoring backoff. Signal it so the drain
            // loop drops adaptive concurrency without counting toward the auto-pause streak.
            if case LLMProviderError.rateLimited = error { return .rateLimited }
            // TASK-542: 401/403 means the key was rejected — retrying or draining the rest of the
            // batch is pointless (every request will fail identically). Surface it distinctly so the
            // drain pauses and tells the user to fix the key.
            if case let LLMProviderError.httpError(code, _) = error, code == 401 || code == 403 {
                return .authFailure(statusCode: code)
            }
            return .providerFailure
        }
    }

    /// A request cancelled in flight (auto-pause `cancelAll()`) returns to `.queued` so it resumes
    /// with the queue — not `.failed`. Only a still-`.running` row is touched, so an inner cancellation
    /// that already set `.cancelled`/`.retryExhausted` stays authoritative. (On app shutdown the parent
    /// loop is cancelled and exits before reaching here; any row left `.running` is recovered by
    /// `requeueRunningOnLaunch`.)
    private func requeueAfterCancellation(id: String) async {
        try? await store.update(LLMRequest.self, predicate: #Predicate { $0.id == id }) { req in
            guard req.status == .running else { return }
            req.status = .queued
            req.startedAt = nil
            req.error = nil
        }
    }

    private func processExtractRequest(
        item: QueuedItem,
        provider: any LLMProvider,
        startedAt: Date
    ) async throws -> Bool {
        let itemID = item.id
        guard let jobID = item.jobID else {
            await markRequestCancelled(id: itemID)
            return false
        }

        // TASK-526: build the snapshot on the store actor — never read the live Job/Capture off-actor.
        guard let extractionSnapshot = try await store.extractionSnapshot(forJobID: jobID) else {
            await markRequestCancelled(id: itemID)
            return false
        }

        // Read outside the do/catch so the failed-attempt record (in catch) can also reference the
        // requested model (TASK-535).
        let extractSettings = await readExtractionSettings()

        do {
            // Enforce consent immediately before sending data to a cloud provider.
            // Fail the request (not the queue) if consent has been revoked since enqueue.
            let consented = ConsentHelper.isConsented(
                provider: extractSettings.llmProvider,
                baseURL: extractSettings.llmBaseURL,
                consentGranted: extractSettings.consentGranted
            )
            guard consented else {
                await markRequestFailed(item: item, error: ConsentError.notConsented, startedAt: startedAt)
                return false
            }

            // Stamp the model as soon as the request is running so the queue shows it immediately,
            // not only once the request completes. Overwritten with the returned model on success.
            await setRequestModel(itemID: itemID, model: extractSettings.llmModel)

            // TASK-516: mirror the active extraction at the job level so the UI shows "Extracting"
            // (and disables Run AI) while the provider call is in flight, instead of "pending".
            // Terminal success/failure below remain the authority for the final state.
            try? await store.update(Job.self, predicate: #Predicate { $0.id == jobID }) { job in
                guard job.extractionStatus != .running else { return }
                job.extractionStatus = .running
                job.extractionError = nil
                job.updatedAt = Date()
            }

            let result = try await ExtractionEngine.extract(
                snapshot: extractionSnapshot,
                provider: provider,
                settings: extractSettings
            )
            let durationMs = Int(Date().timeIntervalSince(startedAt) * 1000)

            // Guard: skip writing success if the request was cancelled while we were running.
            guard try await store.requestStatus(id: itemID) == .running else { return false }

            // Persist extraction result
            try await store.update(
                Job.self,
                predicate: #Predicate { $0.id == jobID }
            ) { job in
                // Preserve fields the user manually edited (Electron parity: manual_overrides).
                let overrides = manualFieldOverrideSet(job.manualFieldOverridesJSON)
                job.extractedJSON = result.extractedJSON
                if !overrides.contains("title") { job.title = result.title }
                if !overrides.contains("company") { job.company = result.company }
                if !overrides.contains("location") { job.location = result.location }
                if !overrides.contains("remoteType") { job.remoteType = result.remoteType }
                if !overrides.contains("salaryMin") { job.salaryMin = result.salaryMin }
                if !overrides.contains("salaryMax") { job.salaryMax = result.salaryMax }
                if !overrides.contains("salaryHourlyMin") { job.salaryHourlyMin = result.salaryHourlyMin }
                if !overrides.contains("salaryHourlyMax") { job.salaryHourlyMax = result.salaryHourlyMax }
                if !overrides.contains("salaryCurrency") { job.salaryCurrency = result.salaryCurrency }
                if !overrides.contains("salaryNote") { job.salaryNote = result.salaryNote }
                if !overrides.contains("employmentType") { job.employmentType = result.employmentType }
                if !overrides.contains("seniority") { job.seniority = result.seniority }
                if !overrides.contains("applicationURL") { job.applicationURL = result.applicationURL }
                job.extractionConfidence = result.extractionConfidence
                job.meetsCriteria = result.meetsCriteria
                job.extractionModel = result.extractionModel
                job.extractionStatus = .succeeded
                job.extractionError = nil
                job.extractedAt = Date()
                // The job now has fresh AI results to review — mark it unread so it counts toward
                // the Dock badge until the user opens it (markOpened clears it). A re-extraction
                // re-marks it unread, since the content changed (workflow.md step 4).
                job.unread = true
                job.updatedAt = Date()
            }

            // Persist attempt record — linked to request and job on the store actor (TASK-314/526)
            try await store.recordAttempt(
                requestID: itemID, jobID: jobID,
                requestType: .extract, attempt: item.attempt, status: .succeeded,
                // modelRequested = the configured model we sent; modelReturned = what the provider
                // actually used (they differ under OpenRouter free-model rotation). Provider identity
                // (provider.id) is intentionally NOT stored here — it's not a model id (TASK-535).
                modelRequested: extractSettings.llmModel, modelReturned: result.extractionModel,
                responseFormat: result.responseFormat.wireValue,
                startedAt: startedAt, finishedAt: Date(), durationMs: durationMs,
                promptChars: result.promptChars, responseChars: result.responseChars
            )

            // Mark request succeeded
            try await store.update(
                LLMRequest.self,
                predicate: #Predicate { $0.id == itemID }
            ) { req in
                req.status = .succeeded
                req.finishedAt = Date()
                req.model = result.extractionModel
                // Clear any error left over from an earlier failed attempt that was retried —
                // otherwise a succeeded row still shows a stale error in the queue.
                req.error = nil
            }

            // Timeline: record extraction as a system event.
            try? await store.insertJobEvent(jobID: jobID, eventType: "extraction", note: result.extractionModel)

            // Electron parity: auto-score fit against all active resumes (no-op when none
            // is active). The drain loop re-fetches queued requests, so the new fit requests
            // run on the next iteration without an explicit restart.
            _ = try? await store.enqueueFitForActiveResumes(jobID: jobID)

            emit(.jobReady(jobNumber: item.jobNumber, title: item.jobTitle, fitScore: nil))
            return true
        } catch {
            // A cancellation in flight (auto-pause cancelAll / shutdown) isn't a real attempt — don't
            // record a failed attempt, fail the job, or back off; rethrow so processRequest requeues.
            if error is CancellationError || Task.isCancelled { throw error }
            let durationMs = Int(Date().timeIntervalSince(startedAt) * 1000)
            let errorStr = error.localizedDescription

            // Record failed attempt — linked on the store actor (TASK-314/526)
            try await store.recordAttempt(
                requestID: itemID, jobID: jobID,
                requestType: .extract, attempt: item.attempt, status: .failed,
                modelRequested: extractSettings.llmModel, startedAt: startedAt, finishedAt: Date(),
                durationMs: durationMs, error: errorStr
            )

            if item.attempt >= Self.maxRetries {
                try await store.update(
                    LLMRequest.self,
                    predicate: #Predicate { $0.id == itemID }
                ) { req in
                    req.status = .retryExhausted
                    req.finishedAt = Date()
                    req.error = errorStr
                }
                try await store.update(
                    Job.self,
                    predicate: #Predicate { $0.id == jobID }
                ) { job in
                    job.extractionStatus = .failed
                    job.extractionError = errorStr
                    job.updatedAt = Date()
                }
            } else {
                // Backoff then re-queue. A 429 honors the server's Retry-After (TASK-463); otherwise
                // generic exponential backoff.
                let backoffMs = Self.backoffMs(for: error, attempt: item.attempt)
                try await Task.sleep(nanoseconds: UInt64(backoffMs) * 1_000_000)
                // TASK-447: a user cancellation during the backoff sleep sets the row to .cancelled.
                // Only requeue if it's still .running, so the cancellation stays authoritative and a
                // cancelled (possibly billable) cloud request is not silently retried.
                try await store.update(
                    LLMRequest.self,
                    predicate: #Predicate { $0.id == itemID }
                ) { req in
                    guard req.status == .running else { return }
                    req.status = .queued
                    req.attempt = item.attempt + 1
                    req.startedAt = nil
                    req.error = errorStr
                }
            }
            throw error
        }
    }

    /// Backoff in ms: honor a 429's Retry-After (clamped) over generic exponential backoff (TASK-463).
    static func backoffMs(for error: Error, attempt: Int) -> Int {
        if case let LLMProviderError.rateLimited(retryAfter) = error, let retryAfter {
            return Int(min(retryAfter, maxRetryAfterSeconds) * 1000)
        }
        return min(Int(pow(2.0, Double(attempt))) * 1000, 30000)
    }

    private func processFitRequest(
        item: QueuedItem,
        provider: any LLMProvider,
        startedAt: Date
    ) async throws -> Bool {
        let itemID = item.id
        guard let jobID = item.jobID,
              let resumeID = item.resumeID else {
            await markRequestCancelled(id: itemID)
            return false
        }

        // TASK-526: build fit inputs on the store actor — never read the live Job/Resume off-actor.
        guard let fitInputs = try await store.fitInputs(forJobID: jobID, resumeID: resumeID) else {
            await markRequestCancelled(id: itemID)
            return false
        }
        guard fitInputs.resumeExists,
              !fitInputs.resumeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            let errMsg = fitInputs.resumeExists ? "Resume has no text to score against." : "Resume no longer exists."
            // TASK-317: Record attempt history for pre-provider failures
            try? await store.recordAttempt(
                requestID: itemID, jobID: jobID,
                requestType: .fit, attempt: item.attempt, status: .failed,
                modelRequested: nil, startedAt: startedAt, finishedAt: Date(), error: errMsg
            )
            try await store.update(
                LLMRequest.self,
                predicate: #Predicate { $0.id == itemID }
            ) { req in
                req.status = .failed
                req.finishedAt = Date()
                req.error = errMsg
            }
            // TASK-520: a pre-provider failure must move the fit record off .pending too, or the
            // job's fit mirror is stuck "pending" forever.
            try? await store.markFitScoreFailed(jobID: jobID, resumeID: resumeID, errorMessage: errMsg)
            return false
        }

        let fitSettings = await readExtractionSettings()

        // Enforce consent immediately before sending data to a cloud provider.
        let consented = ConsentHelper.isConsented(
            provider: fitSettings.llmProvider,
            baseURL: fitSettings.llmBaseURL,
            consentGranted: fitSettings.consentGranted
        )
        guard consented else {
            await markRequestFailed(item: item, error: ConsentError.notConsented, startedAt: startedAt)
            // TASK-520: keep the fit record's state consistent with the failed request.
            try? await store.markFitScoreFailed(
                jobID: jobID,
                resumeID: resumeID,
                errorMessage: ConsentError.notConsented.localizedDescription
            )
            return false
        }

        let fitModel = fitSettings.llmModel

        // Stamp the model as soon as the request is running so the queue shows it immediately,
        // not only once the request completes. Overwritten with the returned model on success.
        await setRequestModel(itemID: itemID, model: fitModel)

        let jobSnap = fitInputs.job
        let resumeSnap = ResumeSnapshot(text: fitInputs.resumeText)

        try? await store.markFitScoreRunning(jobID: jobID, resumeID: resumeID)

        do {
            let fitOutput = try await ExtractionEngine.scoreFit(
                job: jobSnap,
                resume: resumeSnap,
                model: fitModel,
                provider: provider
            )
            let fitResult = fitOutput.score
            let durationMs = Int(Date().timeIntervalSince(startedAt) * 1000)

            // Guard: skip writing success if the request was cancelled while we were running.
            guard try await store.requestStatus(id: itemID) == .running else { return false }

            let fitJSON = fitOutput.fitScoreJSON ?? FitScorer.encode(fitResult)
            let scoredAt = Date()
            try await store.saveFitScore(
                jobID: jobID,
                resumeID: resumeID,
                overall: fitResult.overall,
                fitJSON: fitJSON,
                // Store the model that produced the score: the returned model when the provider
                // reports one, else the configured model — never the provider id (TASK-535).
                model: fitOutput.modelReturned ?? fitModel,
                scoredAt: scoredAt
            )

            // Persist attempt record — linked on the store actor (TASK-314/526)
            try await store.recordAttempt(
                requestID: itemID, jobID: jobID,
                requestType: .fit, attempt: item.attempt, status: .succeeded,
                modelRequested: fitModel, modelReturned: fitOutput.modelReturned,
                responseFormat: fitOutput.responseFormat.wireValue,
                startedAt: startedAt, finishedAt: Date(), durationMs: durationMs,
                promptChars: fitOutput.promptChars, responseChars: fitOutput.responseChars
            )

            try await store.update(
                LLMRequest.self,
                predicate: #Predicate { $0.id == itemID }
            ) { req in
                req.status = .succeeded
                req.finishedAt = Date()
                // Record the model used (was previously left nil, so Fit rows showed "—")
                // and clear any error from an earlier retried attempt.
                req.model = fitOutput.modelReturned
                req.error = nil
            }

            emit(.jobReady(
                jobNumber: item.jobNumber,
                title: item.jobTitle,
                fitScore: fitResult.overall
            ))
            return true
        } catch {
            // A cancellation in flight (auto-pause cancelAll / shutdown) isn't a real attempt — don't
            // record a failed attempt, fail the fit score, or back off; rethrow so processRequest requeues.
            if error is CancellationError || Task.isCancelled { throw error }
            let durationMs = Int(Date().timeIntervalSince(startedAt) * 1000)
            let errorStr = error.localizedDescription

            // Persist attempt record — linked on the store actor (TASK-314/526)
            try await store.recordAttempt(
                requestID: itemID, jobID: jobID,
                requestType: .fit, attempt: item.attempt, status: .failed,
                modelRequested: fitModel, startedAt: startedAt, finishedAt: Date(),
                durationMs: durationMs, error: errorStr
            )

            if item.attempt >= Self.maxRetries {
                try await store.update(
                    LLMRequest.self,
                    predicate: #Predicate { $0.id == itemID }
                ) { req in
                    req.status = .retryExhausted
                    req.finishedAt = Date()
                    req.error = errorStr
                }
                try? await store.markFitScoreFailed(jobID: jobID, resumeID: resumeID, errorMessage: errorStr)
            } else {
                let backoffMs = Self.backoffMs(for: error, attempt: item.attempt)
                try await Task.sleep(nanoseconds: UInt64(backoffMs) * 1_000_000)
                // TASK-447: a user cancellation during the backoff sleep sets the row to .cancelled.
                // Only requeue if it's still .running, so the cancellation stays authoritative and a
                // cancelled (possibly billable) cloud request is not silently retried.
                try await store.update(
                    LLMRequest.self,
                    predicate: #Predicate { $0.id == itemID }
                ) { req in
                    guard req.status == .running else { return }
                    req.status = .queued
                    req.attempt = item.attempt + 1
                    req.startedAt = nil
                    req.error = errorStr
                }
            }
            throw error
        }
    }

    private func markRequestFailed(item: QueuedItem, error: Error, startedAt _: Date) async {
        let itemID = item.id
        let errorStr = error.localizedDescription
        do {
            try await store.update(
                LLMRequest.self,
                predicate: #Predicate { $0.id == itemID }
            ) { req in
                // TASK-313: Only overwrite if still running — don't clobber retry/retryExhausted states
                guard req.status == .running else { return }
                req.status = .failed
                req.finishedAt = Date()
                req.error = errorStr
            }
        } catch {
            // Don't silently drop a failure-persistence error — a request could otherwise be left
            // stuck .running. Log it (and surface a degraded state for diagnostics).
            NSLog("QueueActor: failed to persist request failure for \(itemID): \(error)")
            emit(.queueError("Couldn't record an LLM request failure: \(error.localizedDescription)"))
        }
    }

    /// Records the model on a request while it is running, so the queue shows it during processing
    /// rather than only after completion. No-op if the row is no longer running or the model is blank.
    private func setRequestModel(itemID: String, model: String) async {
        guard !model.isEmpty else { return }
        try? await store.update(
            LLMRequest.self,
            predicate: #Predicate { $0.id == itemID }
        ) { req in
            guard req.status == .running else { return }
            req.model = model
        }
    }

    private func markRequestCancelled(id: String) async {
        do {
            try await store.update(
                LLMRequest.self,
                predicate: #Predicate { $0.id == id }
            ) { req in
                req.status = .cancelled
                req.finishedAt = Date()
            }
        } catch {
            NSLog("QueueActor: failed to persist request cancellation for \(id): \(error)")
            emit(.queueError("Couldn't record an LLM request cancellation: \(error.localizedDescription)"))
        }
    }
}

// MARK: - QueuedItem

/// Lightweight value type for items fetched from the queue.
private struct QueuedItem {
    let id: String
    let requestType: LLMRequestType
    let attempt: Int
    let jobID: String?
    let jobNumber: Int?
    let jobTitle: String?
    let resumeID: String?
}

// MARK: - ConsentError

public enum ConsentError: Error, LocalizedError {
    case notConsented

    public var errorDescription: String? {
        "Cloud LLM consent not granted. Enable the provider in Settings to process jobs."
    }
}

// MARK: - FitEnqueueError

public enum FitEnqueueError: Error, LocalizedError, Equatable {
    /// The resume to score against no longer exists (TASK-452).
    case resumeNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .resumeNotFound:
            "The selected resume no longer exists. Choose another resume and try again."
        }
    }
}

// swiftlint:enable file_length function_body_length type_body_length
