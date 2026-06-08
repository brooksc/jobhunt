import XCTest
import SwiftData
@testable import JobhuntServer
@testable import JobhuntCore

// MARK: - Stub LLM provider

private struct NoOpProvider: LLMProvider {
    let id: String = "noop"
    let concurrencyLimit: Int = 1
    func complete(_ request: ChatRequest) async throws -> ChatResponse {
        throw LLMProviderError.httpError(statusCode: 503, body: "no-op")
    }
}

// MARK: - Helpers

private func makeTestServer() throws -> JobhuntServer {
    let container = try ModelContainerFactory.inMemory()
    let store = BackgroundStore(modelContainer: container)
    let context = ModelContext(container)
    let settings = SettingsStore(modelContext: context)
    let queue = QueueActor(store: store, settings: settings, providerFactory: { NoOpProvider() })
    let jobService = JobService(store: store, queue: queue)
    let siteService = SiteService(store: store)
    return JobhuntServer(jobService: jobService, siteService: siteService, appVersion: "1.0.0-test", store: store)
}

// MARK: - Response decodables (file-scope to avoid nesting violations)

private struct HealthBody: Decodable {
    let isOK: Bool
    enum CodingKeys: String, CodingKey { case isOK = "ok" }
}

private struct CaptureBody: Decodable {
    let isOK: Bool
    let captureID: String
    let jobNumber: Int
    let duplicate: Bool
    enum CodingKeys: String, CodingKey {
        case isOK = "ok"
        case captureID = "capture_id"
        case jobNumber = "job_number"
        case duplicate
    }
}

// MARK: - JobhuntServerTests

final class JobhuntServerTests: XCTestCase {
    private var server: JobhuntServer!

    override func setUp() async throws {
        try await super.setUp()
        server = try makeTestServer()
        try await server.start()
    }

    override func tearDown() async throws {
        await server.stop()
        server = nil
        try await super.tearDown()
    }

    // MARK: - Helper

    private func baseURL() async -> String {
        let port = await server.listeningPort
        return "http://127.0.0.1:\(port)"
    }

    // MARK: - Tests

    func testPingEndpoint() async throws {
        // swiftlint:disable:next force_unwrapping
        let url = URL(string: await baseURL() + "/api/ping")!
        let (data, response) = try await URLSession.shared.data(from: url)
        let http = try XCTUnwrap(response as? HTTPURLResponse)
        XCTAssertEqual(http.statusCode, 200)

        struct PingBody: Decodable { let app: String; let version: String; let isDemo: Bool }
        let body = try JSONDecoder().decode(PingBody.self, from: data)
        XCTAssertEqual(body.app, "jobhunt")
        XCTAssertEqual(body.version, "1.0.0-test")
        XCTAssertFalse(body.isDemo)
    }

    func testHealthEndpoint() async throws {
        // swiftlint:disable:next force_unwrapping
        let url = URL(string: await baseURL() + "/health")!
        let (data, response) = try await URLSession.shared.data(from: url)
        let http = try XCTUnwrap(response as? HTTPURLResponse)
        XCTAssertEqual(http.statusCode, 200)

        let body = try JSONDecoder().decode(HealthBody.self, from: data)
        XCTAssertTrue(body.isOK)
    }

    func testCaptureEndpoint() async throws {
        // swiftlint:disable:next force_unwrapping
        let url = URL(string: await baseURL() + "/captures")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload: [String: String] = [
            "url": "https://example.com/jobs/123",
            "page_title": "Senior Engineer",
            "visible_text": "We are looking for a senior engineer to join our team."
        ]
        req.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await URLSession.shared.data(for: req)
        let http = try XCTUnwrap(response as? HTTPURLResponse)
        XCTAssertEqual(http.statusCode, 200)

        let body = try JSONDecoder().decode(CaptureBody.self, from: data)
        XCTAssertTrue(body.isOK)
        XCTAssertFalse(body.captureID.isEmpty)
        XCTAssertGreaterThan(body.jobNumber, 0)
        XCTAssertFalse(body.duplicate)
    }

    func testCaptureValidation_missingURL() async throws {
        // swiftlint:disable:next force_unwrapping
        let url = URL(string: await baseURL() + "/captures")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload: [String: String] = [
            "url": "",
            "page_title": "Senior Engineer",
            "visible_text": "Some text"
        ]
        req.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await URLSession.shared.data(for: req)
        let http = try XCTUnwrap(response as? HTTPURLResponse)
        XCTAssertEqual(http.statusCode, 400)

        struct ErrorBody: Decodable { let error: String }
        let body = try JSONDecoder().decode(ErrorBody.self, from: data)
        XCTAssertFalse(body.error.isEmpty)
    }

    func testCaptureValidation_missingText() async throws {
        // swiftlint:disable:next force_unwrapping
        let url = URL(string: await baseURL() + "/captures")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // No visible_text or selected_text
        let payload: [String: String] = [
            "url": "https://example.com/jobs/456",
            "page_title": "Engineer"
        ]
        req.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await URLSession.shared.data(for: req)
        let http = try XCTUnwrap(response as? HTTPURLResponse)
        XCTAssertEqual(http.statusCode, 400)

        struct ErrorBody: Decodable { let error: String }
        let body = try JSONDecoder().decode(ErrorBody.self, from: data)
        XCTAssertFalse(body.error.isEmpty)
    }

    func testCORSPreflight() async throws {
        // swiftlint:disable:next force_unwrapping
        let url = URL(string: await baseURL() + "/captures")!
        var req = URLRequest(url: url)
        req.httpMethod = "OPTIONS"
        req.setValue("chrome-extension://abc123", forHTTPHeaderField: "Origin")
        req.setValue("true", forHTTPHeaderField: "Access-Control-Request-Private-Network")

        let (_, response) = try await URLSession.shared.data(for: req)
        let http = try XCTUnwrap(response as? HTTPURLResponse)
        // 204 or 200 both acceptable for preflight
        XCTAssertTrue(http.statusCode == 204 || http.statusCode == 200)
        // Verify PNA header is present
        let pna = http.value(forHTTPHeaderField: "Access-Control-Allow-Private-Network")
        XCTAssertEqual(pna, "true")
    }

    func testNotFoundReturns404() async throws {
        // swiftlint:disable:next force_unwrapping
        let url = URL(string: await baseURL() + "/api/nonexistent")!
        let (_, response) = try await URLSession.shared.data(from: url)
        let http = try XCTUnwrap(response as? HTTPURLResponse)
        XCTAssertEqual(http.statusCode, 404)
    }
}
