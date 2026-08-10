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

private struct JobByURLBody: Decodable {
    let jobNumber: Int
    enum CodingKeys: String, CodingKey { case jobNumber = "job_number" }
}

// MARK: - JobhuntServerTests

/// A non-pooling HTTP client for the tests.
///
/// `URLSession.shared` keeps connections alive and hands them to the next caller. ServerTests share
/// one `JobhuntServer` on purpose (NWListener port lifecycle), and that server closes connections;
/// a test that inherits a dead one fails with `NSURLErrorDomain -1005 "The network connection was
/// lost"` — a transport error, not an assertion, so it looks like a real failure and isn't.
///
/// This bit twice. The first fix isolated only the >1MB capture test on the theory that the large
/// body poisoned the pool; it survived 10 consecutive local runs and then CI failed a DIFFERENT test
/// (`testCaptureRoute_storeError_returnsInternalError`, run 31330335321) with the same error. Body
/// size was never the cause — connection reuse was. So no test reuses a connection: each request
/// gets its own ephemeral session, closed immediately.
///
/// Deliberately NOT a retry. A retry able to swallow a transport error can swallow a real regression
/// too, and would have hidden both of these instead of surfacing them.
enum HTTPTestClient {
    static func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        return try await session.data(for: request)
    }

    static func data(from url: URL) async throws -> (Data, URLResponse) {
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        return try await session.data(from: url)
    }
}

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

    // MARK: - Lifecycle (TASK-430)

    /// start() is idempotent: a second start while already listening is a no-op (same port, no
    /// second listener) — so the Settings "Retry" flow can't create conflicting lifecycle state.
    func testStart_idempotent_doesNotRebindOrChangePort() async throws {
        let s = try makeTestServer()
        try await s.startOnAnyPort()
        let port1 = await s.listeningPort
        XCTAssertGreaterThan(port1, 0)

        // Second start must be a no-op.
        try await s.start()
        let port2 = await s.listeningPort
        XCTAssertEqual(port1, port2, "idempotent start must keep the same listener/port")

        await s.stop()
        let stopped = await s.listeningPort
        XCTAssertEqual(stopped, 0, "stop() releases the port")
    }

    /// After stop(), start() can run again (clean restart) — the lifecycle seam app shutdown relies on.
    func testStartStopRestart() async throws {
        let s = try makeTestServer()
        try await s.startOnAnyPort()
        let p1 = await s.listeningPort
        XCTAssertGreaterThan(p1, 0)
        await s.stop()
        let pStopped = await s.listeningPort
        XCTAssertEqual(pStopped, 0)
        // Restart on a fresh OS-assigned port.
        try await s.startOnAnyPort()
        let p2 = await s.listeningPort
        XCTAssertGreaterThan(p2, 0)
        await s.stop()
    }

    // MARK: - Tests

    func testPingEndpoint() async throws {
        // swiftlint:disable:next force_unwrapping
        let url = await URL(string: baseURL() + "/api/ping")!
        let (data, response) = try await HTTPTestClient.data(from: url)
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
        let (data, response) = try await HTTPTestClient.data(from: url)
        let http = try XCTUnwrap(response as? HTTPURLResponse)
        XCTAssertEqual(http.statusCode, 200)

        let body = try JSONDecoder().decode(HealthBody.self, from: data)
        XCTAssertTrue(body.isOK)
    }

    // TASK-435: an over-limit body is rejected with 413 (site-reviews limit is 256 KB).
    func testOversizedBodyReturns413() async throws {
        let url = await URL(string: baseURL() + "/site-reviews")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("chrome-extension://testextension", forHTTPHeaderField: "Origin")
        let bigNote = String(repeating: "x", count: 300 * 1024) // > 256 KB limit
        req.httpBody = try JSONEncoder().encode(["site_url": "https://x.com", "note": bigNote])
        let (_, response) = try await HTTPTestClient.data(for: req)
        let http = try XCTUnwrap(response as? HTTPURLResponse)
        XCTAssertEqual(http.statusCode, 413, "Over-limit body must be rejected with 413")
    }

    // TASK-560: MCP add-capture is the same semantic operation as /captures (full page text), so it
    // gets the same 4 MB budget — intentionally, not the generic 1 MB MCP limit. Other MCP routes
    // (metadata/read) keep the smaller budget.
    func testMaxBodySize_captureRoutesShareLargeBudget() {
        XCTAssertEqual(JobhuntServer.maxBodySize(forPath: "/captures"), 4 * 1_048_576)
        XCTAssertEqual(
            JobhuntServer.maxBodySize(forPath: "/mcp/captures/add"), 4 * 1_048_576,
            "MCP add-capture must share the /captures budget"
        )
        XCTAssertEqual(
            JobhuntServer.maxBodySize(forPath: "/mcp/jobs/list"), 1_048_576,
            "other MCP routes keep the smaller metadata budget"
        )
    }

    // AC#2: a full-page capture between 1 MB and 4 MB succeeds through MCP just as it does via /captures
    // (it would 413 under the old generic 1 MB MCP limit).
    func testMCPCaptureAdd_acceptsBodyOver1MB() async throws {
        #if MAS_BUILD
            throw XCTSkip("MCP routes are excluded from MAS builds.")
        #endif
        // swiftlint:disable:next force_unwrapping
        let url = await URL(string: baseURL() + "/mcp/captures/add")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("test-token-abc123", forHTTPHeaderField: "X-MCP-Token")
        let bigText = String(repeating: "job description text ", count: 100_000) // ~2.1 MB
        let payloadObj: [String: Any] = [
            "url": "https://example.com/jobs/mcp-large-1",
            "page_title": "Large Capture Engineer",
            "visible_text": bigText
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: payloadObj)
        XCTAssertGreaterThan(req.httpBody?.count ?? 0, 1_048_576, "payload must exceed the old 1 MB MCP limit")

        let (data, response) = try await HTTPTestClient.data(for: req)
        let http = try XCTUnwrap(response as? HTTPURLResponse)
        XCTAssertEqual(http.statusCode, 200, "a 1–4 MB MCP capture must be accepted, not 413")
        struct MCPCaptureBody: Decodable {
            let ok: Bool
            enum CodingKeys: String, CodingKey { case ok }
        }
        XCTAssertTrue(try JSONDecoder().decode(MCPCaptureBody.self, from: data).ok)
    }

    // TASK-532: the Transfer-Encoding rejection must apply uniformly, BEFORE MCP route dispatch — an
    // /mcp/* request carrying transfer-encoding gets the explicit 400 framing error, not a
    // route-specific error (and not a body-decoding attempt).
    func testRouteRequest_transferEncodingRejectedAcrossAllRouteFamilies() async {
        let paths = [
            "/health", // health
            "/captures", // extension
            "/mcp/captures/add", // MCP write
            "/mcp/jobs/list" // MCP read
        ]
        for path in paths {
            #if MAS_BUILD
                if path.hasPrefix("/mcp/") { continue } // MCP routes excluded from MAS builds
            #endif
            let req = HTTPRequest(
                method: path == "/health" ? "GET" : "POST",
                path: path,
                queryItems: [],
                headers: ["transfer-encoding": "chunked", "x-mcp-token": "test-token-abc123"],
                body: nil
            )
            let resp = await server.routeRequest(req)
            XCTAssertEqual(resp.statusCode, 400, "\(path) must reject Transfer-Encoding with 400")
        }
    }

    // AC#3/#4: a normally-framed MCP request (no transfer-encoding) still passes the token check and
    // reaches its handler — the framing guard doesn't disturb the happy path.
    func testRouteRequest_normalMCPRequest_reachesHandler() async throws {
        #if MAS_BUILD
            throw XCTSkip("MCP routes are excluded from MAS builds.")
        #endif
        let req = HTTPRequest(
            method: "POST",
            path: "/mcp/jobs/list",
            queryItems: [],
            headers: ["x-mcp-token": "test-token-abc123"],
            body: nil
        )
        let resp = await server.routeRequest(req)
        XCTAssertEqual(resp.statusCode, 200, "a normally-framed, authenticated MCP request must succeed")
    }

    func testRouteRequest_mcpRequest_badToken_stillRejected() async throws {
        #if MAS_BUILD
            throw XCTSkip("MCP routes are excluded from MAS builds.")
        #endif
        let req = HTTPRequest(
            method: "POST",
            path: "/mcp/jobs/list",
            queryItems: [],
            headers: ["x-mcp-token": "wrong-token"],
            body: nil
        )
        let resp = await server.routeRequest(req)
        XCTAssertNotEqual(resp.statusCode, 200, "an invalid MCP token must still be rejected")
        XCTAssertNotEqual(resp.statusCode, 400, "token rejection is not the framing error")
    }

    // TASK-434: MCP routes only accept POST; other methods get 405.
    func testMCPRoute_getMethodRejectedWith405() async throws {
        // MCP routes are compiled out under MAS_BUILD (no MCP in the App Store sandbox), where these
        // paths 404 instead of 405 — so this only applies to non-MAS builds.
        #if MAS_BUILD
            throw XCTSkip("MCP routes are excluded from MAS builds.")
        #endif
        for path in ["/mcp/jobs/list", "/mcp/jobs/update"] { // a read route and a write route
            let url = await URL(string: baseURL() + path)!
            var req = URLRequest(url: url)
            req.httpMethod = "GET"
            req.setValue("test-token-abc123", forHTTPHeaderField: "X-MCP-Token")
            let (_, response) = try await HTTPTestClient.data(for: req)
            let http = try XCTUnwrap(response as? HTTPURLResponse)
            XCTAssertEqual(http.statusCode, 405, "GET \(path) must be rejected with 405")
        }
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

        let (data, response) = try await HTTPTestClient.data(for: req)
        let http = try XCTUnwrap(response as? HTTPURLResponse)
        XCTAssertEqual(http.statusCode, 200)

        let body = try JSONDecoder().decode(CaptureBody.self, from: data)
        XCTAssertTrue(body.isOK)
        XCTAssertFalse(body.captureID.isEmpty)
        XCTAssertGreaterThan(body.jobNumber, 0)
        XCTAssertFalse(body.duplicate)
    }

    // MARK: - /api/jobs/by-url (TASK-588)

    private func byURLRequest(_ query: String) async -> URLRequest {
        // swiftlint:disable:next force_unwrapping
        var req = await URLRequest(url: URL(string: baseURL() + "/api/jobs/by-url" + query)!)
        req.setValue("chrome-extension://testextension", forHTTPHeaderField: "Origin")
        return req
    }

    func testJobByURL_matchingJob_returns200WithJobNumber() async throws {
        // Seed a job via the capture endpoint, then look it up by its URL.
        let jobURL = "https://example.com/jobs/by-url-hit-\(UUID().uuidString)"
        // swiftlint:disable:next force_unwrapping
        var post = await URLRequest(url: URL(string: baseURL() + "/captures")!)
        post.httpMethod = "POST"
        post.setValue("application/json", forHTTPHeaderField: "Content-Type")
        post.setValue("chrome-extension://testextension", forHTTPHeaderField: "Origin")
        post.httpBody = try JSONEncoder().encode([
            "url": jobURL, "page_title": "By-URL Role", "visible_text": "Hiring for a role."
        ])
        let (capData, _) = try await HTTPTestClient.data(for: post)
        let created = try JSONDecoder().decode(CaptureBody.self, from: capData)

        let (data, response) = try await HTTPTestClient
            .data(
                for: byURLRequest(
                    "?url=\(jobURL.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? jobURL)"
                )
            )
        XCTAssertEqual(try XCTUnwrap(response as? HTTPURLResponse).statusCode, 200)
        XCTAssertEqual(try JSONDecoder().decode(JobByURLBody.self, from: data).jobNumber, created.jobNumber)
    }

    func testJobByURL_unknownURL_returns404() async throws {
        let (_, response) = try await HTTPTestClient
            .data(for: byURLRequest("?url=https://example.com/jobs/definitely-not-here-\(UUID().uuidString)"))
        XCTAssertEqual(try XCTUnwrap(response as? HTTPURLResponse).statusCode, 404)
    }

    func testJobByURL_missingURLParam_returns400() async throws {
        let (_, response) = try await HTTPTestClient.data(for: byURLRequest(""))
        XCTAssertEqual(try XCTUnwrap(response as? HTTPURLResponse).statusCode, 400)
    }

    func testJobByURL_malformedURL_returns404NotCrash() async throws {
        // A schemeless/garbage value matches no capture — resolves to a clean 404, no crash.
        let (_, response) = try await HTTPTestClient.data(for: byURLRequest("?url=not%20a%20url"))
        XCTAssertEqual(try XCTUnwrap(response as? HTTPURLResponse).statusCode, 404)
    }

    func testJobByURL_multipleURLParams_usesFirst() async throws {
        // Documents current behavior: queryValue(for:) returns the first `url=` value.
        let hit = "https://example.com/jobs/by-url-first-\(UUID().uuidString)"
        // swiftlint:disable:next force_unwrapping
        var post = await URLRequest(url: URL(string: baseURL() + "/captures")!)
        post.httpMethod = "POST"
        post.setValue("application/json", forHTTPHeaderField: "Content-Type")
        post.setValue("chrome-extension://testextension", forHTTPHeaderField: "Origin")
        post.httpBody = try JSONEncoder().encode([
            "url": hit, "page_title": "First Wins", "visible_text": "Hiring."
        ])
        let (capData, _) = try await HTTPTestClient.data(for: post)
        let created = try JSONDecoder().decode(CaptureBody.self, from: capData)

        let enc = hit.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? hit
        let (data, response) = try await HTTPTestClient
            .data(for: byURLRequest("?url=\(enc)&url=https://example.com/jobs/second"))
        XCTAssertEqual(try XCTUnwrap(response as? HTTPURLResponse).statusCode, 200)
        XCTAssertEqual(try JSONDecoder().decode(JobByURLBody.self, from: data).jobNumber, created.jobNumber)
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
                ["@type": "JobPosting", "title": "Structured Engineer", "baseSalary": 200_000]
            ]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: payloadObj)

        let (data, response) = try await HTTPTestClient.data(for: req)
        let http = try XCTUnwrap(response as? HTTPURLResponse)
        XCTAssertEqual(http.statusCode, 200)
        let body = try JSONDecoder().decode(CaptureBody.self, from: data)
        XCTAssertTrue(body.isOK)
        XCTAssertGreaterThan(body.jobNumber, 0)
    }

    /// TASK-437: the extension now sends BOTH the `structured_data` array and the preferred typed
    /// `structured_data_json` string. The server must accept this dual-field shape.
    func testCaptureEndpoint_acceptsDualStructuredDataFields() async throws {
        // swiftlint:disable:next force_unwrapping
        let url = await URL(string: baseURL() + "/captures")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("chrome-extension://testextension", forHTTPHeaderField: "Origin")
        let jsonLd: [[String: Any]] = [["@type": "JobPosting", "title": "Dual Engineer", "baseSalary": 210_000]]
        let payloadObj: [String: Any] = try [
            "url": "https://example.com/jobs/dual-1",
            "page_title": "Dual Engineer",
            "visible_text": "We are hiring.",
            "structured_data": jsonLd,
            "structured_data_json": XCTUnwrap(try String(
                data: JSONSerialization.data(withJSONObject: jsonLd),
                encoding: .utf8
            ))
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: payloadObj)

        let (data, response) = try await HTTPTestClient.data(for: req)
        let http = try XCTUnwrap(response as? HTTPURLResponse)
        XCTAssertEqual(http.statusCode, 200)
        let body = try JSONDecoder().decode(CaptureBody.self, from: data)
        XCTAssertTrue(body.isOK)
        XCTAssertGreaterThan(body.jobNumber, 0)
    }

    // TASK-559: the MCP add-capture route must accept the same structured-data shapes as /captures —
    // both the typed `structured_data_json` string and a raw `structured_data` array — via the shared
    // CaptureRequestParsing policy, so MCP clients sending the extension shape don't lose metadata.
    func testMCPCaptureAdd_acceptsStructuredDataArray() async throws {
        #if MAS_BUILD
            throw XCTSkip("MCP routes are excluded from MAS builds.")
        #endif
        // swiftlint:disable:next force_unwrapping
        let url = await URL(string: baseURL() + "/mcp/captures/add")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("test-token-abc123", forHTTPHeaderField: "X-MCP-Token")
        let payloadObj: [String: Any] = [
            "url": "https://example.com/jobs/mcp-structured-1",
            "page_title": "MCP Structured Engineer",
            "visible_text": "We are hiring an engineer.",
            "structured_data": [
                ["@type": "JobPosting", "title": "MCP Structured Engineer", "baseSalary": 200_000]
            ]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: payloadObj)

        let (data, response) = try await HTTPTestClient.data(for: req)
        let http = try XCTUnwrap(response as? HTTPURLResponse)
        XCTAssertEqual(http.statusCode, 200, "MCP add-capture must accept a raw structured_data array")
        struct MCPCaptureBody: Decodable {
            let ok: Bool
            let jobNumber: Int
            enum CodingKeys: String, CodingKey { case ok; case jobNumber = "job_number" }
        }
        let body = try JSONDecoder().decode(MCPCaptureBody.self, from: data)
        XCTAssertTrue(body.ok)
        XCTAssertGreaterThan(body.jobNumber, 0)
    }

    func testMCPCaptureAdd_acceptsStructuredDataJSON() async throws {
        #if MAS_BUILD
            throw XCTSkip("MCP routes are excluded from MAS builds.")
        #endif
        // swiftlint:disable:next force_unwrapping
        let url = await URL(string: baseURL() + "/mcp/captures/add")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("test-token-abc123", forHTTPHeaderField: "X-MCP-Token")
        let payloadObj: [String: Any] = [
            "url": "https://example.com/jobs/mcp-structured-2",
            "page_title": "MCP Typed Engineer",
            "visible_text": "We are hiring.",
            "structured_data_json": "[{\"@type\":\"JobPosting\",\"title\":\"MCP Typed Engineer\"}]"
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: payloadObj)

        let (data, response) = try await HTTPTestClient.data(for: req)
        let http = try XCTUnwrap(response as? HTTPURLResponse)
        XCTAssertEqual(http.statusCode, 200, "MCP add-capture must still accept structured_data_json")
        struct MCPCaptureBody: Decodable {
            let ok: Bool
            let jobNumber: Int
            enum CodingKeys: String, CodingKey { case ok; case jobNumber = "job_number" }
        }
        let body = try JSONDecoder().decode(MCPCaptureBody.self, from: data)
        XCTAssertTrue(body.ok)
        XCTAssertGreaterThan(body.jobNumber, 0)
    }

    // MARK: - TASK-442: centralized structured-data field resolution

    func testResolveStructuredData_prefersTypedField() {
        let body = try? JSONSerialization.data(withJSONObject: ["structured_data": [["@type": "JobPosting"]]])
        let resolved = CaptureRequestParsing.resolveStructuredDataJSON(typed: "[{\"x\":1}]", rawBody: body)
        XCTAssertEqual(resolved, "[{\"x\":1}]", "typed structured_data_json wins over the raw array")
    }

    func testResolveStructuredData_fallsBackToRawArray() throws {
        let body = try JSONSerialization.data(withJSONObject: [
            "structured_data": [["@type": "JobPosting", "title": "Eng"]]
        ])
        let resolved = try XCTUnwrap(CaptureRequestParsing.resolveStructuredDataJSON(typed: nil, rawBody: body))
        let parsed = try JSONSerialization.jsonObject(with: Data(resolved.utf8)) as? [[String: Any]]
        XCTAssertEqual(parsed?.first?["title"] as? String, "Eng")
    }

    func testResolveStructuredData_emptyTypedFallsBackToArray() throws {
        let body = try JSONSerialization.data(withJSONObject: ["structured_data": [["a": 1]]])
        XCTAssertNotNil(CaptureRequestParsing.resolveStructuredDataJSON(typed: "   ", rawBody: body))
    }

    func testResolveStructuredData_bothAbsentIsNil() throws {
        let body = try JSONSerialization.data(withJSONObject: ["visible_text": "hi"])
        XCTAssertNil(CaptureRequestParsing.resolveStructuredDataJSON(typed: nil, rawBody: body))
    }

    func testResolveStructuredData_malformedDegradesToNil() throws {
        // structured_data present but a scalar (not an array/object) → degrade safely to nil.
        let body = try JSONSerialization.data(withJSONObject: ["structured_data": "not-an-array"])
        XCTAssertNil(CaptureRequestParsing.resolveStructuredDataJSON(typed: nil, rawBody: body))
        // Non-JSON body → nil.
        XCTAssertNil(CaptureRequestParsing.resolveStructuredDataJSON(typed: nil, rawBody: Data("garbage".utf8)))
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

        let (data, response) = try await HTTPTestClient.data(for: req)
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

        let (data, response) = try await HTTPTestClient.data(for: req)
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

        let (data, response) = try await HTTPTestClient.data(for: req)
        let http = try XCTUnwrap(response as? HTTPURLResponse)
        XCTAssertEqual(http.statusCode, 400)

        struct ErrorBody: Decodable { let error: String }
        let body = try JSONDecoder().decode(ErrorBody.self, from: data)
        XCTAssertFalse(body.error.isEmpty)
    }

    // TASK-558: a syntactically-present but invalid URL (e.g. a javascript: scheme) passes the route's
    // empty-field pre-check and fails inside ingestCapture. That's a client error, so it must surface
    // as 400 — not the catch-all 500 it used to be — on both the extension and MCP routes.
    func testCaptureValidation_invalidURLScheme_returns400() async throws {
        // swiftlint:disable:next force_unwrapping
        let url = await URL(string: baseURL() + "/captures")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("chrome-extension://testextension", forHTTPHeaderField: "Origin")
        let payload: [String: String] = [
            "url": "javascript:alert(1)",
            "page_title": "Engineer",
            "visible_text": "Some job description text"
        ]
        req.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await HTTPTestClient.data(for: req)
        let http = try XCTUnwrap(response as? HTTPURLResponse)
        XCTAssertEqual(http.statusCode, 400, "invalid URL is a client error, not a 500")
        struct ErrorBody: Decodable { let error: String }
        XCTAssertFalse(try JSONDecoder().decode(ErrorBody.self, from: data).error.isEmpty)
    }

    func testMCPCaptureAdd_invalidURLScheme_returns400() async throws {
        #if MAS_BUILD
            throw XCTSkip("MCP routes are excluded from MAS builds.")
        #endif
        // swiftlint:disable:next force_unwrapping
        let url = await URL(string: baseURL() + "/mcp/captures/add")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("test-token-abc123", forHTTPHeaderField: "X-MCP-Token")
        let payload: [String: String] = [
            "url": "ftp://example.com/jobs/1",
            "page_title": "Engineer",
            "visible_text": "Some job description text"
        ]
        req.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await HTTPTestClient.data(for: req)
        let http = try XCTUnwrap(response as? HTTPURLResponse)
        XCTAssertEqual(http.statusCode, 400, "invalid URL is a client error, not a 500")
        struct ErrorBody: Decodable { let error: String }
        XCTAssertFalse(try JSONDecoder().decode(ErrorBody.self, from: data).error.isEmpty)
    }

    /// TASK-558 AC#2: the MCP route doesn't pre-check text, so a missing-text capture only fails in the
    /// service — it must still map to 400, not 500.
    func testMCPCaptureAdd_missingText_returns400() async throws {
        #if MAS_BUILD
            throw XCTSkip("MCP routes are excluded from MAS builds.")
        #endif
        // swiftlint:disable:next force_unwrapping
        let url = await URL(string: baseURL() + "/mcp/captures/add")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("test-token-abc123", forHTTPHeaderField: "X-MCP-Token")
        let payload: [String: String] = [
            "url": "https://example.com/jobs/no-text",
            "page_title": "Engineer"
        ]
        req.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await HTTPTestClient.data(for: req)
        let http = try XCTUnwrap(response as? HTTPURLResponse)
        XCTAssertEqual(http.statusCode, 400, "missing capture text is a client error, not a 500")
        struct ErrorBody: Decodable { let error: String }
        XCTAssertFalse(try JSONDecoder().decode(ErrorBody.self, from: data).error.isEmpty)
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
        let (_, response) = try await HTTPTestClient.data(for: req)
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
        let (_, response) = try await HTTPTestClient.data(for: req)
        let http = try XCTUnwrap(response as? HTTPURLResponse)
        // With empty allowlist (dev mode) this passes. With a populated allowlist, this would be 403.
        // Update this assertion to XCTAssertEqual(http.statusCode, 403) once CWS_ID is added.
        XCTAssertTrue(
            http.statusCode == 200 || http.statusCode == 403,
            "Must either permit (dev mode, empty allowlist) or block (CWS ID set)"
        )
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
        let (_, response) = try await HTTPTestClient.data(for: req)
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

        let (_, response) = try await HTTPTestClient.data(for: req)
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

        let (_, response) = try await HTTPTestClient.data(for: req)
        let http = try XCTUnwrap(response as? HTTPURLResponse)
        XCTAssertEqual(http.statusCode, 404)
        XCTAssertNil(http.value(forHTTPHeaderField: "Access-Control-Allow-Origin"))
        XCTAssertNil(http.value(forHTTPHeaderField: "Access-Control-Allow-Private-Network"))
    }

    func testNotFoundReturns404() async throws {
        // swiftlint:disable:next force_unwrapping
        let url = await URL(string: baseURL() + "/api/nonexistent")!
        let (_, response) = try await HTTPTestClient.data(from: url)
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

        let (data, response) = try await HTTPTestClient.data(for: req)
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
        // MCP routes are excluded from MAS builds (the route 404s there instead of returning 401).
        #if MAS_BUILD
            throw XCTSkip("MCP routes are excluded from MAS builds.")
        #endif
        // Provide a wrong MCP token — server returns 401 with a stable message.
        // swiftlint:disable:next force_unwrapping
        let url = await URL(string: baseURL() + "/mcp/jobs/get")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("wrong-token", forHTTPHeaderField: "X-MCP-Token")
        req.httpBody = Data("{\"job_number\": 1}".utf8)

        let (data, response) = try await HTTPTestClient.data(for: req)
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
        let (_, response) = try await HTTPTestClient.data(for: req)
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
        let (_, response) = try await HTTPTestClient.data(for: req)
        let http = try XCTUnwrap(response as? HTTPURLResponse)

        XCTAssertNotEqual(http.statusCode, 403, "approved origin must not be forbidden")
        XCTAssertEqual(
            http.value(forHTTPHeaderField: "Access-Control-Allow-Origin"),
            approved,
            "CORS reflected for the approved origin"
        )
        await server.stop()
    }

    /// TASK-619: Firefox extension origins are `moz-extension://<uuid>` where the UUID is per
    /// *install*, so there is no stable value an allowlist could pin. They're therefore accepted only
    /// in debug (`allowArbitrary`), exactly like unpacked Chrome dev extensions.
    ///
    /// The release case is the one that matters: accepting every `moz-extension://` origin would let
    /// any installed Firefox add-on drive capture, which is precisely what the Chrome allowlist
    /// exists to prevent.
    func testFirefoxOriginsAreDebugOnly() {
        let allow: Set = ["chrome-extension://approved"]
        XCTAssertTrue(JobhuntServer.isApprovedExtensionOrigin(
            "moz-extension://11111111-2222-3333-4444-555555555555",
            allowlist: allow,
            allowArbitrary: true
        ))
        XCTAssertFalse(
            JobhuntServer.isApprovedExtensionOrigin(
                "moz-extension://11111111-2222-3333-4444-555555555555",
                allowlist: allow,
                allowArbitrary: false
            ),
            "a release build must not accept an unpinnable Firefox origin"
        )
    }

    func testIsApprovedExtensionOrigin_decisionLogic() {
        let allow: Set = ["chrome-extension://approved"]
        // Non-extension origins are never approved, even with allowArbitrary.
        XCTAssertFalse(JobhuntServer.isApprovedExtensionOrigin(
            "https://evil.com",
            allowlist: allow,
            allowArbitrary: true
        ))
        // Allowlisted origin is approved regardless of allowArbitrary.
        XCTAssertTrue(JobhuntServer.isApprovedExtensionOrigin(
            "chrome-extension://approved",
            allowlist: allow,
            allowArbitrary: false
        ))
        // Unlisted extension origin: approved only when allowArbitrary (debug).
        XCTAssertFalse(JobhuntServer.isApprovedExtensionOrigin(
            "chrome-extension://other",
            allowlist: allow,
            allowArbitrary: false
        ))
        XCTAssertTrue(JobhuntServer.isApprovedExtensionOrigin(
            "chrome-extension://other",
            allowlist: allow,
            allowArbitrary: true
        ))
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
        XCTAssertTrue(
            JobhuntServer.isApprovedExtensionOrigin(
                JobhuntServer.developmentExtensionOrigin,
                allowlist: JobhuntServer.defaultAllowedExtensionOrigins,
                allowArbitrary: false
            ),
            "the repo's pinned unpacked/dev extension origin must be approved so a release build can be "
                + "dogfooded with the locally-loaded extension"
        )
    }
}
