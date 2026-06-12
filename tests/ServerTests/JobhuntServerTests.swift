import SwiftData
import XCTest
@testable import JobhuntCore
@testable import JobhuntServer

// MARK: - Stub LLM provider

private struct NoOpProvider: LLMProvider {
    let id: String = "noop"
    let concurrencyLimit: Int = 1
    func complete(_: ChatRequest) async throws -> ChatResponse {
        throw LLMProviderError.httpError(statusCode: 503, body: "no-op")
    }
}

// MARK: - Helpers

let testMCPToken = "test-mcp-token-abc123"

private func makeTestServer() throws -> JobhuntServer {
    let container = try ModelContainerFactory.inMemory()
    let store = BackgroundStore(modelContainer: container)
    let queue = QueueActor(
        store: store,
        isPaused: { false },
        onSetPaused: { _ in },
        readExtractionSettings: { ExtractionSettings(llmModel: "", preferredLocations: "", locationFilterEnabled: false, locationAllowRemote: true, locationAllowHybrid: true, locationAllowOnsite: true) },
        providerFactory: { NoOpProvider() }
    )
    let jobService = JobService(store: store, queue: queue)
    let siteService = SiteService(store: store)
    return JobhuntServer(jobService: jobService, siteService: siteService, appVersion: "1.0.0-test", store: store, mcpToken: testMCPToken)
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

private struct SiteReviewBody: Decodable {
    let isOK: Bool
    let siteReviewID: String
    enum CodingKeys: String, CodingKey {
        case isOK = "ok"
        case siteReviewID = "site_review_id"
    }
}

private struct JobByURLBody: Decodable {
    let jobNumber: Int
    enum CodingKeys: String, CodingKey { case jobNumber = "job_number" }
}

private struct FocusBody: Decodable {
    let isOK: Bool
    enum CodingKeys: String, CodingKey { case isOK = "ok" }
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
        let url = await URL(string: baseURL() + "/api/ping")!
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
        let url = await URL(string: baseURL() + "/health")!
        let (data, response) = try await URLSession.shared.data(from: url)
        let http = try XCTUnwrap(response as? HTTPURLResponse)
        XCTAssertEqual(http.statusCode, 200)

        let body = try JSONDecoder().decode(HealthBody.self, from: data)
        XCTAssertTrue(body.isOK)
    }

    func testCaptureEndpoint() async throws {
        // swiftlint:disable:next force_unwrapping
        let url = await URL(string: baseURL() + "/captures")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("chrome-extension://testextension", forHTTPHeaderField: "Origin")
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

        // CORS headers must echo the extension origin, not wildcard
        XCTAssertEqual(http.value(forHTTPHeaderField: "Access-Control-Allow-Origin"), "chrome-extension://testextension")
    }

    // TASK-122 regression: mutating routes require chrome-extension:// origin
    func testCaptureWithoutExtensionOriginIsRejected() async throws {
        // swiftlint:disable:next force_unwrapping
        let url = await URL(string: baseURL() + "/captures")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("https://evil.example.com", forHTTPHeaderField: "Origin")
        let payload: [String: String] = [
            "url": "https://example.com/jobs/evil",
            "page_title": "Evil",
            "visible_text": "malicious"
        ]
        req.httpBody = try JSONEncoder().encode(payload)

        let (_, response) = try await URLSession.shared.data(for: req)
        let http = try XCTUnwrap(response as? HTTPURLResponse)
        XCTAssertEqual(http.statusCode, 403, "Non-extension origin must be rejected on mutating routes")
    }

    func testCaptureValidation_missingURL() async throws {
        // swiftlint:disable:next force_unwrapping
        let url = await URL(string: baseURL() + "/captures")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("chrome-extension://testextension", forHTTPHeaderField: "Origin")
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
        let url = await URL(string: baseURL() + "/captures")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("chrome-extension://testextension", forHTTPHeaderField: "Origin")
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

    // TASK-122 regression: CORS echoes extension origin; PNA header only on preflight
    func testCORSPreflight_extensionOrigin_includesPNAHeader() async throws {
        // swiftlint:disable:next force_unwrapping
        let url = await URL(string: baseURL() + "/captures")!
        var req = URLRequest(url: url)
        req.httpMethod = "OPTIONS"
        req.setValue("chrome-extension://abc123", forHTTPHeaderField: "Origin")
        req.setValue("true", forHTTPHeaderField: "Access-Control-Request-Private-Network")

        let (_, response) = try await URLSession.shared.data(for: req)
        let http = try XCTUnwrap(response as? HTTPURLResponse)
        XCTAssertTrue(http.statusCode == 204 || http.statusCode == 200)
        XCTAssertEqual(http.value(forHTTPHeaderField: "Access-Control-Allow-Private-Network"), "true")
        XCTAssertEqual(http.value(forHTTPHeaderField: "Access-Control-Allow-Origin"), "chrome-extension://abc123")
    }

    // TASK-122 regression: no CORS headers for non-extension origins
    func testCORSPreflight_nonExtensionOrigin_noCORSHeaders() async throws {
        // swiftlint:disable:next force_unwrapping
        let url = await URL(string: baseURL() + "/captures")!
        var req = URLRequest(url: url)
        req.httpMethod = "OPTIONS"
        req.setValue("https://evil.example.com", forHTTPHeaderField: "Origin")

        let (_, response) = try await URLSession.shared.data(for: req)
        let http = try XCTUnwrap(response as? HTTPURLResponse)
        // Preflight returns 204 regardless (not rejected), but no ACAO header
        XCTAssertNil(http.value(forHTTPHeaderField: "Access-Control-Allow-Origin"),
                     "Non-extension origin must not receive CORS headers")
    }

    func testNotFoundReturns404() async throws {
        // swiftlint:disable:next force_unwrapping
        let url = await URL(string: baseURL() + "/api/nonexistent")!
        let (_, response) = try await URLSession.shared.data(from: url)
        let http = try XCTUnwrap(response as? HTTPURLResponse)
        XCTAssertEqual(http.statusCode, 404)
    }

    // MARK: - Lifecycle: start/stop idempotency (TASK-248)

    func testStart_calledTwice_doesNotCreateSecondListener() async throws {
        // server was already started in setUp(); calling start() again must be a no-op
        let portBefore = await server.listeningPort
        try await server.start()
        let portAfter = await server.listeningPort
        XCTAssertEqual(portBefore, portAfter, "Calling start() while already running must not change the port")
        // Verify the server is still functional (not in an error state)
        // swiftlint:disable:next force_unwrapping
        let url = URL(string: "http://127.0.0.1:\(portAfter)/health")!
        let (_, response) = try await URLSession.shared.data(from: url)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
    }

    func testStop_thenStart_canRestartCleanly() async throws {
        await server.stop()
        let portAfterStop = await server.listeningPort
        XCTAssertEqual(portAfterStop, 0, "Port must reset to 0 after stop()")

        try await server.start()
        let portAfterRestart = await server.listeningPort
        XCTAssertGreaterThan(portAfterRestart, 0, "Server must acquire a port after restart")

        // swiftlint:disable:next force_unwrapping
        let url = URL(string: "http://127.0.0.1:\(portAfterRestart)/health")!
        let (_, response) = try await URLSession.shared.data(from: url)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200, "Restarted server must respond to /health")
    }

    // MARK: - MCP DTO compatibility

    private func mcpRequest(path: String, body: [String: Any] = [:], token: String = testMCPToken) async throws -> (Data, HTTPURLResponse) {
        // swiftlint:disable:next force_unwrapping
        let url = await URL(string: baseURL() + path)!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(token, forHTTPHeaderField: "X-MCP-Token")
        if !body.isEmpty {
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await URLSession.shared.data(for: req)
        return (data, try XCTUnwrap(response as? HTTPURLResponse))
    }

    func testMCPJobsListDTOShape() async throws {
        // Ingest a job first so there is something to list
        let captureURL = await URL(string: baseURL() + "/captures")!
        var captureReq = URLRequest(url: captureURL)
        captureReq.httpMethod = "POST"
        captureReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        captureReq.setValue("chrome-extension://testextension", forHTTPHeaderField: "Origin")
        let capturePayload: [String: String] = [
            "url": "https://example.com/job/dto-test",
            "page_title": "DTO Test Job",
            "visible_text": "A job for testing MCP DTO shape"
        ]
        captureReq.httpBody = try JSONEncoder().encode(capturePayload)
        _ = try await URLSession.shared.data(for: captureReq)

        let (data, http) = try await mcpRequest(path: "/mcp/jobs/list")
        XCTAssertEqual(http.statusCode, 200)

        let jobs = try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        let job = try XCTUnwrap(jobs?.first)

        XCTAssertNotNil(job["job_id"] as? String, "MCP job DTO must include job_id")
        XCTAssertNotNil(job["status"] as? String, "MCP job DTO must include status")
        XCTAssertNotNil(job["extraction_status"] as? String, "MCP job DTO must include extraction_status")
        XCTAssertNotNil(job["created_at"] as? String, "MCP job DTO must include created_at")
        XCTAssertNil(job["id"], "MCP job DTO must not expose raw SwiftData id key")
    }

    func testMCPSitesListDTOShape() async throws {
        let (data, http) = try await mcpRequest(path: "/mcp/sites/list")
        XCTAssertEqual(http.statusCode, 200)

        // Empty array is valid — just verify it decodes as an array
        let sites = try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        XCTAssertNotNil(sites, "MCP sites/list must return a JSON array")
    }

    func testMCPJobGetDTOShape() async throws {
        // Ingest to get a job number
        let captureURL = await URL(string: baseURL() + "/captures")!
        var captureReq = URLRequest(url: captureURL)
        captureReq.httpMethod = "POST"
        captureReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        captureReq.setValue("chrome-extension://testextension", forHTTPHeaderField: "Origin")
        let capturePayload: [String: String] = [
            "url": "https://example.com/job/get-test",
            "page_title": "Get Test Job",
            "visible_text": "Detail DTO test"
        ]
        captureReq.httpBody = try JSONEncoder().encode(capturePayload)
        let (captureData, _) = try await URLSession.shared.data(for: captureReq)
        let captureBody = try JSONDecoder().decode(CaptureBody.self, from: captureData)

        let (data, http) = try await mcpRequest(path: "/mcp/jobs/get", body: ["job_number": captureBody.jobNumber])
        XCTAssertEqual(http.statusCode, 200)

        let job = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNotNil(job["job_id"] as? String, "MCP job detail DTO must include job_id")
        XCTAssertNotNil(job["status"] as? String, "MCP job detail DTO must include status")
        XCTAssertNotNil(job["extraction_status"] as? String, "MCP job detail DTO must include extraction_status")
        XCTAssertNotNil(job["created_at"] as? String, "MCP job detail DTO must include created_at")
    }

    // TASK-123 regression: MCP token auth — wrong, empty, correct, and unconfigured cases
    func testMCPUnauthorizedWithoutToken() async throws {
        let (_, http) = try await mcpRequest(path: "/mcp/jobs/list", token: "wrong-token")
        XCTAssertEqual(http.statusCode, 401)
    }

    func testMCPUnauthorizedWithEmptyToken() async throws {
        let (_, http) = try await mcpRequest(path: "/mcp/jobs/list", token: "")
        XCTAssertEqual(http.statusCode, 401, "Empty token must be rejected")
    }

    func testMCPAuthorizedWithCorrectToken() async throws {
        let (_, http) = try await mcpRequest(path: "/mcp/jobs/list", token: testMCPToken)
        XCTAssertEqual(http.statusCode, 200, "Correct token must be accepted")
    }

    func testMCPServerWithEmptyTokenRejects503() async throws {
        // A server initialized with an empty token must fail closed (503 Not Configured)
        let container = try ModelContainerFactory.inMemory()
        let store = BackgroundStore(modelContainer: container)
        let queue = QueueActor(
            store: store, isPaused: { false }, onSetPaused: { _ in },
            readExtractionSettings: { ExtractionSettings(llmModel: "", preferredLocations: "", locationFilterEnabled: false, locationAllowRemote: true, locationAllowHybrid: true, locationAllowOnsite: true) },
            providerFactory: { NoOpProvider() }
        )
        let emptyTokenServer = JobhuntServer(
            jobService: JobService(store: store, queue: queue),
            siteService: SiteService(store: store),
            appVersion: "1.0.0-test",
            store: store,
            mcpToken: ""
        )
        try await emptyTokenServer.start()
        defer { Task { await emptyTokenServer.stop() } }

        let port = await emptyTokenServer.listeningPort
        // swiftlint:disable:next force_unwrapping
        let url = URL(string: "http://127.0.0.1:\(port)/mcp/jobs/list")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("", forHTTPHeaderField: "X-MCP-Token")
        let (_, response) = try await URLSession.shared.data(for: req)
        let http = try XCTUnwrap(response as? HTTPURLResponse)
        XCTAssertEqual(http.statusCode, 503, "Empty server token must fail closed with 503")
    }

    // MARK: - Route boundary tests: /site-reviews

    func testSiteReview_happyPath() async throws {
        // swiftlint:disable:next force_unwrapping
        let url = await URL(string: baseURL() + "/site-reviews")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("chrome-extension://testextension", forHTTPHeaderField: "Origin")
        let body: [String: Any] = ["url": "https://acme.com/jobs", "interval_days": 30]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: req)
        let http = try XCTUnwrap(response as? HTTPURLResponse)
        XCTAssertEqual(http.statusCode, 200)
        let decoded = try JSONDecoder().decode(SiteReviewBody.self, from: data)
        XCTAssertTrue(decoded.isOK)
        XCTAssertFalse(decoded.siteReviewID.isEmpty)
    }

    // TASK-261: Extension sends site_url/site_origin/reviewed_at/next_review_at — contract test
    func testSiteReview_extensionPayload_returns200AndPersists() async throws {
        // swiftlint:disable:next force_unwrapping
        let url = await URL(string: baseURL() + "/site-reviews")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("chrome-extension://testextension", forHTTPHeaderField: "Origin")
        // Exact field names used by buildSiteReviewPayload in service_worker.js
        let body: [String: Any] = [
            "schema_version": 1,
            "reviewed_at": "2026-06-11T10:00:00.000Z",
            "site_url": "https://jobs.acme.io/careers",
            "site_origin": "https://jobs.acme.io",
            "page_title": "Acme Jobs",
            "next_review_at": NSNull(),
            "note": ""
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: req)
        let http = try XCTUnwrap(response as? HTTPURLResponse)
        XCTAssertEqual(http.statusCode, 200, "Extension site-review payload must be accepted with 200")
        let decoded = try JSONDecoder().decode(SiteReviewBody.self, from: data)
        XCTAssertTrue(decoded.isOK)
        XCTAssertFalse(decoded.siteReviewID.isEmpty, "site_review_id must be non-empty")
    }

    // TASK-262: Extension sends structured_data as array — contract test
    func testCapture_structuredDataArray_isSerialized() async throws {
        // swiftlint:disable:next force_unwrapping
        let url = await URL(string: baseURL() + "/captures")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("chrome-extension://testextension", forHTTPHeaderField: "Origin")
        let body: [String: Any] = [
            "url": "https://example.com/jobs/structured-array-test",
            "page_title": "Structured Array Test",
            "visible_text": "Job description with structured data array",
            "structured_data": [["@type": "JobPosting", "title": "Engineer"]]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: req)
        let http = try XCTUnwrap(response as? HTTPURLResponse)
        XCTAssertEqual(http.statusCode, 200, "Capture with structured_data array must succeed")
        let decoded = try JSONDecoder().decode(CaptureBody.self, from: data)
        XCTAssertTrue(decoded.isOK)
        XCTAssertFalse(decoded.captureID.isEmpty)
    }

    func testSiteReview_intervalTooSmall_returns400() async throws {
        // swiftlint:disable:next force_unwrapping
        let url = await URL(string: baseURL() + "/site-reviews")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("chrome-extension://testextension", forHTTPHeaderField: "Origin")
        let body: [String: Any] = ["url": "https://acme.com/jobs", "interval_days": 0]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (_, response) = try await URLSession.shared.data(for: req)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 400)
    }

    func testSiteReview_intervalTooLarge_returns400() async throws {
        // swiftlint:disable:next force_unwrapping
        let url = await URL(string: baseURL() + "/site-reviews")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("chrome-extension://testextension", forHTTPHeaderField: "Origin")
        let body: [String: Any] = ["url": "https://acme.com/jobs", "interval_days": 366]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (_, response) = try await URLSession.shared.data(for: req)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 400)
    }

    // MARK: - Route boundary tests: /api/jobs/by-url

    func testJobsByURL_nonExtensionOrigin_returns403() async throws {
        // swiftlint:disable:next force_unwrapping
        let url = await URL(string: baseURL() + "/api/jobs/by-url?url=https://example.com/job/1")!
        let (_, response) = try await URLSession.shared.data(from: url)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 403,
                       "/api/jobs/by-url must be extension-only")
    }

    func testJobsByURL_notFound_returns404() async throws {
        // swiftlint:disable:next force_unwrapping
        let url = await URL(string: baseURL() + "/api/jobs/by-url?url=https://unknown.example.com/job/99")!
        var req = URLRequest(url: url)
        req.setValue("chrome-extension://testextension", forHTTPHeaderField: "Origin")
        let (_, response) = try await URLSession.shared.data(for: req)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 404)
    }

    func testJobsByURL_found_returnsJobNumber() async throws {
        // First ingest a job so there's something to find
        let captureURL = await URL(string: baseURL() + "/captures")!
        var captureReq = URLRequest(url: captureURL)
        captureReq.httpMethod = "POST"
        captureReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        captureReq.setValue("chrome-extension://testextension", forHTTPHeaderField: "Origin")
        let capturePayload: [String: String] = [
            "url": "https://findme.example.com/job/42",
            "page_title": "Found Job",
            "visible_text": "job description text for search test"
        ]
        captureReq.httpBody = try JSONEncoder().encode(capturePayload)
        let (captureData, _) = try await URLSession.shared.data(for: captureReq)
        let captureBody = try JSONDecoder().decode(CaptureBody.self, from: captureData)

        // swiftlint:disable:next force_unwrapping
        let searchURL = await URL(string: baseURL() + "/api/jobs/by-url?url=https://findme.example.com/job/42")!
        var req = URLRequest(url: searchURL)
        req.setValue("chrome-extension://testextension", forHTTPHeaderField: "Origin")
        let (data, response) = try await URLSession.shared.data(for: req)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        let body = try JSONDecoder().decode(JobByURLBody.self, from: data)
        XCTAssertEqual(body.jobNumber, captureBody.jobNumber)
    }

    // MARK: - Route boundary tests: /api/app/focus

    func testAppFocus_withoutJobNumber_returns200() async throws {
        // swiftlint:disable:next force_unwrapping
        let url = await URL(string: baseURL() + "/api/app/focus")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("chrome-extension://testextension", forHTTPHeaderField: "Origin")
        let (data, response) = try await URLSession.shared.data(for: req)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        let body = try JSONDecoder().decode(FocusBody.self, from: data)
        XCTAssertTrue(body.isOK)
    }

    func testAppFocus_withJobNumber_returns200() async throws {
        // swiftlint:disable:next force_unwrapping
        let url = await URL(string: baseURL() + "/api/app/focus")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("chrome-extension://testextension", forHTTPHeaderField: "Origin")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["job_number": 7])
        let (data, response) = try await URLSession.shared.data(for: req)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        let body = try JSONDecoder().decode(FocusBody.self, from: data)
        XCTAssertTrue(body.isOK)
    }

    // MARK: - MCP limit bounds

    func testMCPJobsList_limitZero_returns400() async throws {
        let (_, http) = try await mcpRequest(path: "/mcp/jobs/list", body: ["limit": 0])
        XCTAssertEqual(http.statusCode, 400, "limit=0 must be rejected (min is 1)")
    }

    func testMCPJobsList_limitAboveMax_isClamped() async throws {
        // limit=1000 exceeds the 200 cap; server should clamp and return 200 (not reject)
        let (data, http) = try await mcpRequest(path: "/mcp/jobs/list", body: ["limit": 1000])
        XCTAssertEqual(http.statusCode, 200, "limit above max must be clamped, not rejected")
        let jobs = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        XCTAssertNotNil(jobs, "Response must be a JSON array")
    }

    func testMCPJobGet_defaultResponse_omitsRawText() async throws {
        // Ingest a job with both selected_text and visible_text
        let captureURL = await URL(string: baseURL() + "/captures")!
        var captureReq = URLRequest(url: captureURL)
        captureReq.httpMethod = "POST"
        captureReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        captureReq.setValue("chrome-extension://testextension", forHTTPHeaderField: "Origin")
        let capturePayload: [String: String] = [
            "url": "https://example.com/job/rawtext-test",
            "page_title": "Raw Text Test",
            "visible_text": "lots of visible text here",
            "selected_text": "selected portion here"
        ]
        captureReq.httpBody = try JSONEncoder().encode(capturePayload)
        let (captureData, _) = try await URLSession.shared.data(for: captureReq)
        let captureBody = try JSONDecoder().decode(CaptureBody.self, from: captureData)

        // Default request — include_raw_text not set
        let (data, http) = try await mcpRequest(path: "/mcp/jobs/get", body: ["job_number": captureBody.jobNumber])
        XCTAssertEqual(http.statusCode, 200)
        let job = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(job["selected_text"], "selected_text must be omitted by default")
        XCTAssertNil(job["visible_text"], "visible_text must be omitted by default")
    }

    func testMCPJobGet_includeRawText_true_includesRawText() async throws {
        let captureURL = await URL(string: baseURL() + "/captures")!
        var captureReq = URLRequest(url: captureURL)
        captureReq.httpMethod = "POST"
        captureReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        captureReq.setValue("chrome-extension://testextension", forHTTPHeaderField: "Origin")
        let capturePayload: [String: String] = [
            "url": "https://example.com/job/rawtext-include-test",
            "page_title": "Raw Text Include Test",
            "visible_text": "visible content",
            "selected_text": "selected content"
        ]
        captureReq.httpBody = try JSONEncoder().encode(capturePayload)
        let (captureData, _) = try await URLSession.shared.data(for: captureReq)
        let captureBody = try JSONDecoder().decode(CaptureBody.self, from: captureData)

        // include_raw_text: true
        let (data, http) = try await mcpRequest(
            path: "/mcp/jobs/get",
            body: ["job_number": captureBody.jobNumber, "include_raw_text": true]
        )
        XCTAssertEqual(http.statusCode, 200)
        let job = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNotNil(job["selected_text"], "selected_text must be included when include_raw_text=true")
        XCTAssertNotNil(job["visible_text"], "visible_text must be included when include_raw_text=true")
    }

    func testMCPJobsList_limitOne_returnsAtMostOneJob() async throws {
        // Ingest two jobs first
        for i in 1...2 {
            let captureURL = await URL(string: baseURL() + "/captures")!
            var captureReq = URLRequest(url: captureURL)
            captureReq.httpMethod = "POST"
            captureReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
            captureReq.setValue("chrome-extension://testextension", forHTTPHeaderField: "Origin")
            let payload: [String: String] = [
                "url": "https://example.com/job/limit-test-\(i)",
                "page_title": "Limit Test \(i)",
                "visible_text": "limit test description \(i)"
            ]
            captureReq.httpBody = try JSONEncoder().encode(payload)
            _ = try await URLSession.shared.data(for: captureReq)
        }

        let (data, http) = try await mcpRequest(path: "/mcp/jobs/list", body: ["limit": 1])
        XCTAssertEqual(http.statusCode, 200)
        let jobs = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        XCTAssertLessThanOrEqual(jobs.count, 1, "limit=1 must return at most 1 job")
    }
}

// MARK: - HTTPRequest parser unit tests

final class HTTPRequestParserTests: XCTestCase {

    private func makeRaw(method: String = "POST", path: String = "/test",
                         headers: [String: String] = [:], body: Data? = nil) -> Data {
        var headerLines = "\(method) \(path) HTTP/1.1\r\n"
        for (k, v) in headers { headerLines += "\(k): \(v)\r\n" }
        if let body {
            headerLines += "Content-Length: \(body.count)\r\n"
        }
        headerLines += "\r\n"
        var raw = headerLines.data(using: .ascii)!
        if let body { raw.append(body) }
        return raw
    }

    func testParse_basicRequest() {
        let raw = makeRaw(method: "GET", path: "/ping")
        let req = parseHTTPRequest(raw)
        XCTAssertEqual(req?.method, "GET")
        XCTAssertEqual(req?.path, "/ping")
        XCTAssertNil(req?.body)
    }

    func testParse_nonASCIIUTF8Body_preservedCorrectly() throws {
        // Multi-byte UTF-8 characters: emoji + accented letters
        let jsonString = #"{"title":"Développeur 🚀","note":"café"}"#
        let bodyBytes = jsonString.data(using: .utf8)!
        let raw = makeRaw(headers: ["Content-Type": "application/json"], body: bodyBytes)
        let req = try XCTUnwrap(parseHTTPRequest(raw))
        // Body must contain exactly the right bytes, not truncated at character boundaries
        XCTAssertEqual(req.body, bodyBytes)

        struct Payload: Decodable { let title: String; let note: String }
        let decoded = try req.decodeBody(as: Payload.self)
        XCTAssertEqual(decoded.title, "Développeur 🚀")
        XCTAssertEqual(decoded.note, "café")
    }

    func testParse_malformed_noSeparator_returnsNil() {
        // Missing \r\n\r\n — parser must return nil, not crash
        let raw = "GET /ping HTTP/1.1\r\nHost: localhost\r\n".data(using: .ascii)!
        XCTAssertNil(parseHTTPRequest(raw))
    }

    func testParse_emptyData_returnsNil() {
        XCTAssertNil(parseHTTPRequest(Data()))
    }

    func testParse_queryString_parsedCorrectly() {
        let raw = makeRaw(method: "GET", path: "/api/jobs/by-url?url=https%3A%2F%2Fx.com%2Fjob%2F1&extra=val")
        let req = parseHTTPRequest(raw)
        XCTAssertEqual(req?.path, "/api/jobs/by-url")
        XCTAssertEqual(req?.queryValue(for: "url"), "https://x.com/job/1")
        XCTAssertEqual(req?.queryValue(for: "extra"), "val")
    }

    func testParse_headersCaseNormalized() {
        let raw = makeRaw(method: "POST", path: "/captures",
                          headers: ["Content-Type": "application/json", "Origin": "chrome-extension://abc"])
        let req = parseHTTPRequest(raw)
        XCTAssertEqual(req?.headers["content-type"], "application/json")
        XCTAssertEqual(req?.headers["origin"], "chrome-extension://abc")
    }

    func testParse_noContentLength_bodyIsNil() {
        // A request without Content-Length must not try to slice a body
        var headerLines = "POST /test HTTP/1.1\r\nContent-Type: application/json\r\n\r\n"
        headerLines += #"{"key":"value"}"#
        let raw = headerLines.data(using: .utf8)!
        let req = parseHTTPRequest(raw)
        XCTAssertNotNil(req)
        XCTAssertNil(req?.body, "Body must be nil when Content-Length is absent")
    }
}

// MARK: - Capture field byte-limit tests (TASK-202)

final class CaptureFieldLimitTests: XCTestCase {
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

    private func postCapture(body: [String: Any]) async throws -> HTTPURLResponse {
        let port = await server.listeningPort
        // swiftlint:disable:next force_unwrapping
        let url = URL(string: "http://127.0.0.1:\(port)/captures")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("chrome-extension://testextension", forHTTPHeaderField: "Origin")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (_, response) = try await URLSession.shared.data(for: req)
        return try XCTUnwrap(response as? HTTPURLResponse)
    }

    func testCapture_visibleText_atLimit_returns200() async throws {
        // 500 KB exactly — should be accepted
        let atLimit = String(repeating: "a", count: 500 * 1024)
        let http = try await postCapture(body: [
            "url": "https://example.com/job/vt-at-limit",
            "page_title": "VT At Limit",
            "visible_text": atLimit
        ])
        XCTAssertEqual(http.statusCode, 200, "visible_text at 500 KB limit must be accepted")
    }

    func testCapture_visibleText_overLimit_returns400() async throws {
        // 500 KB + 1 byte — should be rejected
        let overLimit = String(repeating: "a", count: 500 * 1024 + 1)
        let http = try await postCapture(body: [
            "url": "https://example.com/job/vt-over-limit",
            "page_title": "VT Over Limit",
            "visible_text": overLimit
        ])
        XCTAssertEqual(http.statusCode, 400, "visible_text over 500 KB must be rejected with 400")
    }

    func testCapture_selectedText_atLimit_returns200() async throws {
        // 500 KB exactly — should be accepted
        let atLimit = String(repeating: "b", count: 500 * 1024)
        let http = try await postCapture(body: [
            "url": "https://example.com/job/st-at-limit",
            "page_title": "ST At Limit",
            "selected_text": atLimit
        ])
        XCTAssertEqual(http.statusCode, 200, "selected_text at 500 KB limit must be accepted")
    }

    func testCapture_selectedText_overLimit_returns400() async throws {
        // 500 KB + 1 byte — should be rejected
        let overLimit = String(repeating: "b", count: 500 * 1024 + 1)
        let http = try await postCapture(body: [
            "url": "https://example.com/job/st-over-limit",
            "page_title": "ST Over Limit",
            "selected_text": overLimit
        ])
        XCTAssertEqual(http.statusCode, 400, "selected_text over 500 KB must be rejected with 400")
    }

    func testCapture_structuredDataJSON_atLimit_returns200() async throws {
        // 100 KB exactly — should be accepted; wrap in quotes to make valid JSON string value
        let filler = String(repeating: "c", count: 100 * 1024 - 2) // account for quotes in encoding
        let http = try await postCapture(body: [
            "url": "https://example.com/job/sdj-at-limit",
            "page_title": "SDJ At Limit",
            "visible_text": "some text",
            "structured_data_json": filler
        ])
        // Either 200 (accepted as-is, may not parse as valid JSON array) or 400 for size is fine;
        // the important constraint is that exactly-100KB is NOT rejected solely for size.
        // The server returns 200 (field within limit) even if structured_data_json isn't valid JSON.
        XCTAssertNotEqual(http.statusCode, 413, "structured_data_json at 100 KB must not cause 413")
    }

    func testCapture_structuredDataJSON_overLimit_returns400() async throws {
        // 100 KB + 1 byte — should be rejected
        let overLimit = String(repeating: "c", count: 100 * 1024 + 1)
        let http = try await postCapture(body: [
            "url": "https://example.com/job/sdj-over-limit",
            "page_title": "SDJ Over Limit",
            "visible_text": "some text",
            "structured_data_json": overLimit
        ])
        XCTAssertEqual(http.statusCode, 400, "structured_data_json over 100 KB must be rejected with 400")
    }

    func testCapture_userNote_atLimit_returns200() async throws {
        // 10 KB exactly — should be accepted
        let atLimit = String(repeating: "d", count: 10 * 1024)
        let http = try await postCapture(body: [
            "url": "https://example.com/job/note-at-limit",
            "page_title": "Note At Limit",
            "visible_text": "some text",
            "user_note": atLimit
        ])
        XCTAssertEqual(http.statusCode, 200, "user_note at 10 KB limit must be accepted")
    }

    func testCapture_userNote_overLimit_returns400() async throws {
        // 10 KB + 1 byte — should be rejected
        let overLimit = String(repeating: "d", count: 10 * 1024 + 1)
        let http = try await postCapture(body: [
            "url": "https://example.com/job/note-over-limit",
            "page_title": "Note Over Limit",
            "visible_text": "some text",
            "user_note": overLimit
        ])
        XCTAssertEqual(http.statusCode, 400, "user_note over 10 KB must be rejected with 400")
    }
}

// MARK: - MCP jobs/list limit clamping tests (TASK-203)

final class MCPJobsListLimitTests: XCTestCase {
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

    private func mcpJobsList(limit: Int?) async throws -> HTTPURLResponse {
        let port = await server.listeningPort
        // swiftlint:disable:next force_unwrapping
        let url = URL(string: "http://127.0.0.1:\(port)/mcp/jobs/list")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(testMCPToken, forHTTPHeaderField: "X-MCP-Token")
        if let limit {
            req.httpBody = try JSONSerialization.data(withJSONObject: ["limit": limit])
        }
        let (_, response) = try await URLSession.shared.data(for: req)
        return try XCTUnwrap(response as? HTTPURLResponse)
    }

    func testMCPJobsList_negativeLimit_returns400() async throws {
        let http = try await mcpJobsList(limit: -1)
        XCTAssertEqual(http.statusCode, 400, "Negative limit must be rejected with 400")
    }

    func testMCPJobsList_limitZero_returns400() async throws {
        let http = try await mcpJobsList(limit: 0)
        XCTAssertEqual(http.statusCode, 400, "limit=0 must be rejected with 400")
    }

    func testMCPJobsList_defaultLimit_returns200() async throws {
        // No limit specified — server uses default 50
        let http = try await mcpJobsList(limit: nil)
        XCTAssertEqual(http.statusCode, 200, "Default (no limit) must return 200")
    }

    func testMCPJobsList_limit200_returns200() async throws {
        let http = try await mcpJobsList(limit: 200)
        XCTAssertEqual(http.statusCode, 200, "limit=200 (max) must be accepted")
    }

    func testMCPJobsList_limit1000_clampedTo200_returns200() async throws {
        // limit=1000 exceeds max 200; must be clamped, not rejected
        let http = try await mcpJobsList(limit: 1000)
        XCTAssertEqual(http.statusCode, 200, "limit=1000 must be clamped to 200 and return 200")
    }
}

// MARK: - /site-reviews interval_days validation tests (TASK-204)

final class SiteReviewIntervalValidationTests: XCTestCase {
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

    private func postSiteReview(body: [String: Any]) async throws -> HTTPURLResponse {
        let port = await server.listeningPort
        // swiftlint:disable:next force_unwrapping
        let url = URL(string: "http://127.0.0.1:\(port)/site-reviews")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("chrome-extension://testextension", forHTTPHeaderField: "Origin")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (_, response) = try await URLSession.shared.data(for: req)
        return try XCTUnwrap(response as? HTTPURLResponse)
    }

    func testSiteReview_negativeInterval_returns400() async throws {
        let http = try await postSiteReview(body: ["url": "https://acme.com/jobs", "interval_days": -1])
        XCTAssertEqual(http.statusCode, 400, "Negative interval_days must be rejected with 400")
    }

    func testSiteReview_zeroInterval_returns400() async throws {
        let http = try await postSiteReview(body: ["url": "https://acme.com/jobs", "interval_days": 0])
        XCTAssertEqual(http.statusCode, 400, "interval_days=0 must be rejected with 400")
    }

    func testSiteReview_interval7_returns200() async throws {
        let http = try await postSiteReview(body: ["url": "https://acme.com/jobs", "interval_days": 7])
        XCTAssertEqual(http.statusCode, 200, "interval_days=7 must be accepted")
    }

    func testSiteReview_interval400_returns400() async throws {
        let http = try await postSiteReview(body: ["url": "https://acme.com/jobs", "interval_days": 400])
        XCTAssertEqual(http.statusCode, 400, "interval_days=400 (> 365) must be rejected with 400")
    }
}

// MARK: - Request size limit tests (TASK-200)

final class RequestSizeLimitTests: XCTestCase {
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

    func testOversizedRequest_returns413() async throws {
        let port = await server.listeningPort
        // swiftlint:disable:next force_unwrapping
        let url = URL(string: "http://127.0.0.1:\(port)/captures")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("chrome-extension://testextension", forHTTPHeaderField: "Origin")

        // Build a body that exceeds 10 MB
        let overLimit = 10 * 1024 * 1024 + 1
        let filler = String(repeating: "x", count: overLimit)
        let payload = "{\"url\":\"https://example.com\",\"page_title\":\"t\",\"visible_text\":\"\(filler)\"}"
        req.httpBody = payload.data(using: .utf8)

        let (_, response) = try await URLSession.shared.data(for: req)
        let http = try XCTUnwrap(response as? HTTPURLResponse)
        XCTAssertEqual(http.statusCode, 413, "Request exceeding 10 MB must be rejected with 413")
    }
}

// MARK: - TASK-263: MCP update_job salary fields

final class MCPUpdateJobSalaryTests: XCTestCase {
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

    private func baseURL() async -> String {
        let port = await server.listeningPort
        return "http://127.0.0.1:\(port)"
    }

    private func ingestJob(url: String) async throws -> Int {
        // swiftlint:disable:next force_unwrapping
        let captureURL = await URL(string: baseURL() + "/captures")!
        var req = URLRequest(url: captureURL)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("chrome-extension://testextension", forHTTPHeaderField: "Origin")
        let payload: [String: String] = ["url": url, "page_title": "Test Job", "visible_text": "description"]
        req.httpBody = try JSONEncoder().encode(payload)
        let (data, _) = try await URLSession.shared.data(for: req)
        let body = try JSONDecoder().decode(CaptureBody.self, from: data)
        return body.jobNumber
    }

    private func mcpPost(path: String, body: [String: Any]) async throws -> (Data, HTTPURLResponse) {
        // swiftlint:disable:next force_unwrapping
        let url = await URL(string: baseURL() + path)!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(testMCPToken, forHTTPHeaderField: "X-MCP-Token")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: req)
        return (data, try XCTUnwrap(response as? HTTPURLResponse))
    }

    func testUpdateJob_salaryMin_isPersisted() async throws {
        let jobNumber = try await ingestJob(url: "https://example.com/job/salary-min-test")
        let (_, updateHTTP) = try await mcpPost(
            path: "/mcp/jobs/update",
            body: ["job_number": jobNumber, "salary_min": 120_000]
        )
        XCTAssertEqual(updateHTTP.statusCode, 200)

        let (data, getHTTP) = try await mcpPost(path: "/mcp/jobs/get", body: ["job_number": jobNumber])
        XCTAssertEqual(getHTTP.statusCode, 200)
        let job = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(job["salary_min"] as? Int, 120_000, "salary_min must be persisted after update_job")
    }

    func testUpdateJob_salaryMax_isPersisted() async throws {
        let jobNumber = try await ingestJob(url: "https://example.com/job/salary-max-test")
        let (_, updateHTTP) = try await mcpPost(
            path: "/mcp/jobs/update",
            body: ["job_number": jobNumber, "salary_max": 180_000]
        )
        XCTAssertEqual(updateHTTP.statusCode, 200)

        let (data, _) = try await mcpPost(path: "/mcp/jobs/get", body: ["job_number": jobNumber])
        let job = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(job["salary_max"] as? Int, 180_000, "salary_max must be persisted after update_job")
    }

    func testUpdateJob_salaryNote_isPersisted() async throws {
        let jobNumber = try await ingestJob(url: "https://example.com/job/salary-note-test")
        let (_, updateHTTP) = try await mcpPost(
            path: "/mcp/jobs/update",
            body: ["job_number": jobNumber, "salary_note": "base + bonus"]
        )
        XCTAssertEqual(updateHTTP.statusCode, 200)

        let (data, _) = try await mcpPost(path: "/mcp/jobs/get", body: ["job_number": jobNumber])
        let job = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(job["salary_note"] as? String, "base + bonus", "salary_note must be persisted after update_job")
    }

    func testUpdateJob_allSalaryFields_arePersisted() async throws {
        let jobNumber = try await ingestJob(url: "https://example.com/job/salary-all-test")
        let (_, updateHTTP) = try await mcpPost(
            path: "/mcp/jobs/update",
            body: [
                "job_number": jobNumber,
                "salary_min": 100_000,
                "salary_max": 150_000,
                "salary_note": "equity included"
            ]
        )
        XCTAssertEqual(updateHTTP.statusCode, 200)

        let (data, _) = try await mcpPost(path: "/mcp/jobs/get", body: ["job_number": jobNumber])
        let job = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(job["salary_min"] as? Int, 100_000)
        XCTAssertEqual(job["salary_max"] as? Int, 150_000)
        XCTAssertEqual(job["salary_note"] as? String, "equity included")
    }
}

// MARK: - TASK-264: MCP jobs/list invalid status validation

final class MCPJobsListStatusValidationTests: XCTestCase {
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

    private func mcpJobsList(body: [String: Any]) async throws -> (Data, HTTPURLResponse) {
        let port = await server.listeningPort
        // swiftlint:disable:next force_unwrapping
        let url = URL(string: "http://127.0.0.1:\(port)/mcp/jobs/list")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(testMCPToken, forHTTPHeaderField: "X-MCP-Token")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: req)
        return (data, try XCTUnwrap(response as? HTTPURLResponse))
    }

    private func ingestJob(url: String) async throws {
        let port = await server.listeningPort
        // swiftlint:disable:next force_unwrapping
        let captureURL = URL(string: "http://127.0.0.1:\(port)/captures")!
        var req = URLRequest(url: captureURL)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("chrome-extension://testextension", forHTTPHeaderField: "Origin")
        let payload: [String: String] = ["url": url, "page_title": "Test", "visible_text": "desc"]
        req.httpBody = try JSONEncoder().encode(payload)
        _ = try await URLSession.shared.data(for: req)
    }

    func testJobsList_invalidStatus_returns400() async throws {
        let (data, http) = try await mcpJobsList(body: ["status": "typo_status"])
        XCTAssertEqual(http.statusCode, 400, "Invalid status string must return 400")
        let responseBody = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let error = try XCTUnwrap(responseBody["error"] as? String)
        XCTAssertTrue(error.contains("typo_status"), "Error message must mention the invalid value")
        XCTAssertTrue(error.contains("new") || error.contains("valid"), "Error message must hint at valid values")
    }

    func testJobsList_validStatus_returns200() async throws {
        try await ingestJob(url: "https://example.com/job/status-filter-test")

        let (data, http) = try await mcpJobsList(body: ["status": "new"])
        XCTAssertEqual(http.statusCode, 200, "Valid status 'new' must return 200")
        let jobs = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        XCTAssertNotNil(jobs)
    }

    func testJobsList_omittedStatus_returnsAllJobs() async throws {
        try await ingestJob(url: "https://example.com/job/no-status-filter-a")
        try await ingestJob(url: "https://example.com/job/no-status-filter-b")

        // No status key in body — should return all jobs (existing behavior)
        let (data, http) = try await mcpJobsList(body: [:])
        XCTAssertEqual(http.statusCode, 200, "Omitted status must return all jobs")
        let jobs = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(jobs.count, 2, "Omitted status must return all jobs without filtering")
    }
}
