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
            snapshot: snapshot, provider: mockProvider(), settings: settings())

        // Input-aware: the mock echoed the page title it saw in the prompt.
        XCTAssertEqual(result.title, "Senior iOS Engineer")
        XCTAssertEqual(result.company, "Acme")
        XCTAssertEqual(result.remoteType, .remote)
        XCTAssertEqual(result.salaryMin, 150_000)
    }

    func testFitScoring_overLocalhostMock_parsesDimensions() async throws {
        let job = JobFitSnapshot(
            title: "iOS Engineer", company: "Acme",
            seniority: "senior", extractedJSON: nil, extractionModel: nil)
        let resume = ResumeSnapshot(text: "Swift / SwiftUI iOS developer with 6 years of experience.")

        let output = try await ExtractionEngine.scoreFit(
            job: job, resume: resume, model: "mock-model", provider: mockProvider())

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
            selectedText: "We are hiring an iOS engineer to build delightful apps.", rawHash: "mock-pipeline")
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
            FetchDescriptor<Job>(predicate: #Predicate { $0.id == jobID }))
        let updated = try XCTUnwrap(fetched.first)
        XCTAssertEqual(updated.extractionStatus, .succeeded)
        XCTAssertEqual(updated.title, "Senior iOS Engineer")
        XCTAssertEqual(updated.company, "Acme")
    }

    func testModelsEndpoint_servesMockModel() async throws {
        let url = URL(string: "\(server.baseURL)/v1/models")!
        let (data, response) = try await URLSession.shared.data(from: url)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let ids = (obj?["data"] as? [[String: Any]])?.compactMap { $0["id"] as? String }
        XCTAssertEqual(ids, ["mock-model"])
    }
}
