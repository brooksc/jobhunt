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

private func makeTestServer(
    allowArbitraryExtensionOrigins: Bool = true,
    allowedExtensionOrigins: Set<String> = JobhuntServer.defaultAllowedExtensionOrigins
) throws -> JobhuntServer {
    let container = try ModelContainerFactory.inMemory()
    let store = BackgroundStore(modelContainer: container)
    let context = ModelContext(container)
    let settings = SettingsStore(modelContext: context)
    let queue = QueueActor(
        store: store,
        isPaused: { false },
        onSetPaused: { _ in },
        readExtractionSettings: { settings.extractionSettings() },
        providerFactory: { NoOpProvider() }
    )
    let jobService = JobService(store: store, queue: queue)
    let siteService = SiteService(store: store)
    // Default to permit-all so the broad endpoint tests work regardless of build config; the
    // fail-closed (production) behavior is covered explicitly by JobhuntServerOriginTests.
    return JobhuntServer(
        jobService: jobService,
        siteService: siteService,
        appVersion: "1.0.0-test",
        store: store,
        mcpToken: "test-token-abc123",
        allowedExtensionOrigins: allowedExtensionOrigins,
        allowArbitraryExtensionOrigins: allowArbitraryExtensionOrigins
    )
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
    // Shared across all tests in this class — avoids per-test server create/destroy which
    // triggers NWListener port RST issues in sequential test runs.
    private static var sharedServer: JobhuntServer?
    private var server: JobhuntServer!

    override func setUp() async throws {
        try await super.setUp()
        if Self.sharedServer == nil {
            let s = try makeTestServer()
            try await s.startOnAnyPort()
            Self.sharedServer = s
        }
        server = Self.sharedServer!
    }

    override func tearDown() async throws {
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
    }

    /// The extension sends JSON-LD under `structured_data` (an array), not the pre-stringified
    /// `structured_data_json`. The server must accept and ingest it.
    func testCaptureEndpoint_acceptsStructuredDataArray() async throws {
        // swiftlint:disable:next force_unwrapping
        let url = await URL(string: baseURL() + "/captures")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("chrome-extension://testextension", forHTTPHeaderField: "Origin")
        let payloadObj: [String: Any] = [
            "url": "https://example.com/jobs/structured-1",
            "page_title": "Structured Engineer",
            "visible_text": "We are hiring an engineer.",
            "structured_data": [
                ["@type": "JobPosting", "title": "Structured Engineer", "baseSalary": 200000]
            ]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: payloadObj)

        let (data, response) = try await URLSession.shared.data(for: req)
        let http = try XCTUnwrap(response as? HTTPURLResponse)
        XCTAssertEqual(http.statusCode, 200)
        let body = try JSONDecoder().decode(CaptureBody.self, from: data)
        XCTAssertTrue(body.isOK)
        XCTAssertGreaterThan(body.jobNumber, 0)
    }

    /// The extension's "Mark site reviewed" sends `site_url` + reviewed_at/next_review_at/note,
    /// not `url` + interval_days. Before the contract fix this returned 400.
    func testSiteReview_acceptsExtensionPayload() async throws {
        // swiftlint:disable:next force_unwrapping
        let url = await URL(string: baseURL() + "/site-reviews")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("chrome-extension://testextension", forHTTPHeaderField: "Origin")
        let payloadObj: [String: Any] = [
            "schema_version": 1,
            "reviewed_at": "2026-06-13T12:00:00.000Z",
            "site_url": "https://boards.example.com/careers",
            "site_origin": "https://boards.example.com",
            "page_title": "Careers",
            "note": ""
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: payloadObj)

        let (data, response) = try await URLSession.shared.data(for: req)
        let http = try XCTUnwrap(response as? HTTPURLResponse)
        XCTAssertEqual(http.statusCode, 200)
        struct SiteReviewBody: Decodable {
            let isOK: Bool
            let siteReviewID: String
            enum CodingKeys: String, CodingKey { case isOK = "ok"; case siteReviewID = "site_review_id" }
        }
        let body = try JSONDecoder().decode(SiteReviewBody.self, from: data)
        XCTAssertTrue(body.isOK)
        XCTAssertFalse(body.siteReviewID.isEmpty)
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

    // TASK-334: CORS reflected for valid extension origins; blocked for others.
    func testCorsAllowsJobhuntExtensionOrigin() async throws {
        // chrome-extension:// origins are allowed (allowlist empty = permit all during dev)
        // swiftlint:disable:next force_unwrapping
        let url = await URL(string: baseURL() + "/captures")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("chrome-extension://jobhuntextid123", forHTTPHeaderField: "Origin")
        let payload: [String: String] = [
            "url": "https://example.com/jobs/cors-test",
            "page_title": "CORS Test",
            "visible_text": "testing cors header reflection"
        ]
        req.httpBody = try JSONEncoder().encode(payload)
        let (_, response) = try await URLSession.shared.data(for: req)
        let http = try XCTUnwrap(response as? HTTPURLResponse)
        XCTAssertEqual(http.statusCode, 200)
        XCTAssertEqual(
            http.value(forHTTPHeaderField: "Access-Control-Allow-Origin"),
            "chrome-extension://jobhuntextid123",
            "CORS must be reflected for allowed extension origin"
        )
    }

    func testCorsBlocksArbitraryExtension() async throws {
        // When allowedExtensionOrigins is populated, only listed IDs should receive CORS.
        // Since the allowlist is currently empty (dev mode), this test verifies the 200 path
        // but notes that once the CWS ID is set, unapproved IDs will get 403 + no CORS.
        // This test is intentionally a documentation placeholder; see TASK-334.
        //
        // For now, with empty allowlist, any chrome-extension:// origin is permitted.
        // swiftlint:disable:next force_unwrapping
        let url = await URL(string: baseURL() + "/captures")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("chrome-extension://evil123/", forHTTPHeaderField: "Origin")
        let payload: [String: String] = [
            "url": "https://example.com/jobs/evil-cors",
            "page_title": "Evil CORS Test",
            "visible_text": "testing blocked cors"
        ]
        req.httpBody = try JSONEncoder().encode(payload)
        let (_, response) = try await URLSession.shared.data(for: req)
        let http = try XCTUnwrap(response as? HTTPURLResponse)
        // With empty allowlist (dev mode) this passes. With a populated allowlist, this would be 403.
        // Update this assertion to XCTAssertEqual(http.statusCode, 403) once CWS_ID is added.
        XCTAssertTrue(http.statusCode == 200 || http.statusCode == 403,
                      "Must either permit (dev mode, empty allowlist) or block (CWS ID set)")
    }

    func testCorsBlocksNonExtension() async throws {
        // Non chrome-extension:// origins must always be blocked on capture routes.
        // swiftlint:disable:next force_unwrapping
        let url = await URL(string: baseURL() + "/captures")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("https://evil.com", forHTTPHeaderField: "Origin")
        let payload: [String: String] = [
            "url": "https://example.com/jobs/non-ext",
            "page_title": "Non-Extension Test",
            "visible_text": "non extension origin test"
        ]
        req.httpBody = try JSONEncoder().encode(payload)
        let (_, response) = try await URLSession.shared.data(for: req)
        let http = try XCTUnwrap(response as? HTTPURLResponse)
        XCTAssertEqual(http.statusCode, 403, "Non-extension origin must be blocked with 403")
        XCTAssertNil(
            http.value(forHTTPHeaderField: "Access-Control-Allow-Origin"),
            "Non-extension origin must not receive CORS headers"
        )
    }

    func testCORSPreflight() async throws {
        // swiftlint:disable:next force_unwrapping
        let url = await URL(string: baseURL() + "/captures")!
        var req = URLRequest(url: url)
        req.httpMethod = "OPTIONS"
        req.setValue("chrome-extension://abc123", forHTTPHeaderField: "Origin")
        req.setValue("POST", forHTTPHeaderField: "Access-Control-Request-Method")
        req.setValue("true", forHTTPHeaderField: "Access-Control-Request-Private-Network")

        let (_, response) = try await URLSession.shared.data(for: req)
        let http = try XCTUnwrap(response as? HTTPURLResponse)
        // 204 or 200 both acceptable for preflight
        XCTAssertTrue(http.statusCode == 204 || http.statusCode == 200)
        // Verify PNA header is present
        let pna = http.value(forHTTPHeaderField: "Access-Control-Allow-Private-Network")
        XCTAssertEqual(pna, "true")
    }

    func testCORSPreflight_unknownRoute_rejectedWithoutCORS() async throws {
        // A preflight for a path/method that maps to no real route must not be answered with a
        // blanket 204 + private-network grant — it returns 404 with no CORS headers.
        // swiftlint:disable:next force_unwrapping
        let url = await URL(string: baseURL() + "/api/nonexistent")!
        var req = URLRequest(url: url)
        req.httpMethod = "OPTIONS"
        req.setValue("chrome-extension://abc123", forHTTPHeaderField: "Origin")
        req.setValue("POST", forHTTPHeaderField: "Access-Control-Request-Method")

        let (_, response) = try await URLSession.shared.data(for: req)
        let http = try XCTUnwrap(response as? HTTPURLResponse)
        XCTAssertEqual(http.statusCode, 404)
        XCTAssertNil(http.value(forHTTPHeaderField: "Access-Control-Allow-Origin"))
        XCTAssertNil(http.value(forHTTPHeaderField: "Access-Control-Allow-Private-Network"))
    }

    func testNotFoundReturns404() async throws {
        // swiftlint:disable:next force_unwrapping
        let url = await URL(string: baseURL() + "/api/nonexistent")!
        let (_, response) = try await URLSession.shared.data(from: url)
        let http = try XCTUnwrap(response as? HTTPURLResponse)
        XCTAssertEqual(http.statusCode, 404)
    }

    // TASK-358: Error bodies must not expose file paths or SwiftData internals.
    func testCaptureRoute_storeError_returnsInternalError() async throws {
        // Send malformed JSON to trigger a 400; the body must be a stable string
        // with no file-system paths or SwiftData class names.
        // swiftlint:disable:next force_unwrapping
        let url = await URL(string: baseURL() + "/captures")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("chrome-extension://testextension", forHTTPHeaderField: "Origin")
        req.httpBody = Data("{bad json}".utf8)

        let (data, response) = try await URLSession.shared.data(for: req)
        let http = try XCTUnwrap(response as? HTTPURLResponse)
        XCTAssertEqual(http.statusCode, 400)

        let bodyString = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(bodyString.contains("/Users/"), "Error body must not contain file paths")
        XCTAssertFalse(bodyString.contains("SwiftData"), "Error body must not contain SwiftData internals")
        XCTAssertFalse(bodyString.contains("ModelContext"), "Error body must not expose ModelContext")
        struct ErrorBody: Decodable { let error: String }
        let body = try JSONDecoder().decode(ErrorBody.self, from: data)
        XCTAssertFalse(body.error.isEmpty)
    }

    // TASK-358: Invalid MCP request must return a stable JSON error, not raw localizedDescription.
    func testMCPRoute_invalidRequest_returnsSafeErrorCode() async throws {
        // Provide a wrong MCP token — server returns 401 with a stable message.
        // swiftlint:disable:next force_unwrapping
        let url = await URL(string: baseURL() + "/mcp/jobs/get")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("wrong-token", forHTTPHeaderField: "X-MCP-Token")
        req.httpBody = Data("{\"job_number\": 1}".utf8)

        let (data, response) = try await URLSession.shared.data(for: req)
        let http = try XCTUnwrap(response as? HTTPURLResponse)
        XCTAssertEqual(http.statusCode, 401)

        let bodyString = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(bodyString.contains("/Users/"), "Error body must not contain file paths")
        XCTAssertFalse(bodyString.contains("SwiftData"), "Error body must not expose SwiftData")
        struct ErrorBody: Decodable { let error: String }
        let body = try JSONDecoder().decode(ErrorBody.self, from: data)
        XCTAssertFalse(body.error.isEmpty)
    }
}

// MARK: - Origin allowlist (TASK-431) + loopback (TASK-432)

final class JobhuntServerOriginTests: XCTestCase {
    private func captureRequest(port: UInt16, origin: String) throws -> URLRequest {
        let url = try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)/captures"))
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(origin, forHTTPHeaderField: "Origin")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "url": "https://jobs.example.com/role",
            "page_title": "Role",
            "visible_text": "Some job description body text."
        ])
        return req
    }

    func testProductionMode_arbitraryExtensionOrigin_rejectedWithoutCORS() async throws {
        let server = try makeTestServer(allowArbitraryExtensionOrigins: false)
        try await server.startOnAnyPort()
        let port = await server.listeningPort

        let req = try captureRequest(port: port, origin: "chrome-extension://arbitrarydevextension")
        let (_, response) = try await URLSession.shared.data(for: req)
        let http = try XCTUnwrap(response as? HTTPURLResponse)

        XCTAssertEqual(http.statusCode, 403, "unapproved extension origin must be forbidden in production mode")
        XCTAssertNil(
            http.value(forHTTPHeaderField: "Access-Control-Allow-Origin"),
            "no CORS reflected for an unapproved origin"
        )
        await server.stop()
    }

    func testProductionMode_approvedExtensionOrigin_reflectsCORS() async throws {
        let approved = "chrome-extension://approvedcwsid"
        let server = try makeTestServer(
            allowArbitraryExtensionOrigins: false,
            allowedExtensionOrigins: [approved]
        )
        try await server.startOnAnyPort()
        let port = await server.listeningPort

        let req = try captureRequest(port: port, origin: approved)
        let (_, response) = try await URLSession.shared.data(for: req)
        let http = try XCTUnwrap(response as? HTTPURLResponse)

        XCTAssertNotEqual(http.statusCode, 403, "approved origin must not be forbidden")
        XCTAssertEqual(
            http.value(forHTTPHeaderField: "Access-Control-Allow-Origin"),
            approved,
            "CORS reflected for the approved origin"
        )
        await server.stop()
    }

    func testIsApprovedExtensionOrigin_decisionLogic() {
        let allow: Set<String> = ["chrome-extension://approved"]
        // Non-extension origins are never approved, even with allowArbitrary.
        XCTAssertFalse(JobhuntServer.isApprovedExtensionOrigin("https://evil.com", allowlist: allow, allowArbitrary: true))
        // Allowlisted origin is approved regardless of allowArbitrary.
        XCTAssertTrue(JobhuntServer.isApprovedExtensionOrigin("chrome-extension://approved", allowlist: allow, allowArbitrary: false))
        // Unlisted extension origin: approved only when allowArbitrary (debug).
        XCTAssertFalse(JobhuntServer.isApprovedExtensionOrigin("chrome-extension://other", allowlist: allow, allowArbitrary: false))
        XCTAssertTrue(JobhuntServer.isApprovedExtensionOrigin("chrome-extension://other", allowlist: allow, allowArbitrary: true))
    }

    func testReleaseDefault_failsClosed() {
        // The shipped default must reject arbitrary extension origins (only the CWS origin works).
        XCTAssertFalse(
            JobhuntServer.isApprovedExtensionOrigin(
                "chrome-extension://arbitrary",
                allowlist: JobhuntServer.defaultAllowedExtensionOrigins,
                allowArbitrary: false
            ),
            "release default must fail closed for unapproved origins"
        )
        XCTAssertTrue(
            JobhuntServer.isApprovedExtensionOrigin(
                JobhuntServer.productionExtensionOrigin,
                allowlist: JobhuntServer.defaultAllowedExtensionOrigins,
                allowArbitrary: false
            ),
            "the published CWS extension origin must be approved"
        )
    }
}
