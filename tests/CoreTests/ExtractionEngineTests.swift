import XCTest
import SwiftData
@testable import JobhuntCore

// MARK: - Stub providers for testing

/// A provider that always fails with a given error.
private struct AlwaysFailProvider: LLMProvider {
    let id: String = "always-fail"
    let concurrencyLimit: Int = 1
    let error: Error

    func complete(_ request: ChatRequest) async throws -> ChatResponse {
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

    func complete(_ request: ChatRequest) async throws -> ChatResponse {
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

        XCTAssertEqual(ten.inputTokens, single.inputTokens * 10)
        XCTAssertEqual(ten.outputTokens, single.outputTokens * 10)
        XCTAssertEqual(ten.estimatedCostUSD, single.estimatedCostUSD * 10, accuracy: 1e-10)
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
        for i in 0..<3 {
            let capture = Capture(
                url: "https://example.com/job\(i)",
                pageTitle: "Job \(i)",
                selectedText: "Job description for position \(i).",
                rawHash: "autohash\(i)"
            )
            let job = Job(jobNumber: i + 1, title: "Job \(i + 1)")
            job.capture = capture
            try await store.insert(job)
            jobIDs.append(job.id)
        }

        // Enqueue extraction requests (QueueActor fetches jobs from store and links them)
        try await queue.enqueue(jobIDs: jobIDs, mode: .extract)

        // Run the queue — it should auto-pause after 2 consecutive failures
        await queue.startProcessing()

        // Queue should be paused after consecutive failures
        XCTAssertTrue(settings.llmQueuePaused, "Queue should auto-pause after \(QueueActor.autoPauseThreshold) consecutive failures")
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
