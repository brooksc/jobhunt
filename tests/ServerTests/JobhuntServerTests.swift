// swiftlint:disable force_try force_unwrapping
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
    return JobhuntServer(jobService: jobService, siteService: siteService, appVersion: "1.0.0-test")
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
        let url = URL(string: await baseURL() + "/health")!
        let (data, response) = try await URLSession.shared.data(from: url)
        let http = try XCTUnwrap(response as? HTTPURLResponse)
        XCTAssertEqual(http.statusCode, 200)

        struct HealthBody: Decodable { let ok: Bool }
        let body = try JSONDecoder().decode(HealthBody.self, from: data)
        XCTAssertTrue(body.ok)
    }

    func testCaptureEndpoint() async throws {
        let url = URL(string: await baseURL() + "/captures")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload: [String: String] = [
            "url": "https://example.com/jobs/123",
            "page_title": "Senior Engineer",
            "visible_text": "We are looking for a senior engineer to join our team.",
        ]
        req.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await URLSession.shared.data(for: req)
        let http = try XCTUnwrap(response as? HTTPURLResponse)
        XCTAssertEqual(http.statusCode, 200)

        struct CaptureBody: Decodable {
            let ok: Bool; let capture_id: String; let job_number: Int; let duplicate: Bool
        }
        let body = try JSONDecoder().decode(CaptureBody.self, from: data)
        XCTAssertTrue(body.ok)
        XCTAssertFalse(body.capture_id.isEmpty)
        XCTAssertGreaterThan(body.job_number, 0)
        XCTAssertFalse(body.duplicate)
    }

    func testCaptureValidation_missingURL() async throws {
        let url = URL(string: await baseURL() + "/captures")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload: [String: String] = [
            "url": "",
            "page_title": "Senior Engineer",
            "visible_text": "Some text",
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
        let url = URL(string: await baseURL() + "/captures")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // No visible_text or selected_text
        let payload: [String: String] = [
            "url": "https://example.com/jobs/456",
            "page_title": "Engineer",
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
        let url = URL(string: await baseURL() + "/api/nonexistent")!
        let (_, response) = try await URLSession.shared.data(from: url)
        let http = try XCTUnwrap(response as? HTTPURLResponse)
        XCTAssertEqual(http.statusCode, 404)
    }
}
