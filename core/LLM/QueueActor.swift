// swiftlint:disable file_length function_body_length type_body_length
import Foundation
import SwiftData

// MARK: - QueueEvent

/// Domain events emitted by the queue, consumed by platform integration.
public enum QueueEvent: Sendable {
    case jobReady(jobNumber: Int?, title: String?, fitScore: Int?)
    case jobUnavailable(jobNumber: Int?)
    case processingComplete(processed: Int, failed: Int)
    case autoPaused
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
    private let providerFactory: @Sendable () -> any LLMProvider
    /// Read the current queue-paused flag. Implementations should dispatch to @MainActor.
    private let isPaused: @Sendable () async -> Bool
    /// Write the queue-paused flag. Implementations should dispatch to @MainActor.
    private let onSetPaused: @Sendable (Bool) async -> Void
    /// Snapshot extraction-relevant settings. Implementations should dispatch to @MainActor.
    private let readExtractionSettings: @Sendable () async -> ExtractionSettings

    // MARK: - State

    private var isRunning = false
    /// Consecutive failure count across the whole queue (reset on success).
    private var failureStreak = 0
    /// Active in-flight request count per provider id.
    private var activeCounts: [String: Int] = [:]

    static let maxRetries = 3
    static let autoPauseThreshold = 2

    // MARK: - Init

    public init(
        store: BackgroundStore,
        isPaused: @escaping @Sendable () async -> Bool,
        onSetPaused: @escaping @Sendable (Bool) async -> Void,
        readExtractionSettings: @escaping @Sendable () async -> ExtractionSettings,
        providerFactory: @escaping @Sendable () -> any LLMProvider
    ) {
        self.store = store
        self.isPaused = isPaused
        self.onSetPaused = onSetPaused
        self.readExtractionSettings = readExtractionSettings
        self.providerFactory = providerFactory
    }

    // MARK: - Public API

    /// Enqueue new LLM extraction requests for a set of job IDs.
    /// Fetches all needed Job objects in a single query and saves all LLMRequest rows at once.
    public func enqueue(jobIDs: [String], mode: LLMRequestType) async throws {
        guard !jobIDs.isEmpty else { return }
        let ids = jobIDs
        let jobs = try await store.fetch(FetchDescriptor<Job>(predicate: #Predicate { ids.contains($0.id) }))
        let jobMap = Dictionary(jobs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let requests = jobIDs.compactMap { jobID -> LLMRequest? in
            guard let job = jobMap[jobID] else { return nil }
            let req = LLMRequest(requestType: mode, status: .queued)
            req.job = job
            return req
        }
        try await store.insertBatch(requests)
    }

    /// Enqueue fit-scoring requests for a set of job IDs against a specific resume.
    /// Also creates/updates a JobFitScore record for each (job, resume) pair with fitStatus = .pending.
    public func enqueueFit(jobIDs: [String], resumeID: String) async throws {
        guard !jobIDs.isEmpty else { return }
        let ids = jobIDs
        let jobs = try await store.fetch(FetchDescriptor<Job>(predicate: #Predicate { ids.contains($0.id) }))
        let jobMap = Dictionary(jobs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let resumes = try await store.fetch(FetchDescriptor<Resume>(predicate: #Predicate { $0.id == resumeID }))
        guard let resume = resumes.first else { return }
        for jobID in jobIDs {
            guard let job = jobMap[jobID] else { continue }
            let req = LLMRequest(requestType: .fit, status: .queued)
            req.job = job
            req.resume = resume
            try await store.insert(req)
            try? await store.markFitScorePending(jobID: jobID, resumeID: resumeID)
        }
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

    /// Cancel a specific request by id.
    public func cancelRequest(id: String) async throws {
        try await store.update(
            LLMRequest.self,
            predicate: #Predicate { $0.id == id }
        ) { req in
            req.status = .cancelled
            req.finishedAt = Date()
        }
    }

    /// Cancel all queued and running requests.
    public func cancelAll() async throws {
        // Fetch all then filter in-memory — SwiftData predicates cannot compare enum cases.
        try await store.update(LLMRequest.self, predicate: nil) { req in
            guard req.status == .queued || req.status == .running else { return }
            req.status = .cancelled
            req.finishedAt = Date()
        }
    }

    /// Permanently delete specific requests by ID.
    public func deleteRequests(ids: [String]) async throws {
        let set = Set(ids)
        try await store.delete(LLMRequest.self, predicate: #Predicate { set.contains($0.id) })
    }

    /// Permanently delete all requests (all statuses).
    public func deleteAll() async throws {
        try await store.deleteAll(LLMRequest.self)
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
            guard await !isPaused() else { break }

            let provider = providerFactory()
            let limit = provider.concurrencyLimit

            let requests = await fetchQueuedRequests(limit: limit)
            guard !requests.isEmpty else { break }

            await withTaskGroup(of: ProcessResult.self) { group in
                for req in requests {
                    group.addTask {
                        await self.processRequest(req, provider: provider)
                    }
                }
                for await result in group {
                    totalProcessed += 1
                    if result.succeeded {
                        failureStreak = 0
                    } else {
                        totalFailed += 1
                        failureStreak += 1
                        if failureStreak >= Self.autoPauseThreshold {
                            await onSetPaused(true)
                            emit(.autoPaused)
                            break
                        }
                    }
                }
            }

            if await isPaused() { break }
        }

        emit(.processingComplete(processed: totalProcessed, failed: totalFailed))
    }

    // MARK: - Private processing

    private struct ProcessResult {
        let succeeded: Bool
    }

    private func fetchQueuedRequests(limit: Int) async -> [QueuedItem] {
        do {
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
        } catch {
            return []
        }
    }

    private func processRequest(_ item: QueuedItem, provider: any LLMProvider) async -> ProcessResult {
        // Mark as running
        let itemID = item.id
        do {
            try await store.update(
                LLMRequest.self,
                predicate: #Predicate { $0.id == itemID }
            ) { req in
                req.status = .running
                req.startedAt = Date()
            }
        } catch {
            return ProcessResult(succeeded: false)
        }

        let startedAt = Date()

        do {
            switch item.requestType {
            case .extract:
                let succeeded = try await processExtractRequest(item: item, provider: provider, startedAt: startedAt)
                return ProcessResult(succeeded: succeeded)
            case .fit:
                let succeeded = try await processFitRequest(item: item, provider: provider, startedAt: startedAt)
                return ProcessResult(succeeded: succeeded)
            }
        } catch {
            await markRequestFailed(item: item, error: error, startedAt: startedAt)
            return ProcessResult(succeeded: false)
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

        // Fetch the job and snapshot its fields before the async provider call
        let jobs = try await store.fetch(FetchDescriptor<Job>(predicate: #Predicate { $0.id == jobID }))
        guard let job = jobs.first else {
            await markRequestCancelled(id: itemID)
            return false
        }
        let extractionSnapshot = JobExtractionSnapshot(
            captureURL: job.capture?.url ?? "",
            captureCanonicalURL: job.capture?.canonicalURL,
            capturePageTitle: job.capture?.pageTitle ?? "",
            captureCleanedDescription: job.capture?.cleanedDescription,
            captureVisibleText: job.capture?.visibleText,
            captureSelectedText: job.capture?.selectedText
        )

        let attempt = LLMRequestAttempt(
            requestType: .extract,
            attempt: item.attempt,
            status: .running,
            modelRequested: provider.id,
            startedAt: startedAt
        )

        do {
            let extractSettings = await readExtractionSettings()

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

            let result = try await ExtractionEngine.extract(snapshot: extractionSnapshot, provider: provider, settings: extractSettings)
            let durationMs = Int(Date().timeIntervalSince(startedAt) * 1000)

            // Guard: skip writing success if the request was cancelled while we were running.
            let currentReqs = try await store.fetch(FetchDescriptor<LLMRequest>(predicate: #Predicate { $0.id == itemID }))
            guard currentReqs.first?.status == .running else { return false }

            // Persist extraction result
            try await store.update(
                Job.self,
                predicate: #Predicate { $0.id == jobID }
            ) { job in
                job.extractedJSON = result.extractedJSON
                job.title = result.title
                job.company = result.company
                job.location = result.location
                job.remoteType = result.remoteType
                job.salaryMin = result.salaryMin
                job.salaryMax = result.salaryMax
                job.salaryHourlyMin = result.salaryHourlyMin
                job.salaryHourlyMax = result.salaryHourlyMax
                job.salaryCurrency = result.salaryCurrency
                job.salaryNote = result.salaryNote
                job.employmentType = result.employmentType
                job.seniority = result.seniority
                job.applicationURL = result.applicationURL
                job.extractionConfidence = result.extractionConfidence
                job.extractionModel = result.extractionModel
                job.extractionStatus = .succeeded
                job.extractionError = nil
                job.extractedAt = Date()
                job.updatedAt = Date()
            }

            // Persist attempt record
            let finishedAttempt = LLMRequestAttempt(
                requestType: .extract,
                attempt: item.attempt,
                status: .succeeded,
                modelRequested: provider.id,
                modelReturned: result.extractionModel,
                startedAt: startedAt,
                finishedAt: Date(),
                durationMs: durationMs,
                promptChars: result.promptChars,
                responseChars: result.responseChars
            )
            try await store.insert(finishedAttempt)

            // Mark request succeeded
            try await store.update(
                LLMRequest.self,
                predicate: #Predicate { $0.id == itemID }
            ) { req in
                req.status = .succeeded
                req.finishedAt = Date()
                req.model = result.extractionModel
            }

            emit(.jobReady(jobNumber: item.jobNumber, title: item.jobTitle, fitScore: nil))
            return true
        } catch {
            let durationMs = Int(Date().timeIntervalSince(startedAt) * 1000)
            let errorStr = error.localizedDescription

            // Record failed attempt
            let failedAttempt = LLMRequestAttempt(
                requestType: .extract,
                attempt: item.attempt,
                status: .failed,
                modelRequested: provider.id,
                startedAt: startedAt,
                finishedAt: Date(),
                durationMs: durationMs,
                error: errorStr
            )
            try await store.insert(failedAttempt)

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
                // Backoff then re-queue
                let backoffMs = min(Int(pow(2.0, Double(item.attempt))) * 1000, 30000)
                try await Task.sleep(nanoseconds: UInt64(backoffMs) * 1_000_000)
                try await store.update(
                    LLMRequest.self,
                    predicate: #Predicate { $0.id == itemID }
                ) { req in
                    req.status = .queued
                    req.attempt = item.attempt + 1
                    req.startedAt = nil
                    req.error = errorStr
                }
            }
            throw error
        }
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

        // Fetch job and resume, then snapshot fields before the async provider call
        let jobs = try await store.fetch(FetchDescriptor<Job>(predicate: #Predicate { $0.id == jobID }))
        guard let job = jobs.first else {
            await markRequestCancelled(id: itemID)
            return false
        }

        let resumes = try await store.fetch(FetchDescriptor<Resume>(predicate: #Predicate { $0.id == resumeID }))
        guard let resume = resumes.first,
              !resume.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            let errMsg = resumes.isEmpty ? "Resume no longer exists." : "Resume has no text to score against."
            try await store.update(
                LLMRequest.self,
                predicate: #Predicate { $0.id == itemID }
            ) { req in
                req.status = .failed
                req.finishedAt = Date()
                req.error = errMsg
            }
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
            return false
        }

        let fitModel = fitSettings.llmModel

        let jobSnap = JobFitSnapshot(
            title: job.title,
            company: job.company,
            seniority: job.seniority,
            extractedJSON: job.extractedJSON,
            extractionModel: job.extractionModel
        )
        let resumeSnap = ResumeSnapshot(text: resume.text)

        try? await store.markFitScoreRunning(jobID: jobID, resumeID: resumeID)

        do {
            let fitOutput = try await ExtractionEngine.scoreFit(job: jobSnap, resume: resumeSnap, model: fitModel, provider: provider)
            let fitResult = fitOutput.score
            let durationMs = Int(Date().timeIntervalSince(startedAt) * 1000)

            // Guard: skip writing success if the request was cancelled while we were running.
            let currentReqs = try await store.fetch(FetchDescriptor<LLMRequest>(predicate: #Predicate { $0.id == itemID }))
            guard currentReqs.first?.status == .running else { return false }

            let fitJSON = fitOutput.fitScoreJSON ?? FitScorer.encode(fitResult)
            let scoredAt = Date()
            try await store.saveFitScore(
                jobID: jobID,
                resumeID: resumeID,
                overall: fitResult.overall,
                fitJSON: fitJSON,
                model: provider.id,
                scoredAt: scoredAt
            )

            let finishedAttempt = LLMRequestAttempt(
                requestType: .fit,
                attempt: item.attempt,
                status: .succeeded,
                modelRequested: provider.id,
                responseFormat: "json_object",
                startedAt: startedAt,
                finishedAt: Date(),
                durationMs: durationMs,
                promptChars: fitOutput.promptChars,
                responseChars: fitOutput.responseChars
            )
            try await store.insert(finishedAttempt)

            try await store.update(
                LLMRequest.self,
                predicate: #Predicate { $0.id == itemID }
            ) { req in
                req.status = .succeeded
                req.finishedAt = Date()
            }

            emit(.jobReady(
                jobNumber: item.jobNumber,
                title: item.jobTitle,
                fitScore: fitResult.overall
            ))
            return true
        } catch {
            let durationMs = Int(Date().timeIntervalSince(startedAt) * 1000)
            let errorStr = error.localizedDescription

            let failedAttempt = LLMRequestAttempt(
                requestType: .fit,
                attempt: item.attempt,
                status: .failed,
                modelRequested: provider.id,
                startedAt: startedAt,
                finishedAt: Date(),
                durationMs: durationMs,
                error: errorStr
            )
            try await store.insert(failedAttempt)

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
                try await store.update(
                    Job.self,
                    predicate: #Predicate { $0.id == jobID }
                ) { job in
                    job.fitStatus = .failed
                    job.updatedAt = Date()
                }
            } else {
                let backoffMs = min(Int(pow(2.0, Double(item.attempt))) * 1000, 30000)
                try await Task.sleep(nanoseconds: UInt64(backoffMs) * 1_000_000)
                try await store.update(
                    LLMRequest.self,
                    predicate: #Predicate { $0.id == itemID }
                ) { req in
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
        try? await store.update(
            LLMRequest.self,
            predicate: #Predicate { $0.id == itemID }
        ) { req in
            req.status = .failed
            req.finishedAt = Date()
            req.error = errorStr
        }
    }

    private func markRequestCancelled(id: String) async {
        try? await store.update(
            LLMRequest.self,
            predicate: #Predicate { $0.id == id }
        ) { req in
            req.status = .cancelled
            req.finishedAt = Date()
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

// swiftlint:enable file_length function_body_length type_body_length
