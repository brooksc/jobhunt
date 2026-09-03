import SwiftData
import XCTest
@testable import JobhuntCore

/// End-to-end inference-path coverage: a real OpenAI-compatible provider talks to the localhost
/// `MockLLMServer` over a TCP socket, and the engine parses the canned-but-input-aware responses.
/// Proves the provider → OpenAICompatibleTransport → ExtractionEngine path works with no API key.
final class MockLLMInferenceTests: XCTestCase {
    private var server: MockLLMServer!

    override func setUpWithError() throws {
        server = try MockLLMServer()
        try server.start()
    }

    override func tearDown() {
        server.stop()
        server = nil
        super.tearDown()
    }

    private func mockProvider() -> LMStudioProvider {
        // LM Studio is OpenAI-compatible, needs no key/consent — point it at the mock.
        LMStudioProvider(baseURL: server.baseURL, model: "mock-model")
    }

    private func settings() -> ExtractionSettings {
        ExtractionSettings(
            llmModel: "mock-model",
            preferredLocations: "",
            locationFilterEnabled: false,
            locationAllowRemote: true,
            locationAllowHybrid: true,
            locationAllowOnsite: true
        )
    }

    func testExtraction_overLocalhostMock_echoesCapturedTitle() async throws {
        let snapshot = JobExtractionSnapshot(
            captureURL: "https://example.com/job",
            captureCanonicalURL: nil,
            capturePageTitle: "Senior iOS Engineer - Acme",
            captureCleanedDescription: "We are hiring an iOS engineer to build delightful apps.",
            captureVisibleText: nil,
            captureSelectedText: nil
        )

        let result = try await ExtractionEngine.extract(
            snapshot: snapshot, provider: mockProvider(), settings: settings()
        )

        // Input-aware: the mock echoed the page title it saw in the prompt.
        XCTAssertEqual(result.title, "Senior iOS Engineer")
        XCTAssertEqual(result.company, "Acme")
        XCTAssertEqual(result.remoteType, .remote)
        XCTAssertEqual(result.salaryMin, 150_000)
    }

    func testFitScoring_overLocalhostMock_parsesDimensions() async throws {
        let job = JobFitSnapshot(
            title: "iOS Engineer", company: "Acme",
            seniority: "senior", extractedJSON: nil, extractionModel: nil
        )
        let resume = ResumeSnapshot(text: "Swift / SwiftUI iOS developer with 6 years of experience.")

        let output = try await ExtractionEngine.scoreFit(
            job: job, resume: resume, model: "mock-model", provider: mockProvider(), feedback: [],
            otherResumeTexts: []
        )

        XCTAssertGreaterThan(output.score.overall, 0, "fit should parse to a real score")
        // All five required dimensions came back and validated.
        XCTAssertEqual(output.score.scoreWeights.count, 5)
    }

    /// The full app processing pipeline: QueueActor drains a queued extraction request, calls the
    /// real provider against the mock server, and writes the parsed result back to the Job in the
    /// store. Deterministic (waits for processingComplete), no UI/VM needed.
    func testQueuePipeline_extractsJobViaMockServer() async throws {
        let container = try ModelContainerFactory.inMemory()
        let store = BackgroundStore(modelContainer: container)
        let provider = mockProvider()
        let queue = QueueActor(
            store: store,
            isPaused: { false },
            onSetPaused: { _ in },
            readExtractionSettings: { self.settings() },
            providerFactory: { provider }
        )

        let capture = Capture(
            url: "https://example.com/job", pageTitle: "Senior iOS Engineer - Acme",
            selectedText: "We are hiring an iOS engineer to build delightful apps.", rawHash: "mock-pipeline"
        )
        let job = Job(jobNumber: 1, title: "Original Title")
        job.capture = capture
        try await store.insert(job)
        let jobID = job.id

        let events = await queue.subscribe()
        try await queue.enqueue(jobIDs: [jobID], mode: .extract)
        for await event in events {
            if case .processingComplete = event { break }
        }

        let fetched = try await store.fetch(
            FetchDescriptor<Job>(predicate: #Predicate { $0.id == jobID })
        )
        let updated = try XCTUnwrap(fetched.first)
        XCTAssertEqual(updated.extractionStatus, .succeeded)
        XCTAssertEqual(updated.title, "Senior iOS Engineer")
        XCTAssertEqual(updated.company, "Acme")
        // Fresh AI results mark the job unread so it counts toward the Dock badge until opened.
        XCTAssertTrue(updated.unread, "a successful extraction should mark the job unread")

        // TASK-535: a new attempt records the requested MODEL id, not the provider id.
        let attempts = try await store.fetch(FetchDescriptor<LLMRequestAttempt>())
        let extractAttempt = try XCTUnwrap(
            attempts.first { $0.requestType == .extract && $0.status == .succeeded }
        )
        XCTAssertEqual(
            extractAttempt.modelRequested,
            "mock-model",
            "modelRequested must be the configured model, not the provider id"
        )
        XCTAssertNotEqual(
            extractAttempt.modelRequested,
            provider.id,
            "modelRequested must not be the provider id (\(provider.id))"
        )
        // TASK-537: the attempt records the effective provider endpoint.
        XCTAssertEqual(
            extractAttempt.baseURL,
            LLMProviderFactory.resolveBaseURL(
                provider: settings().llmProvider, customBaseURL: settings().llmBaseURL
            ),
            "attempt must persist the effective base URL"
        )
    }

    /// TASK-491 regression: a capture must kick the drain loop on its own. Previously the extraction
    /// request was inserted directly by the atomic ingest without kicking the queue, so a capture
    /// arriving while the loop was idle sat "Queued" until the user manually hit Resume.
    func testCapture_kicksQueue_andProcessesWithoutManualResume() async throws {
        let container = try ModelContainerFactory.inMemory()
        let store = BackgroundStore(modelContainer: container)
        let provider = mockProvider()
        let queue = QueueActor(
            store: store,
            isPaused: { false },
            onSetPaused: { _ in },
            readExtractionSettings: { self.settings() },
            providerFactory: { provider }
        )
        let jobService = JobService(store: store, queue: queue)

        let events = await queue.subscribe()
        // Ingest a capture — NOT queue.enqueue / resume. Nothing else kicks the queue.
        _ = try await jobService.ingestCapture(CapturePayload(
            url: "https://example.com/job",
            pageTitle: "Senior iOS Engineer - Acme",
            selectedText: "We are hiring an iOS engineer to build delightful apps."
        ))

        for await event in events {
            if case .processingComplete = event { break }
        }

        let jobs = try await store.fetch(FetchDescriptor<Job>())
        let job = try XCTUnwrap(jobs.first)
        XCTAssertEqual(job.extractionStatus, .succeeded, "the capture must process on its own (kick)")
        XCTAssertEqual(job.title, "Senior iOS Engineer")
    }

    func testModelsEndpoint_servesMockModel() async throws {
        let url = try XCTUnwrap(URL(string: "\(server.baseURL)/v1/models"))
        let (data, response) = try await URLSession.shared.data(from: url)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let ids = (obj?["data"] as? [[String: Any]])?.compactMap { $0["id"] as? String }
        XCTAssertEqual(ids, ["mock-model"])
    }
}
