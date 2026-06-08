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

    // MARK: - Public API stream

    public let events: AsyncStream<QueueEvent>
    private let continuation: AsyncStream<QueueEvent>.Continuation

    // MARK: - Dependencies

    private let store: BackgroundStore
    private let providerFactory: @Sendable () -> any LLMProvider
    // nonisolated(unsafe) because SettingsStore is @Observable (not Sendable) but
    // all access goes through the actor's serialized execution context.
    nonisolated(unsafe) private let settings: SettingsStore

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
        settings: SettingsStore,
        providerFactory: @escaping @Sendable () -> any LLMProvider
    ) {
        self.store = store
        self.settings = settings
        self.providerFactory = providerFactory
        var cont: AsyncStream<QueueEvent>.Continuation!
        self.events = AsyncStream { cont = $0 }
        self.continuation = cont
    }

    // MARK: - Public API

    /// Enqueue new LLM extraction requests for a set of job IDs.
    /// Each job must already exist in the store; this method creates the LLMRequest rows
    /// and links them by fetching the Job objects from the store.
    public func enqueue(jobIDs: [String], mode: LLMRequestType) async throws {
        for jobID in jobIDs {
            let jobs = try await store.fetch(
                FetchDescriptor<Job>(predicate: #Predicate { $0.id == jobID })
            )
            guard let job = jobs.first else { continue }
            let request = LLMRequest(requestType: mode, status: .queued)
            request.job = job
            try await store.insert(request)
        }
    }

    /// On app launch, reset any requests stuck in "running" back to "queued".
    public func requeueRunningOnLaunch() async throws {
        // Fetch all then filter in-memory — SwiftData predicates cannot compare enum cases.
        try await store.update(LLMRequest.self, predicate: nil) { req in
            guard req.status == .running else { return }
            req.status = .queued
            req.startedAt = nil
            req.finishedAt = nil
            req.error = nil
        }
    }

    /// Pause the queue (prevents new requests from being processed).
    public func pauseQueue() async {
        settings.llmQueuePaused = true
    }

    /// Resume the queue and restart the drain loop.
    public func resumeQueue() async {
        settings.llmQueuePaused = false
        failureStreak = 0
    }

    /// Cancel a specific request by id.
    public func cancelRequest(id: String) async throws {
        try await store.update(LLMRequest.self,
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

    /// Reset a failed request back to queued so it can be retried.
    public func resetRequest(id: String) async throws {
        try await store.update(LLMRequest.self,
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
            guard !settings.llmQueuePaused else { break }

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
                            settings.llmQueuePaused = true
                            continuation.yield(.autoPaused)
                            break
                        }
                    }
                }
            }

            if settings.llmQueuePaused { break }
        }

        continuation.yield(.processingComplete(processed: totalProcessed, failed: totalFailed))
    }

    // MARK: - Private processing

    private struct ProcessResult: Sendable {
        let succeeded: Bool
    }

    private func fetchQueuedRequests(limit: Int) async -> [QueuedItem] {
        do {
            // SwiftData predicates cannot compare enum cases; sort+filter in Swift instead.
            var descriptor = FetchDescriptor<LLMRequest>(
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
            try await store.update(LLMRequest.self,
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

        // Fetch the job
        let jobs = try await store.fetch(FetchDescriptor<Job>(predicate: #Predicate { $0.id == jobID }))
        guard let job = jobs.first else {
            await markRequestCancelled(id: itemID)
            return false
        }

        let attempt = LLMRequestAttempt(
            requestType: .extract,
            attempt: item.attempt,
            status: .running,
            modelRequested: provider.id,
            startedAt: startedAt
        )

        do {
            let result = try await ExtractionEngine.extract(job: job, provider: provider, settings: settings)
            let durationMs = Int(Date().timeIntervalSince(startedAt) * 1000)

            // Persist extraction result
            try await store.update(Job.self,
                predicate: #Predicate { $0.id == jobID }
            ) { job in
                job.extractedJSON = result.extractedJSON
                job.title = result.title ?? job.title
                job.company = result.company ?? job.company
                job.location = result.location ?? job.location
                job.remoteType = result.remoteType ?? job.remoteType
                job.salaryMin = result.salaryMin ?? job.salaryMin
                job.salaryMax = result.salaryMax ?? job.salaryMax
                job.salaryCurrency = result.salaryCurrency ?? job.salaryCurrency
                job.salaryNote = result.salaryNote ?? job.salaryNote
                job.employmentType = result.employmentType ?? job.employmentType
                job.seniority = result.seniority ?? job.seniority
                job.applicationURL = result.applicationURL ?? job.applicationURL
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
            try await store.update(LLMRequest.self,
                predicate: #Predicate { $0.id == itemID }
            ) { req in
                req.status = .succeeded
                req.finishedAt = Date()
                req.model = result.extractionModel
            }

            continuation.yield(.jobReady(jobNumber: item.jobNumber, title: item.jobTitle, fitScore: nil))
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
                try await store.update(LLMRequest.self,
                    predicate: #Predicate { $0.id == itemID }
                ) { req in
                    req.status = .retryExhausted
                    req.finishedAt = Date()
                    req.error = errorStr
                }
                try await store.update(Job.self,
                    predicate: #Predicate { $0.id == jobID }
                ) { job in
                    job.extractionStatus = .failed
                    job.extractionError = errorStr
                    job.updatedAt = Date()
                }
            } else {
                // Backoff then re-queue
                let backoffMs = min(Int(pow(2.0, Double(item.attempt))) * 1000, 30_000)
                try await Task.sleep(nanoseconds: UInt64(backoffMs) * 1_000_000)
                try await store.update(LLMRequest.self,
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

        let jobs = try await store.fetch(FetchDescriptor<Job>(predicate: #Predicate { $0.id == jobID }))
        guard let job = jobs.first else {
            await markRequestCancelled(id: itemID)
            return false
        }

        let resumes = try await store.fetch(FetchDescriptor<Resume>(predicate: #Predicate { $0.id == resumeID }))
        guard let resume = resumes.first,
              !resume.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            let errMsg = resumes.isEmpty ? "Resume no longer exists." : "Resume has no text to score against."
            try await store.update(LLMRequest.self,
                predicate: #Predicate { $0.id == itemID }
            ) { req in
                req.status = .failed
                req.finishedAt = Date()
                req.error = errMsg
            }
            return false
        }

        do {
            let fitResult = try await ExtractionEngine.scoreFit(job: job, resume: resume, provider: provider)
            let durationMs = Int(Date().timeIntervalSince(startedAt) * 1000)

            let fitJSON = FitScorer.encode(fitResult)
            try await store.update(Job.self,
                predicate: #Predicate { $0.id == jobID }
            ) { job in
                job.fitScore = fitResult.overall
                job.fitStatus = .succeeded
                job.fitScoreJSON = fitJSON
                job.updatedAt = Date()
            }

            let finishedAttempt = LLMRequestAttempt(
                requestType: .fit,
                attempt: item.attempt,
                status: .succeeded,
                modelRequested: provider.id,
                startedAt: startedAt,
                finishedAt: Date(),
                durationMs: durationMs
            )
            try await store.insert(finishedAttempt)

            try await store.update(LLMRequest.self,
                predicate: #Predicate { $0.id == itemID }
            ) { req in
                req.status = .succeeded
                req.finishedAt = Date()
            }

            continuation.yield(.jobReady(
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
                try await store.update(LLMRequest.self,
                    predicate: #Predicate { $0.id == itemID }
                ) { req in
                    req.status = .retryExhausted
                    req.finishedAt = Date()
                    req.error = errorStr
                }
                try await store.update(Job.self,
                    predicate: #Predicate { $0.id == jobID }
                ) { job in
                    job.fitStatus = .failed
                    job.updatedAt = Date()
                }
            } else {
                let backoffMs = min(Int(pow(2.0, Double(item.attempt))) * 1000, 30_000)
                try await Task.sleep(nanoseconds: UInt64(backoffMs) * 1_000_000)
                try await store.update(LLMRequest.self,
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

    private func markRequestFailed(item: QueuedItem, error: Error, startedAt: Date) async {
        let itemID = item.id
        let errorStr = error.localizedDescription
        try? await store.update(LLMRequest.self,
            predicate: #Predicate { $0.id == itemID }
        ) { req in
            req.status = .failed
            req.finishedAt = Date()
            req.error = errorStr
        }
    }

    private func markRequestCancelled(id: String) async {
        try? await store.update(LLMRequest.self,
            predicate: #Predicate { $0.id == id }
        ) { req in
            req.status = .cancelled
            req.finishedAt = Date()
        }
    }
}

// MARK: - QueuedItem

/// Lightweight value type for items fetched from the queue.
private struct QueuedItem: Sendable {
    let id: String
    let requestType: LLMRequestType
    let attempt: Int
    let jobID: String?
    let jobNumber: Int?
    let jobTitle: String?
    let resumeID: String?
}
// swiftlint:enable file_length function_body_length type_body_length
