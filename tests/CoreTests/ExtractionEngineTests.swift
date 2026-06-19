import SwiftData
import XCTest
@testable import JobhuntCore

// MARK: - Shared test helpers

private func makeExtractionSettings() -> ExtractionSettings {
    ExtractionSettings(
        llmModel: "stub-model",
        preferredLocations: "",
        locationFilterEnabled: false,
        locationAllowRemote: true,
        locationAllowHybrid: true,
        locationAllowOnsite: true
    )
}

// MARK: - Stub providers for testing

/// A provider that always fails with a given error.
private struct AlwaysFailProvider: LLMProvider {
    let id: String = "always-fail"
    var concurrencyLimit: Int = 1
    let error: Error

    func complete(_: ChatRequest) async throws -> ChatResponse {
        throw error
    }
}

/// Records the model string from the last ChatRequest it receives.
private final class CapturingProvider: LLMProvider, @unchecked Sendable {
    let id: String = "capturing"
    let concurrencyLimit: Int = 1
    private(set) var lastRequestedModel: String?
    private(set) var lastRequest: ChatRequest?
    private let response: String
    /// Format this provider reports it used (TASK-454: lets tests simulate a JSON success,
    /// a downgrade to json_object, or an always-text provider).
    private let usedFormat: ResponseFormat

    init(response: String, usedFormat: ResponseFormat = .text) {
        self.response = response
        self.usedFormat = usedFormat
    }

    func complete(_ request: ChatRequest) async throws -> ChatResponse {
        lastRequestedModel = request.model
        lastRequest = request
        return ChatResponse(content: response, model: request.model, responseFormat: usedFormat)
    }
}

/// A provider that waits a short delay before returning a canned success response.
private struct DelayedSuccessProvider: LLMProvider {
    let id: String = "delayed-success"
    let concurrencyLimit: Int = 1
    let delay: TimeInterval
    let response: String

    func complete(_: ChatRequest) async throws -> ChatResponse {
        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        return ChatResponse(content: response, model: "stub-model", responseFormat: .text)
    }
}

/// A provider that succeeds on a given attempt number, fails before that.
private final class CountingProvider: LLMProvider, @unchecked Sendable {
    let id: String = "counting"
    let concurrencyLimit: Int = 1
    private var callCount = 0
    private let succeedOnAttempt: Int
    private let successResponse: String
    private let lock = NSLock()

    init(succeedOnAttempt: Int, successResponse: String) {
        self.succeedOnAttempt = succeedOnAttempt
        self.successResponse = successResponse
    }

    func complete(_: ChatRequest) async throws -> ChatResponse {
        let count: Int = lock.withLock {
            callCount += 1
            return callCount
        }
        if count < succeedOnAttempt {
            throw LLMProviderError.httpError(statusCode: 500, body: "fail")
        }
        return ChatResponse(
            content: successResponse,
            model: "stub-model",
            responseFormat: .text
        )
    }
}

// MARK: - ExtractionEngineTests

final class ExtractionEngineTests: XCTestCase {
    // MARK: - CostEstimator token math

    func testCostEstimateTokenMath() {
        let tokens = CostEstimator.tokenEstimate(chars: 4000)
        XCTAssertEqual(tokens, 1000)
    }

    func testTokenEstimateRoundsDown() {
        // 4001 chars / 4 = 1000 (integer division)
        XCTAssertEqual(CostEstimator.tokenEstimate(chars: 4001), 1000)
        XCTAssertEqual(CostEstimator.tokenEstimate(chars: 4003), 1000)
        XCTAssertEqual(CostEstimator.tokenEstimate(chars: 4004), 1001)
    }

    func testTokenEstimateZero() {
        XCTAssertEqual(CostEstimator.tokenEstimate(chars: 0), 0)
    }

    // MARK: - CostEstimator total cost math

    func testCostEstimateTotalCost() throws {
        let container = try ModelContainerFactory.inMemory()
        let context = ModelContext(container)
        let settings = SettingsStore(modelContext: context)

        // $1 per 1M input tokens, $2 per 1M output tokens
        // With 1 job and 0 resume chars
        let estimate = CostEstimator.estimateCost(
            jobCount: 1,
            resumeCharCount: 0,
            priceInputPer1M: 1.0,
            priceOutputPer1M: 2.0,
            settings: settings
        )

        // Verify structure
        XCTAssertGreaterThan(estimate.inputTokens, 0)
        XCTAssertGreaterThan(estimate.outputTokens, 0)
        XCTAssertEqual(estimate.totalTokens, estimate.inputTokens + estimate.outputTokens)

        // Cost math: inputCost + outputCost
        let expectedCost = Double(estimate.inputTokens) * 1.0 / 1_000_000
            + Double(estimate.outputTokens) * 2.0 / 1_000_000
        XCTAssertEqual(estimate.estimatedCostUSD, expectedCost, accuracy: 1e-10)
    }

    func testCostEstimateScalesWithJobCount() throws {
        let container = try ModelContainerFactory.inMemory()
        let context = ModelContext(container)
        let settings = SettingsStore(modelContext: context)

        let single = CostEstimator.estimateCost(
            jobCount: 1,
            resumeCharCount: 1000,
            priceInputPer1M: 1.0,
            priceOutputPer1M: 1.0,
            settings: settings
        )
        let ten = CostEstimator.estimateCost(
            jobCount: 10,
            resumeCharCount: 1000,
            priceInputPer1M: 1.0,
            priceOutputPer1M: 1.0,
            settings: settings
        )

        // Integer division means token counts may differ by up to jobCount-1 per field.
        XCTAssertLessThanOrEqual(abs(ten.inputTokens - single.inputTokens * 10), 9)
        XCTAssertLessThanOrEqual(abs(ten.outputTokens - single.outputTokens * 10), 9)
        XCTAssertEqual(ten.estimatedCostUSD, single.estimatedCostUSD * 10, accuracy: 1e-5)
    }

    func testCostEstimateZeroPrice() throws {
        let container = try ModelContainerFactory.inMemory()
        let context = ModelContext(container)
        let settings = SettingsStore(modelContext: context)

        let estimate = CostEstimator.estimateCost(
            jobCount: 100,
            resumeCharCount: 5000,
            priceInputPer1M: 0.0,
            priceOutputPer1M: 0.0,
            settings: settings
        )
        XCTAssertEqual(estimate.estimatedCostUSD, 0.0)
        XCTAssertGreaterThan(estimate.totalTokens, 0)
    }

    // TASK-449: auto-pause works with a provider concurrency limit > 1 (batched), pausing the queue
    // and cancelling the rest of the batch rather than draining every request.
    func testAutoPause_withConcurrencyGreaterThanOne() async throws {
        let container = try ModelContainerFactory.inMemory()
        let store = BackgroundStore(modelContainer: container)
        let failProvider = AlwaysFailProvider(
            concurrencyLimit: 3,
            error: LLMProviderError.unavailable(reason: "stub failure")
        )
        var paused = false
        let queue = QueueActor(
            store: store,
            isPaused: { paused },
            onSetPaused: { paused = $0 },
            readExtractionSettings: { makeExtractionSettings() },
            providerFactory: { failProvider }
        )

        var jobIDs: [String] = []
        for idx in 0 ..< 5 {
            let capture = Capture(
                url: "https://example.com/job\(idx)",
                pageTitle: "Job \(idx)",
                selectedText: "Description \(idx).",
                rawHash: "ap-\(idx)"
            )
            let job = Job(jobNumber: idx + 1, title: "Job \(idx + 1)")
            job.capture = capture
            try await store.insert(job)
            jobIDs.append(job.id)
        }
        try await queue.enqueue(jobIDs: jobIDs, mode: .extract)
        await queue.startProcessing()

        XCTAssertTrue(paused, "repeated failures must auto-pause even with a wide batch")
        // Not every request was processed to a terminal failure — at least one stayed queued
        // (cancelled by auto-pause), so the queue stopped rather than draining all 5.
        let reqs = try await store.fetch(FetchDescriptor<LLMRequest>())
        let queued = reqs.filter { $0.status == .queued }
        XCTAssertFalse(queued.isEmpty, "auto-pause should leave remaining batch work queued, not drain it")
    }

    // MARK: - Provider-not-configured notice (TASK-483)

    /// Queued work with no usable provider must emit `.providerNotConfigured` and leave the work
    /// queued — NOT fail it into an auto-pause. The provider must never be invoked.
    func testProviderNotConfigured_emitsNoticeAndLeavesWorkQueued() async throws {
        let container = try ModelContainerFactory.inMemory()
        let store = BackgroundStore(modelContainer: container)
        // Would fail if ever called — proves the queue bailed before touching the provider.
        let provider = AlwaysFailProvider(error: LLMProviderError.unavailable(reason: "should not run"))
        var paused = false
        let queue = QueueActor(
            store: store,
            isPaused: { paused },
            onSetPaused: { paused = $0 },
            readExtractionSettings: { makeExtractionSettings() },
            providerFactory: { provider },
            isProviderConfigured: { false }
        )

        let capture = Capture(
            url: "https://example.com/job",
            pageTitle: "Job",
            selectedText: "Description for the role.",
            rawHash: "not-configured"
        )
        let job = Job(jobNumber: 1, title: "Job 1")
        job.capture = capture
        try await store.insert(job)
        // Insert the queued request directly (bypass enqueue's kick) for a deterministic single drain.
        let req = LLMRequest(requestType: .extract, status: .queued)
        req.job = job
        try await store.insert(req)

        let events = await queue.subscribe()
        await queue.startProcessing()

        var sawNotConfigured = false
        for await event in events {
            if case .providerNotConfigured = event { sawNotConfigured = true }
            if case .processingComplete = event { break }
        }

        XCTAssertTrue(sawNotConfigured, "must notify that no provider is configured")
        XCTAssertFalse(paused, "an unconfigured provider must not auto-pause the queue")
        let reqs = try await store.fetch(FetchDescriptor<LLMRequest>())
        XCTAssertEqual(reqs.first?.status, .queued, "work must stay queued for when a provider is set up")
    }

    /// The notice is debounced to one per unconfigured episode: a second drain while still
    /// unconfigured must NOT re-emit it (AC#4 — no spam as more captures queue up).
    func testProviderNotConfigured_isDebouncedAcrossDrains() async throws {
        let container = try ModelContainerFactory.inMemory()
        let store = BackgroundStore(modelContainer: container)
        let provider = AlwaysFailProvider(error: LLMProviderError.unavailable(reason: "should not run"))
        let queue = QueueActor(
            store: store,
            isPaused: { false },
            onSetPaused: { _ in },
            readExtractionSettings: { makeExtractionSettings() },
            providerFactory: { provider },
            isProviderConfigured: { false }
        )

        let capture = Capture(
            url: "https://example.com/job",
            pageTitle: "Job",
            selectedText: "Description.",
            rawHash: "debounce"
        )
        let job = Job(jobNumber: 1, title: "Job 1")
        job.capture = capture
        try await store.insert(job)
        let req = LLMRequest(requestType: .extract, status: .queued)
        req.job = job
        try await store.insert(req)

        let events = await queue.subscribe()
        await queue.startProcessing() // pass 1 — should emit the notice
        await queue.startProcessing() // pass 2 — still unconfigured, must stay silent

        var notConfiguredCount = 0
        var completes = 0
        for await event in events {
            if case .providerNotConfigured = event { notConfiguredCount += 1 }
            if case .processingComplete = event { completes += 1; if completes == 2 { break } }
        }
        XCTAssertEqual(notConfiguredCount, 1, "exactly one notice across two unconfigured drains")
    }

    // MARK: - QueueActor cancellation during retry backoff (TASK-447)

    /// A user cancellation that lands while a failed request is sleeping in its retry backoff must
    /// stay authoritative — the post-sleep requeue must not resurrect it (and re-bill a cloud call).
    func testCancellationDuringRetryBackoffIsPreserved() async throws {
        let container = try ModelContainerFactory.inMemory()
        let store = BackgroundStore(modelContainer: container)

        let failProvider = AlwaysFailProvider(error: LLMProviderError.unavailable(reason: "stub failure"))
        var paused = false
        let queue = QueueActor(
            store: store,
            isPaused: { paused },
            onSetPaused: { paused = $0 },
            readExtractionSettings: { makeExtractionSettings() },
            providerFactory: { failProvider }
        )

        let capture = Capture(
            url: "https://example.com/job", pageTitle: "Job",
            selectedText: "Description for the role.", rawHash: "cancel-backoff"
        )
        let job = Job(jobNumber: 1, title: "Job 1")
        job.capture = capture
        try await store.insert(job)

        let events = await queue.subscribe()
        // enqueue kicks the drain: attempt 1 fails fast, then the request sleeps ~2s in backoff.
        try await queue.enqueue(jobIDs: [job.id], mode: .extract)

        let reqs = try await store.fetch(FetchDescriptor<LLMRequest>())
        let reqID = try XCTUnwrap(reqs.first).id

        // Cancel mid-backoff (well before the ~2s sleep elapses and the requeue runs).
        try await Task.sleep(nanoseconds: 600_000_000)
        try await queue.cancelRequest(id: reqID)

        // Wait for the drain — including the post-backoff requeue attempt — to finish.
        for await event in events {
            if case .processingComplete = event { break }
        }

        let after = try await store.fetch(FetchDescriptor<LLMRequest>(predicate: #Predicate { $0.id == reqID }))
        XCTAssertEqual(
            after.first?.status,
            .cancelled,
            "Cancellation during backoff must survive the post-sleep requeue"
        )
    }

    /// TASK-387 AC#5: a genuinely empty queue (no fetch error) still emits the normal
    /// processingComplete event — only a store-read *failure* takes the degraded path.
    func testStartProcessing_fetchFailure_emitsQueueErrorNotComplete() async throws {
        // TASK-479/387 AC#4: a store-read failure during the drain must surface as a queueError and
        // NOT a (false) processingComplete that would look like all work finished.
        let container = try ModelContainerFactory.inMemory()
        let store = BackgroundStore(modelContainer: container)
        struct FakeStoreError: Error {}
        await store.setFetchFault(FakeStoreError())
        var paused = false
        let queue = QueueActor(
            store: store,
            isPaused: { paused },
            onSetPaused: { paused = $0 },
            readExtractionSettings: { makeExtractionSettings() },
            providerFactory: { AlwaysFailProvider(error: LLMProviderError.unavailable(reason: "unused")) }
        )

        let events = await queue.subscribe()
        await queue.startProcessing()

        var received: QueueEvent?
        for await event in events {
            received = event; break
        }
        guard case let .queueError(message) = received else {
            return XCTFail("Expected queueError, got \(String(describing: received))")
        }
        XCTAssertTrue(message.contains("Couldn't read the LLM queue"))
    }

    func testEmptyQueueEmitsProcessingComplete() async throws {
        let container = try ModelContainerFactory.inMemory()
        let store = BackgroundStore(modelContainer: container)
        var paused = false
        let queue = QueueActor(
            store: store,
            isPaused: { paused },
            onSetPaused: { paused = $0 },
            readExtractionSettings: { makeExtractionSettings() },
            providerFactory: { AlwaysFailProvider(error: LLMProviderError.unavailable(reason: "unused")) }
        )

        let events = await queue.subscribe()
        await queue.startProcessing()

        var received: QueueEvent?
        for await event in events {
            received = event
            break
        }
        guard case let .processingComplete(processed, failed) = received else {
            return XCTFail("Expected processingComplete, got \(String(describing: received))")
        }
        XCTAssertEqual(processed, 0)
        XCTAssertEqual(failed, 0)
    }

    // TASK-450: cancelling an in-flight request must not count as a provider failure or auto-pause.
    func testCancellingInFlightRequestIsNotCountedAsFailure() async throws {
        let container = try ModelContainerFactory.inMemory()
        let store = BackgroundStore(modelContainer: container)

        // Provider blocks long enough that we can cancel while the request is .running.
        let provider = DelayedSuccessProvider(delay: 1.5, response: "{\"title\":\"X\"}")
        var paused = false
        let queue = QueueActor(
            store: store,
            isPaused: { paused },
            onSetPaused: { paused = $0 },
            readExtractionSettings: { makeExtractionSettings() },
            providerFactory: { provider }
        )

        let capture = Capture(
            url: "https://example.com/job",
            pageTitle: "Job",
            selectedText: "Description.",
            rawHash: "cancel-inflight"
        )
        let job = Job(jobNumber: 1, title: "Job 1")
        job.capture = capture
        try await store.insert(job)

        let events = await queue.subscribe()
        try await queue.enqueue(jobIDs: [job.id], mode: .extract)

        let reqs = try await store.fetch(FetchDescriptor<LLMRequest>())
        let reqID = try XCTUnwrap(reqs.first).id
        // Cancel mid-provider-call.
        try await Task.sleep(nanoseconds: 500_000_000)
        try await queue.cancelRequest(id: reqID)

        for await event in events {
            if case .processingComplete = event { break }
            if case .autoPaused = event { XCTFail("A single cancellation must not auto-pause") }
        }

        let after = try await store.fetch(FetchDescriptor<LLMRequest>(predicate: #Predicate { $0.id == reqID }))
        XCTAssertEqual(after.first?.status, .cancelled)
        XCTAssertFalse(paused, "Cancellation must not trigger auto-pause")
    }

    // MARK: - QueueActor auto-pause

    func testQueueActorAutoPause() async throws {
        let container = try ModelContainerFactory.inMemory()
        let store = BackgroundStore(modelContainer: container)

        let stubError = LLMProviderError.unavailable(reason: "stub failure")
        let failProvider = AlwaysFailProvider(error: stubError)

        var paused = false
        let queue = QueueActor(
            store: store,
            isPaused: { paused },
            onSetPaused: { paused = $0 },
            readExtractionSettings: { makeExtractionSettings() },
            providerFactory: { failProvider }
        )

        // Enough failing jobs to exceed the auto-pause threshold (one per consecutive failure).
        var jobIDs: [String] = []
        for idx in 0 ..< (QueueActor.autoPauseThreshold + 1) {
            let capture = Capture(
                url: "https://example.com/job\(idx)",
                pageTitle: "Job \(idx)",
                selectedText: "Job description for position \(idx).",
                rawHash: "autohash\(idx)"
            )
            let job = Job(jobNumber: idx + 1, title: "Job \(idx + 1)")
            job.capture = capture
            try await store.insert(job)
            jobIDs.append(job.id)
        }

        // Enqueue extraction requests (QueueActor fetches jobs from store and links them)
        try await queue.enqueue(jobIDs: jobIDs, mode: .extract)

        // Run the queue — it should auto-pause after 2 consecutive failures
        await queue.startProcessing()

        // Queue should be paused after consecutive failures
        XCTAssertTrue(
            paused,
            "Queue should auto-pause after \(QueueActor.autoPauseThreshold) consecutive failures"
        )
    }

    // MARK: - Snapshot-based engine API

    func testExtract_usesSnapshot_noCaptureTextThrows() async throws {
        let snapshot = JobExtractionSnapshot(
            captureURL: "https://example.com",
            captureCanonicalURL: nil,
            capturePageTitle: "Test",
            captureCleanedDescription: nil,
            captureVisibleText: nil,
            captureSelectedText: nil
        )
        let provider = AlwaysFailProvider(error: LLMProviderError.unavailable(reason: "should not reach"))
        do {
            _ = try await ExtractionEngine.extract(
                snapshot: snapshot,
                provider: provider,
                settings: makeExtractionSettings()
            )
            XCTFail("Expected noCaptureText error")
        } catch ExtractionEngineError.noCaptureText {
            // expected
        }
    }

    func testExtract_snapshot_callsProviderWithCaptureText() async throws {
        let successJSON = """
        {"title":"Engineer","company":"Acme","location":null,"remote_type":null,
         "salary_min":null,"salary_max":null,"salary_currency":null,"salary_note":null,
         "salary_hourly_min":null,"salary_hourly_max":null,
         "employment_type":null,"seniority":null,"skills":[],"summary":"Great",
         "requirements":[],"nice_to_haves":[],"benefits":[],
         "application_url":null,"application_instructions":null,"confidence":null}
        """
        let snapshot = JobExtractionSnapshot(
            captureURL: "https://example.com/job",
            captureCanonicalURL: nil,
            capturePageTitle: "Engineer",
            captureCleanedDescription: "We are looking for an engineer.",
            captureVisibleText: nil,
            captureSelectedText: nil
        )
        let provider = CountingProvider(succeedOnAttempt: 1, successResponse: successJSON)
        let result = try await ExtractionEngine.extract(
            snapshot: snapshot,
            provider: provider,
            settings: makeExtractionSettings()
        )
        XCTAssertEqual(result.title, "Engineer")
    }

    // MARK: - TASK-154: scoreFit merged JSON retains explanation fields

    func testScoreFit_mergedJSON_retainsExplanationFields() async throws {
        let fitResponseJSON = """
        {
          "overall": 80,
          "summary": "Strong iOS background.",
          "requirements_met": ["Swift", "UIKit"],
          "requirements_not_met": ["FPGA"],
          "dimensions": [
            {"name": "required_qualifications", "score": 85, "weight": 0.45, "rationale": "Meets core req"},
            {"name": "skills", "score": 80, "weight": 0.15, "rationale": "Good skill match"},
            {"name": "preferred_qualifications", "score": 60, "weight": 0.05, "rationale": "Partial"},
            {"name": "experience_level", "score": 90, "weight": 0.20, "rationale": "Senior"},
            {"name": "domain_fit", "score": 70, "weight": 0.15, "rationale": "Adjacent"}
          ]
        }
        """
        let capturing = CapturingProvider(response: fitResponseJSON)
        let jobSnap = JobFitSnapshot(
            title: "iOS Dev",
            company: "Acme",
            seniority: nil,
            extractedJSON: nil,
            extractionModel: nil
        )
        let resumeSnap = ResumeSnapshot(text: "Swift UIKit developer")

        let output = try await ExtractionEngine.scoreFit(
            job: jobSnap,
            resume: resumeSnap,
            model: "gpt-4o",
            provider: capturing
        )

        XCTAssertNotNil(output.fitScoreJSON)
        guard let jsonStr = output.fitScoreJSON,
              let data = jsonStr.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            XCTFail("fitScoreJSON must be valid JSON")
            return
        }

        // Explanation fields from LLM must be preserved
        XCTAssertEqual(dict["summary"] as? String, "Strong iOS background.")
        let requirementsMet = dict["requirements_met"] as? [String]
        XCTAssertEqual(requirementsMet, ["Swift", "UIKit"])
        let requirementsNotMet = dict["requirements_not_met"] as? [String]
        XCTAssertEqual(requirementsNotMet?.first, "FPGA")
        let dimensions = dict["dimensions"] as? [[String: Any]]
        XCTAssertEqual(dimensions?.count, 5)
        XCTAssertEqual(dimensions?.first?["rationale"] as? String, "Meets core req")

        // Computed fields must also be present
        XCTAssertNotNil(dict["overall"])
        XCTAssertNotNil(dict["breakdown"])
        XCTAssertNotNil(dict["penalty"])
    }

    // MARK: - TASK-153: scoreFit uses the passed model, not job.extractionModel

    func testScoreFit_usesPassedModel() async throws {
        let fitResponseJSON = """
        {"overall":75,"dimensions":[{"name":"required_qualifications","score":75,"rationale":"ok"},
         {"name":"preferred_qualifications","score":60,"rationale":"ok"},{"name":"skills","score":70,"rationale":"ok"},
         {"name":"experience_level","score":80,"rationale":"ok"},{"name":"domain_fit","score":50,"rationale":"ok"}],
         "requirements_not_met":[]}
        """
        let capturing = CapturingProvider(response: fitResponseJSON)
        let jobSnap = JobFitSnapshot(
            title: "iOS Dev",
            company: "Acme",
            seniority: nil,
            extractedJSON: nil,
            extractionModel: "old-extraction-model"
        )
        let resumeSnap = ResumeSnapshot(text: "Swift iOS developer with 5 years experience")

        let output = try await ExtractionEngine.scoreFit(
            job: jobSnap,
            resume: resumeSnap,
            model: "configured-fit-model",
            provider: capturing
        )

        XCTAssertEqual(
            capturing.lastRequestedModel,
            "configured-fit-model",
            "scoreFit must use the model parameter, not job.extractionModel"
        )
        XCTAssertNotNil(output.fitScoreJSON, "scoreFit must return merged JSON")
    }

    // MARK: - TASK-266: ChatRequest includes responseFormat

    func testExtract_chatRequest_hasResponseFormat() async throws {
        let successJSON = """
        {"title":"Engineer","company":"Acme","location":null,"remote_type":null,
         "salary_min":null,"salary_max":null,"salary_currency":null,"salary_note":null,
         "salary_hourly_min":null,"salary_hourly_max":null,
         "employment_type":null,"seniority":null,"skills":[],"summary":"Good",
         "requirements":[],"nice_to_haves":[],"benefits":[],
         "application_url":null,"application_instructions":null,"confidence":null}
        """
        let capturing = CapturingProvider(response: successJSON)
        let snapshot = JobExtractionSnapshot(
            captureURL: "https://example.com/job",
            captureCanonicalURL: nil,
            capturePageTitle: "Engineer",
            captureCleanedDescription: "Build amazing things.",
            captureVisibleText: nil,
            captureSelectedText: nil
        )
        _ = try await ExtractionEngine.extract(
            snapshot: snapshot,
            provider: capturing,
            settings: makeExtractionSettings()
        )
        XCTAssertNotNil(
            capturing.lastRequest?.responseFormat,
            "Extraction ChatRequest must include a non-nil responseFormat"
        )
    }

    func testScoreFit_chatRequest_hasResponseFormat() async throws {
        let fitResponseJSON = """
        {"overall":80,"dimensions":[{"name":"required_qualifications","score":80,"rationale":"ok"},
         {"name":"preferred_qualifications","score":60,"rationale":"ok"},{"name":"skills","score":70,"rationale":"ok"},
         {"name":"experience_level","score":80,"rationale":"ok"},{"name":"domain_fit","score":50,"rationale":"ok"}],
         "requirements_not_met":[]}
        """
        let capturing = CapturingProvider(response: fitResponseJSON)
        let jobSnap = JobFitSnapshot(
            title: "Engineer",
            company: "Acme",
            seniority: nil,
            extractedJSON: nil,
            extractionModel: nil
        )
        let resumeSnap = ResumeSnapshot(text: "Swift developer with 5 years experience")
        _ = try await ExtractionEngine.scoreFit(
            job: jobSnap,
            resume: resumeSnap,
            model: "test-model",
            provider: capturing
        )
        XCTAssertNotNil(
            capturing.lastRequest?.responseFormat,
            "Fit scoring ChatRequest must include a non-nil responseFormat"
        )
    }

    // MARK: - TASK-454: engine outputs surface the actual provider response format

    private func valid5DimFitJSON() -> String {
        """
        {"overall":80,"dimensions":[{"name":"required_qualifications","score":80},
         {"name":"preferred_qualifications","score":60},{"name":"skills","score":70},
         {"name":"experience_level","score":80},{"name":"domain_fit","score":50}],
         "requirements_not_met":[]}
        """
    }

    private func extractionJSON() -> String {
        """
        {"title":"Engineer","company":"Acme","location":null,"remote_type":null,
         "salary_min":null,"salary_max":null,"salary_currency":null,"salary_note":null,
         "salary_hourly_min":null,"salary_hourly_max":null,
         "employment_type":null,"seniority":null,"skills":[],"summary":"Good",
         "requirements":[],"nice_to_haves":[],"benefits":[],
         "application_url":null,"application_instructions":null,"confidence":null}
        """
    }

    private func makeExtractSnapshot() -> JobExtractionSnapshot {
        JobExtractionSnapshot(
            captureURL: "https://example.com/job", captureCanonicalURL: nil,
            capturePageTitle: "Engineer", captureCleanedDescription: "Build amazing things.",
            captureVisibleText: nil, captureSelectedText: nil
        )
    }

    func testExtract_outputReflectsProviderJSONObjectFormat() async throws {
        let provider = CapturingProvider(response: extractionJSON(), usedFormat: .jsonObject)
        let result = try await ExtractionEngine.extract(
            snapshot: makeExtractSnapshot(), provider: provider, settings: makeExtractionSettings()
        )
        XCTAssertEqual(result.responseFormat, .jsonObject)
        XCTAssertEqual(result.responseFormat.wireValue, "json_object")
    }

    func testExtract_outputReflectsProviderTextDowngrade() async throws {
        // Provider downgraded to free text even though JSON was requested — attempt history must show it.
        let provider = CapturingProvider(response: extractionJSON(), usedFormat: .text)
        let result = try await ExtractionEngine.extract(
            snapshot: makeExtractSnapshot(), provider: provider, settings: makeExtractionSettings()
        )
        XCTAssertEqual(result.responseFormat, .text)
        XCTAssertEqual(result.responseFormat.wireValue, "text")
    }

    func testScoreFit_outputReflectsProviderJSONObjectFormat() async throws {
        let provider = CapturingProvider(response: valid5DimFitJSON(), usedFormat: .jsonObject)
        let jobSnap = JobFitSnapshot(
            title: "Engineer",
            company: "Acme",
            seniority: nil,
            extractedJSON: nil,
            extractionModel: nil
        )
        let resumeSnap = ResumeSnapshot(text: "Swift developer with 5 years experience")
        let output = try await ExtractionEngine.scoreFit(
            job: jobSnap,
            resume: resumeSnap,
            model: "m",
            provider: provider
        )
        XCTAssertEqual(output.responseFormat, .jsonObject)
        XCTAssertEqual(output.responseFormat.wireValue, "json_object")
    }

    func testScoreFit_outputReflectsAlwaysTextProvider() async throws {
        let provider = CapturingProvider(response: valid5DimFitJSON(), usedFormat: .text)
        let jobSnap = JobFitSnapshot(
            title: "Engineer",
            company: "Acme",
            seniority: nil,
            extractedJSON: nil,
            extractionModel: nil
        )
        let resumeSnap = ResumeSnapshot(text: "Swift developer with 5 years experience")
        let output = try await ExtractionEngine.scoreFit(
            job: jobSnap,
            resume: resumeSnap,
            model: "m",
            provider: provider
        )
        XCTAssertEqual(output.responseFormat, .text)
        XCTAssertEqual(output.responseFormat.wireValue, "text")
    }

    func testExtract_computesMeetsCriteria_fromSettings() async throws {
        // TASK-464: an onsite job with onsite disallowed → meets_criteria false.
        let json = """
        {"title":"Eng","company":"Acme","location":"Austin, TX","remote_type":"onsite",
         "salary_min":null,"salary_max":null,"salary_currency":null,"salary_note":null,
         "salary_hourly_min":null,"salary_hourly_max":null,"employment_type":null,"seniority":null,
         "skills":[],"summary":"x","requirements":[],"nice_to_haves":[],"benefits":[],
         "application_url":null,"application_instructions":null,"confidence":null}
        """
        let provider = CapturingProvider(response: json, usedFormat: .jsonObject)
        let settings = ExtractionSettings(
            llmModel: "m", preferredLocations: "", locationFilterEnabled: true,
            locationAllowRemote: true, locationAllowHybrid: true, locationAllowOnsite: false
        )
        let result = try await ExtractionEngine.extract(
            snapshot: makeExtractSnapshot(), provider: provider, settings: settings
        )
        XCTAssertFalse(result.meetsCriteria, "onsite job must fail when onsite is disallowed")

        // Filter disabled → always meets.
        let settings2 = ExtractionSettings(
            llmModel: "m", preferredLocations: "", locationFilterEnabled: false,
            locationAllowRemote: true, locationAllowHybrid: true, locationAllowOnsite: true
        )
        let result2 = try await ExtractionEngine.extract(
            snapshot: makeExtractSnapshot(), provider: CapturingProvider(response: json, usedFormat: .jsonObject),
            settings: settings2
        )
        XCTAssertTrue(result2.meetsCriteria)
    }

    func testExtract_malformedFieldShape_throws() async throws {
        // TASK-456: a salary field with an incompatible shape fails the extraction (retryable)
        // instead of silently dropping the value.
        let badJSON = """
        {"title":"Engineer","company":"Acme","salary_min":{"nested":1},"skills":[]}
        """
        let provider = CapturingProvider(response: badJSON, usedFormat: .jsonObject)
        do {
            _ = try await ExtractionEngine.extract(
                snapshot: makeExtractSnapshot(), provider: provider, settings: makeExtractionSettings()
            )
            XCTFail("Expected malformedField error")
        } catch let ExtractionEngineError.malformedField(field, _) {
            XCTAssertEqual(field, "salary_min")
        }
    }

    func testExtract_normalizationStillRunsAfterTypedDecode() async throws {
        // TASK-456 AC#4: remote-type inference (a normalization pass) still runs on the rebuilt dict.
        let json = """
        {"title":"Engineer","company":"Acme","location":null,"remote_type":null,
         "salary_min":null,"salary_max":null,"salary_currency":null,"salary_note":null,
         "salary_hourly_min":null,"salary_hourly_max":null,"employment_type":null,"seniority":null,
         "skills":[],"summary":"x","requirements":[],"nice_to_haves":[],"benefits":[],
         "application_url":null,"application_instructions":null,"confidence":null}
        """
        let provider = CapturingProvider(response: json, usedFormat: .jsonObject)
        let snapshot = JobExtractionSnapshot(
            captureURL: "https://example.com/job", captureCanonicalURL: nil,
            capturePageTitle: "Engineer", captureCleanedDescription: "Fully Remote position.",
            captureVisibleText: nil, captureSelectedText: nil
        )
        let result = try await ExtractionEngine.extract(
            snapshot: snapshot, provider: provider, settings: makeExtractionSettings()
        )
        XCTAssertEqual(result.remoteType, .remote, "RemoteTypeInferer must still infer remote from source text")
    }

    func testScoreFit_snapshot_emptyResumeThrows() async throws {
        let jobSnap = JobFitSnapshot(
            title: "Eng",
            company: "Acme",
            seniority: nil,
            extractedJSON: nil,
            extractionModel: nil
        )
        let resumeSnap = ResumeSnapshot(text: "   ")
        let provider = AlwaysFailProvider(error: LLMProviderError.unavailable(reason: "should not reach"))
        do {
            _ = try await ExtractionEngine.scoreFit(
                job: jobSnap,
                resume: resumeSnap,
                model: "test-model",
                provider: provider
            )
            XCTFail("Expected emptyResumeText error")
        } catch ExtractionEngineError.emptyResumeText {
            // expected
        }
    }

    // MARK: - Fit consent check

    func testFitRequest_consentMissing_marksRequestFailed() async throws {
        let container = try ModelContainerFactory.inMemory()
        let store = BackgroundStore(modelContainer: container)
        let failProvider = AlwaysFailProvider(error: LLMProviderError.unavailable(reason: "should not reach"))

        // Cloud provider without consent
        let noConsentSettings = ExtractionSettings(
            llmModel: "gpt-4o",
            llmProvider: "openai",
            llmBaseURL: "https://api.openai.com",
            consentGranted: false,
            preferredLocations: "",
            locationFilterEnabled: false,
            locationAllowRemote: true,
            locationAllowHybrid: true,
            locationAllowOnsite: true
        )
        var paused = false
        let queue = QueueActor(
            store: store,
            isPaused: { paused },
            onSetPaused: { paused = $0 },
            readExtractionSettings: { noConsentSettings },
            providerFactory: { failProvider }
        )

        let capture = Capture(url: "https://example.com/job", pageTitle: "Engineer", rawHash: "h1")
        let job = Job(jobNumber: 1, title: "Engineer")
        job.capture = capture
        job.extractedJSON = "{\"title\":\"Engineer\"}"
        let resume = Resume(
            name: "My Resume",
            text: "Swift developer with 5 years experience.",
            charCount: 40,
            active: true,
            sortOrder: 0
        )
        try await store.insert(job)
        try await store.insert(resume)

        try await queue.enqueueFit(jobIDs: [job.id], resumeID: resume.id)
        await queue.startProcessing()

        let requests = try await store.fetch(FetchDescriptor<LLMRequest>())
        let req = try XCTUnwrap(requests.first)
        XCTAssertEqual(req.status, .failed, "Fit request without consent must be marked failed")
    }

    func testFitRequest_consentGranted_succeeds() async throws {
        let container = try ModelContainerFactory.inMemory()
        let store = BackgroundStore(modelContainer: container)

        let fitJSON = """
        {"overall":80,"dimensions":[{"name":"required_qualifications","score":80,"evidence":"Good match"},{"name":"preferred_qualifications","score":60,"evidence":"ok"},{"name":"skills","score":70,"evidence":"ok"},{"name":"experience_level","score":80,"evidence":"ok"},{"name":"domain_fit","score":50,"evidence":"ok"}],
         "requirements_not_met":[],"summary":"Strong match"}
        """
        let capturingProvider = CapturingProvider(response: fitJSON)

        // Cloud provider with consent granted
        let consentedSettings = ExtractionSettings(
            llmModel: "gpt-4o",
            llmProvider: "openai",
            llmBaseURL: "https://api.openai.com",
            consentGranted: true,
            preferredLocations: "",
            locationFilterEnabled: false,
            locationAllowRemote: true,
            locationAllowHybrid: true,
            locationAllowOnsite: true
        )
        var paused = false
        let queue = QueueActor(
            store: store,
            isPaused: { paused },
            onSetPaused: { paused = $0 },
            readExtractionSettings: { consentedSettings },
            providerFactory: { capturingProvider }
        )

        let capture = Capture(url: "https://example.com/job", pageTitle: "Engineer", rawHash: "h2")
        let job = Job(jobNumber: 2, title: "Engineer")
        job.capture = capture
        job.extractedJSON = "{\"title\":\"Engineer\"}"
        let resume = Resume(
            name: "My Resume",
            text: "Swift developer with 5 years experience.",
            charCount: 40,
            active: true,
            sortOrder: 0
        )
        try await store.insert(job)
        try await store.insert(resume)

        try await queue.enqueueFit(jobIDs: [job.id], resumeID: resume.id)
        await queue.startProcessing()

        let requests = try await store.fetch(FetchDescriptor<LLMRequest>())
        let req = try XCTUnwrap(requests.first)
        XCTAssertEqual(req.status, .succeeded, "Fit request with consent granted must succeed")
    }

    func testEnqueueFit_drainsWithoutExplicitStartProcessing() async throws {
        // Regression for TASK-465: enqueueFit must kick the drain loop itself (like enqueue).
        // The only production caller — the "Score against resume" button — does not call
        // startProcessing, so without the self-kick the request sits .queued indefinitely.
        let container = try ModelContainerFactory.inMemory()
        let store = BackgroundStore(modelContainer: container)

        let fitJSON = """
        {"overall":80,"dimensions":[{"name":"required_qualifications","score":80,"evidence":"Good match"},{"name":"preferred_qualifications","score":60,"evidence":"ok"},{"name":"skills","score":70,"evidence":"ok"},{"name":"experience_level","score":80,"evidence":"ok"},{"name":"domain_fit","score":50,"evidence":"ok"}],
         "requirements_not_met":[],"summary":"Strong match"}
        """
        let capturingProvider = CapturingProvider(response: fitJSON)

        let consentedSettings = ExtractionSettings(
            llmModel: "gpt-4o",
            llmProvider: "openai",
            llmBaseURL: "https://api.openai.com",
            consentGranted: true,
            preferredLocations: "",
            locationFilterEnabled: false,
            locationAllowRemote: true,
            locationAllowHybrid: true,
            locationAllowOnsite: true
        )
        var paused = false
        let queue = QueueActor(
            store: store,
            isPaused: { paused },
            onSetPaused: { paused = $0 },
            readExtractionSettings: { consentedSettings },
            providerFactory: { capturingProvider }
        )

        let capture = Capture(url: "https://example.com/job", pageTitle: "Engineer", rawHash: "h-fit-drain")
        let job = Job(jobNumber: 3, title: "Engineer")
        job.capture = capture
        job.extractedJSON = "{\"title\":\"Engineer\"}"
        let resume = Resume(
            name: "My Resume",
            text: "Swift developer with 5 years experience.",
            charCount: 40,
            active: true,
            sortOrder: 0
        )
        try await store.insert(job)
        try await store.insert(resume)

        // No explicit startProcessing — enqueueFit alone must drain the queue.
        try await queue.enqueueFit(jobIDs: [job.id], resumeID: resume.id)

        // The drain runs on a detached Task; poll until the request reaches a terminal state.
        var settled = false
        for _ in 0 ..< 100 {
            let requests = try await store.fetch(FetchDescriptor<LLMRequest>())
            if let status = requests.first?.status, status == .succeeded || status == .failed {
                XCTAssertEqual(status, .succeeded, "Fit request should succeed once drained")
                settled = true
                break
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertTrue(settled, "enqueueFit must drain the queue without an explicit startProcessing call")
    }

    func testFitRequest_loopbackProvider_noConsentNeeded() async throws {
        let container = try ModelContainerFactory.inMemory()
        let store = BackgroundStore(modelContainer: container)

        let fitJSON = """
        {"overall":75,"dimensions":[{"name":"required_qualifications","score":75,"evidence":"Match"},{"name":"preferred_qualifications","score":60,"evidence":"ok"},{"name":"skills","score":70,"evidence":"ok"},{"name":"experience_level","score":80,"evidence":"ok"},{"name":"domain_fit","score":50,"evidence":"ok"}],
         "requirements_not_met":[],"summary":"OK match"}
        """
        let capturingProvider = CapturingProvider(response: fitJSON)

        // Local provider — consentGranted=false doesn't matter for loopback
        let localSettings = ExtractionSettings(
            llmModel: "local-model",
            llmProvider: "custom",
            llmBaseURL: "http://127.0.0.1:1234",
            consentGranted: false,
            preferredLocations: "",
            locationFilterEnabled: false,
            locationAllowRemote: true,
            locationAllowHybrid: true,
            locationAllowOnsite: true
        )
        var paused = false
        let queue = QueueActor(
            store: store,
            isPaused: { paused },
            onSetPaused: { paused = $0 },
            readExtractionSettings: { localSettings },
            providerFactory: { capturingProvider }
        )

        let capture = Capture(url: "https://example.com/job", pageTitle: "Engineer", rawHash: "h3")
        let job = Job(jobNumber: 3, title: "Engineer")
        job.capture = capture
        job.extractedJSON = "{\"title\":\"Engineer\"}"
        let resume = Resume(
            name: "My Resume",
            text: "Swift developer with 5 years experience.",
            charCount: 40,
            active: true,
            sortOrder: 0
        )
        try await store.insert(job)
        try await store.insert(resume)

        try await queue.enqueueFit(jobIDs: [job.id], resumeID: resume.id)
        await queue.startProcessing()

        let requests = try await store.fetch(FetchDescriptor<LLMRequest>())
        let req = try XCTUnwrap(requests.first)
        XCTAssertEqual(req.status, .succeeded, "Fit request to loopback provider must succeed without explicit consent")
    }

    // MARK: - TASK-247: requeueRunningOnLaunch resets stuck running requests

    func testRequeueRunningOnLaunch_resetsRunningRequest() async throws {
        let container = try ModelContainerFactory.inMemory()
        let store = BackgroundStore(modelContainer: container)
        let queue = QueueActor(
            store: store,
            isPaused: { false },
            onSetPaused: { _ in },
            readExtractionSettings: { makeExtractionSettings() },
            providerFactory: { AlwaysFailProvider(error: LLMProviderError.unavailable(reason: "stub")) }
        )

        // Insert a request stuck in .running (simulating a crash mid-run)
        let job = Job(jobNumber: 1, title: "Stuck Job")
        try await store.insert(job)
        let req = LLMRequest(requestType: .extract, status: .running)
        req.job = job
        req.startedAt = Date(timeIntervalSinceNow: -60)
        try await store.insert(req)

        // Verify preconditions
        let before = try await store.fetch(FetchDescriptor<LLMRequest>())
        XCTAssertEqual(before.first?.status, .running)
        XCTAssertNotNil(before.first?.startedAt)

        // Call the method under test
        try await queue.requeueRunningOnLaunch()

        // Verify the request was reset to .queued with startedAt cleared
        let after = try await store.fetch(FetchDescriptor<LLMRequest>())
        let updated = try XCTUnwrap(after.first)
        XCTAssertEqual(updated.status, .queued, "requeueRunningOnLaunch must reset .running to .queued")
        XCTAssertNil(updated.startedAt, "requeueRunningOnLaunch must clear startedAt")
    }

    func testLaunchResume_pausedQueue_leavesRecoveredRequestQueued() async throws {
        // TASK-383: launch auto-resume calls startProcessing(), which must respect the paused
        // setting — a recovered (.queued) request stays queued while paused.
        let container = try ModelContainerFactory.inMemory()
        let store = BackgroundStore(modelContainer: container)
        let queue = QueueActor(
            store: store,
            isPaused: { true },
            onSetPaused: { _ in },
            readExtractionSettings: { makeExtractionSettings() },
            providerFactory: { AlwaysFailProvider(error: LLMProviderError.unavailable(reason: "should not run")) }
        )

        let job = Job(jobNumber: 1, title: "Recovered Job")
        try await store.insert(job)
        let req = LLMRequest(requestType: .extract, status: .queued)
        req.job = job
        try await store.insert(req)

        // Simulate the launch path: recover, then auto-resume.
        try await queue.requeueRunningOnLaunch()
        await queue.startProcessing()

        let after = try await store.fetch(FetchDescriptor<LLMRequest>())
        XCTAssertEqual(after.first?.status, .queued, "paused launch resume must leave recovered work queued")
    }

    // MARK: - TASK-246: Cancellation during in-flight request prevents success overwrite

    func testCancelDuringExecution_requestRemainsCancel() async throws {
        let container = try ModelContainerFactory.inMemory()
        let store = BackgroundStore(modelContainer: container)

        // Provider that delays long enough for us to cancel before it returns
        let delayedProvider = DelayedSuccessProvider(
            delay: 0.05,
            response: """
            {"title":"Eng","company":"Acme","location":null,"remote_type":null,
             "salary_min":null,"salary_max":null,"salary_currency":null,"salary_note":null,
             "salary_hourly_min":null,"salary_hourly_max":null,
             "employment_type":null,"seniority":null,"skills":[],"summary":"ok",
             "requirements":[],"nice_to_haves":[],"benefits":[],
             "application_url":null,"application_instructions":null,"confidence":null}
            """
        )
        var paused = false
        let queue = QueueActor(
            store: store,
            isPaused: { paused },
            onSetPaused: { paused = $0 },
            readExtractionSettings: { makeExtractionSettings() },
            providerFactory: { delayedProvider }
        )

        let capture = Capture(
            url: "https://example.com/job",
            pageTitle: "Engineer",
            selectedText: "Swift engineer role.",
            rawHash: "cancelhash"
        )
        let job = Job(jobNumber: 1, title: "Engineer")
        job.capture = capture
        try await store.insert(job)
        try await queue.enqueue(jobIDs: [job.id], mode: .extract)

        // Start processing and cancel concurrently before provider returns
        async let processing: Void = queue.startProcessing()
        // Give the queue time to mark the request .running, then cancel it
        try await Task.sleep(nanoseconds: 10_000_000) // 10ms
        let requests = try await store.fetch(FetchDescriptor<LLMRequest>())
        if let reqID = requests.first?.id {
            try await queue.cancelRequest(id: reqID)
        }
        await processing

        // The request must end as .cancelled, not .succeeded
        let final = try await store.fetch(FetchDescriptor<LLMRequest>())
        let finalReq = try XCTUnwrap(final.first)
        XCTAssertEqual(
            finalReq.status,
            .cancelled,
            "Cancelling during in-flight execution must leave status as .cancelled"
        )
    }

    // MARK: - TASK-245: Fan-out event stream delivers to multiple subscribers

    func testSubscribe_twoSubscribersReceiveSameEvent() async throws {
        let container = try ModelContainerFactory.inMemory()
        let store = BackgroundStore(modelContainer: container)

        let successJSON = """
        {"title":"Engineer","company":"Acme","location":null,"remote_type":null,
         "salary_min":null,"salary_max":null,"salary_currency":null,"salary_note":null,
         "salary_hourly_min":null,"salary_hourly_max":null,
         "employment_type":null,"seniority":null,"skills":[],"summary":"ok",
         "requirements":[],"nice_to_haves":[],"benefits":[],
         "application_url":null,"application_instructions":null,"confidence":null}
        """
        let capturingProvider = CapturingProvider(response: successJSON)
        var paused = false
        let queue = QueueActor(
            store: store,
            isPaused: { paused },
            onSetPaused: { paused = $0 },
            readExtractionSettings: { makeExtractionSettings() },
            providerFactory: { capturingProvider }
        )

        // Subscribe two independent streams before processing starts
        let stream1 = await queue.subscribe()
        let stream2 = await queue.subscribe()

        var events1: [QueueEvent] = []
        var events2: [QueueEvent] = []

        let capture = Capture(
            url: "https://example.com/fanout-job",
            pageTitle: "Fanout Engineer",
            selectedText: "Swift role for fanout test.",
            rawHash: "fanouthash"
        )
        let job = Job(jobNumber: 1, title: "Fanout Engineer")
        job.capture = capture
        try await store.insert(job)
        try await queue.enqueue(jobIDs: [job.id], mode: .extract)

        // Collect events from both streams while the queue runs
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                await queue.startProcessing()
            }
            group.addTask {
                for await event in stream1 {
                    events1.append(event)
                    if case .processingComplete = event { break }
                }
            }
            group.addTask {
                for await event in stream2 {
                    events2.append(event)
                    if case .processingComplete = event { break }
                }
            }
        }

        XCTAssertFalse(events1.isEmpty, "Subscriber 1 must receive events")
        XCTAssertFalse(events2.isEmpty, "Subscriber 2 must receive events")

        // Both should have seen processingComplete
        let complete1 = events1.contains { if case .processingComplete = $0 { return true }; return false }
        let complete2 = events2.contains { if case .processingComplete = $0 { return true }; return false }
        XCTAssertTrue(complete1, "Subscriber 1 must receive processingComplete")
        XCTAssertTrue(complete2, "Subscriber 2 must receive processingComplete")
    }

    // MARK: - QueueActor retry (attempt tracking)

    func testQueueActorRetryAttemptCount() async throws {
        let container = try ModelContainerFactory.inMemory()
        let store = BackgroundStore(modelContainer: container)

        let successJSON = """
        {
            "title": "Senior Engineer",
            "company": "Acme Corp",
            "location": "Seattle, WA",
            "remote_type": "hybrid",
            "salary_min": 150000,
            "salary_max": 200000,
            "salary_currency": "USD",
            "salary_note": "$150k-200k",
            "salary_hourly_min": null,
            "salary_hourly_max": null,
            "employment_type": "full_time",
            "seniority": "Senior",
            "skills": ["Swift", "iOS"],
            "summary": "Great role",
            "requirements": ["5 years Swift"],
            "nice_to_haves": ["SwiftUI"],
            "benefits": ["401k"],
            "application_url": null,
            "application_instructions": null,
            "confidence": {"title": 0.9, "company": 0.95}
        }
        """

        // Provider succeeds immediately (attempt count test verifies attempt row is written)
        let countingProvider = CountingProvider(succeedOnAttempt: 1, successResponse: successJSON)

        let queue = QueueActor(
            store: store,
            isPaused: { false },
            onSetPaused: { _ in },
            readExtractionSettings: { makeExtractionSettings() },
            providerFactory: { countingProvider }
        )

        let capture = Capture(
            url: "https://example.com/job",
            pageTitle: "Software Engineer",
            selectedText: "Join our team as a Senior Engineer at Acme Corp in Seattle, WA.",
            rawHash: "testhash1"
        )
        let job = Job(jobNumber: 1, title: "Senior Engineer")
        job.capture = capture
        try await store.insert(job)

        try await queue.enqueue(jobIDs: [job.id], mode: .extract)

        await queue.startProcessing()

        // After processing, verify at least one attempt record was written
        let descriptor = FetchDescriptor<LLMRequestAttempt>()
        let attempts = try await store.fetch(descriptor)

        // A successful extraction should write 1 attempt record
        XCTAssertGreaterThanOrEqual(attempts.count, 1)
    }

    // MARK: - TASK-269: Re-extraction overwrites scalar fields with nil when LLM returns nil

    func testReextraction_nilFieldOverwritesOldValue() async throws {
        let container = try ModelContainerFactory.inMemory()
        let store = BackgroundStore(modelContainer: container)

        // Extraction returns company=null (the LLM found no company in the posting)
        let nilCompanyJSON = """
        {"title":"Engineer","company":null,"location":null,"remote_type":null,
         "salary_min":null,"salary_max":null,"salary_currency":null,"salary_note":null,
         "salary_hourly_min":null,"salary_hourly_max":null,
         "employment_type":null,"seniority":null,"skills":[],"summary":"ok",
         "requirements":[],"nice_to_haves":[],"benefits":[],
         "application_url":null,"application_instructions":null,"confidence":null}
        """
        let provider = CapturingProvider(response: nilCompanyJSON)
        var paused = false
        let queue = QueueActor(
            store: store,
            isPaused: { paused },
            onSetPaused: { paused = $0 },
            readExtractionSettings: { makeExtractionSettings() },
            providerFactory: { provider }
        )

        let capture = Capture(
            url: "https://example.com/job",
            pageTitle: "Engineer",
            selectedText: "Looking for an engineer.",
            rawHash: "nilcompanyhash"
        )
        let job = Job(jobNumber: 1, title: "Engineer")
        job.capture = capture
        job.company = "OldCo" // pre-existing value from a prior extraction
        try await store.insert(job)

        try await queue.enqueue(jobIDs: [job.id], mode: .extract)
        await queue.startProcessing()

        let jobs = try await store.fetch(FetchDescriptor<Job>())
        let updated = try XCTUnwrap(jobs.first)
        XCTAssertNil(
            updated.company,
            "Re-extraction returning nil must overwrite the old company value, not preserve it"
        )
    }

    // MARK: - TASK-272: Fit attempt records promptChars and responseChars

    func testFitAttempt_recordsPromptAndResponseChars() async throws {
        let container = try ModelContainerFactory.inMemory()
        let store = BackgroundStore(modelContainer: container)

        let fitJSON = """
        {"overall":80,"dimensions":[{"name":"required_qualifications","score":80,"evidence":"Match"},{"name":"preferred_qualifications","score":60,"evidence":"ok"},{"name":"skills","score":70,"evidence":"ok"},{"name":"experience_level","score":80,"evidence":"ok"},{"name":"domain_fit","score":50,"evidence":"ok"}],
         "requirements_not_met":[],"summary":"Strong match"}
        """
        // TASK-454: the attempt's responseFormat is the provider's actual format, no longer hardcoded.
        let capturingProvider = CapturingProvider(response: fitJSON, usedFormat: .jsonObject)

        let consentedSettings = ExtractionSettings(
            llmModel: "gpt-4o",
            llmProvider: "openai",
            llmBaseURL: "https://api.openai.com",
            consentGranted: true,
            preferredLocations: "",
            locationFilterEnabled: false,
            locationAllowRemote: true,
            locationAllowHybrid: true,
            locationAllowOnsite: true
        )
        var paused = false
        let queue = QueueActor(
            store: store,
            isPaused: { paused },
            onSetPaused: { paused = $0 },
            readExtractionSettings: { consentedSettings },
            providerFactory: { capturingProvider }
        )

        let capture = Capture(url: "https://example.com/job", pageTitle: "Engineer", rawHash: "fitcharshash")
        let job = Job(jobNumber: 1, title: "Engineer")
        job.capture = capture
        job.extractedJSON = "{\"title\":\"Engineer\"}"
        let resume = Resume(
            name: "My Resume",
            text: "Swift developer with 5 years experience.",
            charCount: 40,
            active: true,
            sortOrder: 0
        )
        try await store.insert(job)
        try await store.insert(resume)

        try await queue.enqueueFit(jobIDs: [job.id], resumeID: resume.id)
        await queue.startProcessing()

        let attempts = try await store.fetch(FetchDescriptor<LLMRequestAttempt>())
        let fitAttempt = try XCTUnwrap(attempts.first { $0.requestType == .fit && $0.status == .succeeded })
        XCTAssertNotNil(fitAttempt.promptChars, "Successful fit attempt must record promptChars")
        XCTAssertNotNil(fitAttempt.responseChars, "Successful fit attempt must record responseChars")
        XCTAssertGreaterThan(fitAttempt.promptChars ?? 0, 0, "promptChars must be positive")
        XCTAssertGreaterThan(fitAttempt.responseChars ?? 0, 0, "responseChars must be positive")
        XCTAssertEqual(fitAttempt.responseFormat, "json_object", "Fit attempt must record responseFormat")
    }

    // MARK: - TASK-270: Disallowed remoteType is cleared post-extraction

    func testExtract_remoteDisallowed_clearsRemoteType() async throws {
        // LLM returns remote, but remote is disallowed → remoteType must be nil
        let remoteJSON = """
        {"title":"Remote Engineer","company":"Acme","location":"Remote","remote_type":"remote",
         "salary_min":null,"salary_max":null,"salary_currency":null,"salary_note":null,
         "salary_hourly_min":null,"salary_hourly_max":null,
         "employment_type":null,"seniority":null,"skills":[],"summary":"ok",
         "requirements":[],"nice_to_haves":[],"benefits":[],
         "application_url":null,"application_instructions":null,"confidence":null}
        """
        let provider = CapturingProvider(response: remoteJSON)
        let settings = ExtractionSettings(
            llmModel: "stub",
            preferredLocations: "",
            locationFilterEnabled: true,
            locationAllowRemote: false,
            locationAllowHybrid: true,
            locationAllowOnsite: true
        )
        let snapshot = JobExtractionSnapshot(
            captureURL: "https://example.com/job",
            captureCanonicalURL: nil,
            capturePageTitle: "Remote Engineer",
            captureCleanedDescription: "Fully remote role.",
            captureVisibleText: nil,
            captureSelectedText: nil
        )
        let result = try await ExtractionEngine.extract(snapshot: snapshot, provider: provider, settings: settings)
        XCTAssertNil(result.remoteType, "remoteType must be nil when remote is disallowed")
    }

    func testExtract_hybridDisallowed_clearsRemoteType() async throws {
        // LLM returns hybrid, only onsite is allowed → remoteType must be nil
        let hybridJSON = """
        {"title":"Hybrid Engineer","company":"Acme","location":"Seattle, WA","remote_type":"hybrid",
         "salary_min":null,"salary_max":null,"salary_currency":null,"salary_note":null,
         "salary_hourly_min":null,"salary_hourly_max":null,
         "employment_type":null,"seniority":null,"skills":[],"summary":"ok",
         "requirements":[],"nice_to_haves":[],"benefits":[],
         "application_url":null,"application_instructions":null,"confidence":null}
        """
        let provider = CapturingProvider(response: hybridJSON)
        let settings = ExtractionSettings(
            llmModel: "stub",
            preferredLocations: "",
            locationFilterEnabled: true,
            locationAllowRemote: false,
            locationAllowHybrid: false,
            locationAllowOnsite: true
        )
        let snapshot = JobExtractionSnapshot(
            captureURL: "https://example.com/job",
            captureCanonicalURL: nil,
            capturePageTitle: "Hybrid Engineer",
            captureCleanedDescription: "3 days per week in office.",
            captureVisibleText: nil,
            captureSelectedText: nil
        )
        let result = try await ExtractionEngine.extract(snapshot: snapshot, provider: provider, settings: settings)
        XCTAssertNil(result.remoteType, "remoteType must be nil when hybrid is disallowed")
    }

    func testExtract_remoteAllowed_preservesRemoteType() async throws {
        // LLM returns remote and remote is allowed → remoteType must be preserved
        let remoteJSON = """
        {"title":"Remote Engineer","company":"Acme","location":"Remote","remote_type":"remote",
         "salary_min":null,"salary_max":null,"salary_currency":null,"salary_note":null,
         "salary_hourly_min":null,"salary_hourly_max":null,
         "employment_type":null,"seniority":null,"skills":[],"summary":"ok",
         "requirements":[],"nice_to_haves":[],"benefits":[],
         "application_url":null,"application_instructions":null,"confidence":null}
        """
        let provider = CapturingProvider(response: remoteJSON)
        let settings = ExtractionSettings(
            llmModel: "stub",
            preferredLocations: "",
            locationFilterEnabled: true,
            locationAllowRemote: true,
            locationAllowHybrid: false,
            locationAllowOnsite: false
        )
        let snapshot = JobExtractionSnapshot(
            captureURL: "https://example.com/job",
            captureCanonicalURL: nil,
            capturePageTitle: "Remote Engineer",
            captureCleanedDescription: "Fully remote role.",
            captureVisibleText: nil,
            captureSelectedText: nil
        )
        let result = try await ExtractionEngine.extract(snapshot: snapshot, provider: provider, settings: settings)
        XCTAssertEqual(result.remoteType, .remote, "remoteType must be preserved when remote is allowed")
    }

    // MARK: - TASK-271: Hourly salary fields survive into ExtractionResult

    func testExtract_hourlySalary_populatesHourlyFields() async throws {
        // LLM returns hourly salary values → hourlyMin/Max must be non-nil in ExtractionResult
        let hourlyJSON = """
        {"title":"Contractor","company":"Acme","location":null,"remote_type":null,
         "salary_min":null,"salary_max":null,"salary_currency":"USD",
         "salary_note":"$85/hr - $105/hr on W2 contract.",
         "salary_hourly_min":null,"salary_hourly_max":null,
         "employment_type":"contract","seniority":null,"skills":[],"summary":"ok",
         "requirements":[],"nice_to_haves":[],"benefits":[],
         "application_url":null,"application_instructions":null,"confidence":null}
        """
        let provider = CapturingProvider(response: hourlyJSON)
        let snapshot = JobExtractionSnapshot(
            captureURL: "https://example.com/job",
            captureCanonicalURL: nil,
            capturePageTitle: "Contractor",
            captureCleanedDescription: "Pay: $85/hr - $105/hr on W2 contract.",
            captureVisibleText: nil,
            captureSelectedText: nil
        )
        let result = try await ExtractionEngine.extract(
            snapshot: snapshot,
            provider: provider,
            settings: makeExtractionSettings()
        )
        XCTAssertNotNil(result.salaryHourlyMin, "hourlyMin must be non-nil for hourly salary postings")
        XCTAssertNotNil(result.salaryHourlyMax, "hourlyMax must be non-nil for hourly salary postings")
        XCTAssertEqual(result.salaryHourlyMin, 85.0)
        XCTAssertEqual(result.salaryHourlyMax, 105.0)
        // Annual salary must also be set (converted at 2080 hrs/yr)
        XCTAssertEqual(result.salaryMin, 176_800)
        XCTAssertEqual(result.salaryMax, 218_400)
    }

    func testExtract_annualSalary_hourlyFieldsNil() async throws {
        // LLM returns annual salary (no hourly) → hourlyMin/Max must be nil
        let annualJSON = """
        {"title":"Engineer","company":"Acme","location":null,"remote_type":null,
         "salary_min":150000,"salary_max":200000,"salary_currency":"USD",
         "salary_note":"$150,000 - $200,000 USD annually",
         "salary_hourly_min":null,"salary_hourly_max":null,
         "employment_type":"full_time","seniority":null,"skills":[],"summary":"ok",
         "requirements":[],"nice_to_haves":[],"benefits":[],
         "application_url":null,"application_instructions":null,"confidence":null}
        """
        let provider = CapturingProvider(response: annualJSON)
        let snapshot = JobExtractionSnapshot(
            captureURL: "https://example.com/job",
            captureCanonicalURL: nil,
            capturePageTitle: "Engineer",
            captureCleanedDescription: "Salary: $150,000 - $200,000 USD annually.",
            captureVisibleText: nil,
            captureSelectedText: nil
        )
        let result = try await ExtractionEngine.extract(
            snapshot: snapshot,
            provider: provider,
            settings: makeExtractionSettings()
        )
        XCTAssertNil(result.salaryHourlyMin, "hourlyMin must be nil for annual salary postings")
        XCTAssertNil(result.salaryHourlyMax, "hourlyMax must be nil for annual salary postings")
        XCTAssertNotNil(result.salaryMin)
        XCTAssertNotNil(result.salaryMax)
    }

    // MARK: - Queue starvation regression

    /// Verifies that a large number of terminal (finished) rows older than the queued item
    /// do not prevent the queued item from being fetched and processed.
    func testQueueActor_terminalRowsDoNotStarveQueuedItems() async throws {
        let container = try ModelContainerFactory.inMemory()
        let store = BackgroundStore(modelContainer: container)

        let successJSON = """
        {"title":"Engineer","company":"Acme","location":null,"remote_type":null,
         "salary_min":null,"salary_max":null,"salary_currency":null,"salary_note":null,
         "salary_hourly_min":null,"salary_hourly_max":null,
         "employment_type":null,"seniority":null,"skills":[],"summary":"Good",
         "requirements":[],"nice_to_haves":[],"benefits":[],
         "application_url":null,"application_instructions":null,"confidence":null}
        """
        let capturingProvider = CapturingProvider(response: successJSON)
        var paused = false
        let queue = QueueActor(
            store: store,
            isPaused: { paused },
            onSetPaused: { paused = $0 },
            readExtractionSettings: { makeExtractionSettings() },
            providerFactory: { capturingProvider }
        )

        // Insert 50 terminal (retryExhausted) LLMRequest rows with early creation dates
        // to simulate a scenario where many old finished rows exist before the queued item.
        let earlyDate = Date(timeIntervalSinceNow: -3600)
        for idx in 0 ..< 50 {
            let oldCapture = Capture(
                url: "https://old.example.com/job\(idx)",
                pageTitle: "Old Job \(idx)",
                rawHash: "oldhash\(idx)"
            )
            let oldJob = Job(jobNumber: 1000 + idx, title: "Old Job \(idx)")
            oldJob.capture = oldCapture
            try await store.insert(oldJob)

            let termReq = LLMRequest(requestType: .extract, status: .retryExhausted)
            termReq.job = oldJob
            termReq.finishedAt = earlyDate
            try await store.insert(termReq)
        }

        // Now insert the one queued job that must not be starved
        let liveCapture = Capture(
            url: "https://example.com/live-job",
            pageTitle: "Live Engineer",
            selectedText: "We need a Swift engineer.",
            rawHash: "livehash"
        )
        let liveJob = Job(jobNumber: 9999, title: "Live Engineer")
        liveJob.capture = liveCapture
        try await store.insert(liveJob)
        try await queue.enqueue(jobIDs: [liveJob.id], mode: .extract)

        await queue.startProcessing()

        // The live job's LLMRequest must have been processed successfully.
        let all = try await store.fetch(FetchDescriptor<LLMRequest>())
        let liveReqs = all.filter { $0.job?.jobNumber == 9999 }
        XCTAssertEqual(liveReqs.count, 1, "Live job must have exactly one LLMRequest")
        XCTAssertEqual(
            liveReqs.first?.status,
            .succeeded,
            "Live job must be processed despite 50 older terminal rows"
        )
    }
}
