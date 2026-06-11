import SwiftData
import XCTest
@testable import JobhuntCore

// MARK: - Stub providers for testing

/// A provider that always fails with a given error.
private struct AlwaysFailProvider: LLMProvider {
    let id: String = "always-fail"
    let concurrencyLimit: Int = 1
    let error: Error

    func complete(_: ChatRequest) async throws -> ChatResponse {
        throw error
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

    // MARK: - QueueActor auto-pause

    func testQueueActorAutoPause() async throws {
        let container = try ModelContainerFactory.inMemory()
        let store = BackgroundStore(modelContainer: container)
        let context = ModelContext(container)
        let settings = SettingsStore(modelContext: context)

        let stubError = LLMProviderError.unavailable(reason: "stub failure")
        let failProvider = AlwaysFailProvider(error: stubError)

        let queue = QueueActor(
            store: store,
            settings: settings,
            providerFactory: { failProvider }
        )

        // Create 3 jobs with captures and enqueue extraction requests
        var jobIDs: [String] = []
        for idx in 0 ..< 3 {
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
            settings.llmQueuePaused,
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
            _ = try await ExtractionEngine.extract(snapshot: snapshot, provider: provider, settings: makeSettings())
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
        let result = try await ExtractionEngine.extract(snapshot: snapshot, provider: provider, settings: makeSettings())
        XCTAssertEqual(result.title, "Engineer")
    }

    func testScoreFit_snapshot_emptyResumeThrows() async throws {
        let jobSnap = JobFitSnapshot(title: "Eng", company: "Acme", seniority: nil, extractedJSON: nil, extractionModel: nil)
        let resumeSnap = ResumeSnapshot(text: "   ")
        let provider = AlwaysFailProvider(error: LLMProviderError.unavailable(reason: "should not reach"))
        do {
            _ = try await ExtractionEngine.scoreFit(job: jobSnap, resume: resumeSnap, provider: provider)
            XCTFail("Expected emptyResumeText error")
        } catch ExtractionEngineError.emptyResumeText {
            // expected
        }
    }

    private func makeSettings() throws -> SettingsStore {
        let container = try ModelContainerFactory.inMemory()
        let ctx = ModelContext(container)
        return SettingsStore(modelContext: ctx)
    }

    // MARK: - QueueActor retry (attempt tracking)

    func testQueueActorRetryAttemptCount() async throws {
        let container = try ModelContainerFactory.inMemory()
        let store = BackgroundStore(modelContainer: container)
        let context = ModelContext(container)
        let settings = SettingsStore(modelContext: context)

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
            settings: settings,
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
}
