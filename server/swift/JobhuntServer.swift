import Foundation
import JobhuntCore
import Network
import SwiftData

// MARK: - Request/Response Codable types

private struct PingResponse: Encodable {
    let app: String
    let version: String
    let isDemo: Bool
}

private struct HealthResponse: Encodable {
    let isOK: Bool

    enum CodingKeys: String, CodingKey {
        case isOK = "ok"
    }
}

private struct CaptureRequest: Decodable {
    let url: String
    let pageTitle: String
    let selectedText: String?
    let visibleText: String?
    let userNote: String?
    let canonicalURL: String?
    let structuredDataJSON: String?

    enum CodingKeys: String, CodingKey {
        case url
        case pageTitle = "page_title"
        case selectedText = "selected_text"
        case visibleText = "visible_text"
        case userNote = "user_note"
        case canonicalURL = "canonical_url"
        case structuredDataJSON = "structured_data_json"
    }
}

private struct CaptureResponse: Encodable {
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

private struct SiteReviewRequest: Decodable {
    // The Chrome extension sends `site_url` + reviewed_at/next_review_at/note/site_origin.
    // The in-app / legacy path sends `url` + interval_days. Accept both.
    let url: String?
    let siteURL: String?
    let siteOrigin: String?
    let pageTitle: String?
    let note: String?
    let reviewedAt: String?
    let nextReviewAt: String?
    let intervalDays: Int?

    enum CodingKeys: String, CodingKey {
        case url
        case siteURL = "site_url"
        case siteOrigin = "site_origin"
        case pageTitle = "page_title"
        case note
        case reviewedAt = "reviewed_at"
        case nextReviewAt = "next_review_at"
        case intervalDays = "interval_days"
    }

    /// Prefer the extension's `site_url`, fall back to the legacy `url`.
    var resolvedURL: String? {
        if let s = siteURL, !s.isEmpty { return s }
        if let u = url, !u.isEmpty { return u }
        return nil
    }

    /// True when the body carries the richer extension fields (reviewed_at / next_review_at / note / origin).
    var hasExtensionFields: Bool {
        reviewedAt != nil || nextReviewAt != nil || note != nil || siteOrigin != nil || siteURL != nil
    }
}

private struct SiteReviewResponse: Encodable {
    let isOK: Bool
    let siteReviewID: String

    enum CodingKeys: String, CodingKey {
        case isOK = "ok"
        case siteReviewID = "site_review_id"
    }
}

private struct JobByURLResponse: Encodable {
    let jobNumber: Int

    enum CodingKeys: String, CodingKey {
        case jobNumber = "job_number"
    }
}

private struct FocusRequest: Decodable {
    let jobNumber: Int?

    enum CodingKeys: String, CodingKey {
        case jobNumber = "job_number"
    }
}

private struct FocusResponse: Encodable {
    let isOK: Bool

    enum CodingKeys: String, CodingKey {
        case isOK = "ok"
    }
}

// MARK: - JobhuntServer

public actor JobhuntServer {
    public private(set) var port: UInt16 = 0
    private var listener: NWListener?
    private let jobService: JobService
    private let siteService: SiteService
    private let appVersion: String
    private let isDemo: Bool
    /// Chrome-extension origins that may use the extension routes and receive reflected CORS.
    private let allowedExtensionOrigins: Set<String>
    /// When true, any `chrome-extension://` origin is permitted (for locally-loaded unpacked dev
    /// extensions, which get a different ID than the published one). Defaults to true only in DEBUG
    /// builds; release builds fail closed.
    private let allowArbitraryExtensionOrigins: Bool
    #if !MAS_BUILD
        private let store: BackgroundStore
        private let mcpToken: String
    #endif

    public init(
        jobService: JobService,
        siteService: SiteService,
        appVersion: String = "1.0.0",
        isDemo: Bool = false,
        store: BackgroundStore,
        mcpToken: String = "",
        allowedExtensionOrigins: Set<String> = JobhuntServer.defaultAllowedExtensionOrigins,
        allowArbitraryExtensionOrigins: Bool = JobhuntServer.defaultAllowArbitraryExtensionOrigins
    ) {
        self.jobService = jobService
        self.siteService = siteService
        self.appVersion = appVersion
        self.isDemo = isDemo
        self.allowedExtensionOrigins = allowedExtensionOrigins
        self.allowArbitraryExtensionOrigins = allowArbitraryExtensionOrigins
        #if !MAS_BUILD
            self.store = store
            self.mcpToken = mcpToken
        #endif
    }

    /// Bind one of the shared `ServerPortContract.discoveryPorts` (8765–8769). There is NO ephemeral
    /// fallback in production (TASK-433): an OS-assigned port is undiscoverable by the extension/MCP
    /// helper, so if every contract port is taken this throws `ServerError.noPortAvailable` and the
    /// failure is surfaced in Settings → Local Server (with Retry) rather than running on a port no
    /// client can find.
    ///
    /// Idempotent: if a listener is already bound this is a no-op, so the Settings "Retry" flow can't
    /// bind a second conflicting listener (TASK-430). A failed start leaves `listener == nil`, so a
    /// retry after failure still proceeds.
    public func start() async throws {
        guard listener == nil else { return }

        for candidate in ServerPortContract.discoveryPorts {
            do {
                try await startListener(on: candidate)
                port = candidate
                return
            } catch {
                continue
            }
        }
        throw ServerError.noPortAvailable
    }

    /// Start on an OS-assigned ephemeral port. Suitable for tests where the exact port
    /// doesn't matter and port reuse/TIME_WAIT must be avoided.
    public func startOnAnyPort() async throws {
        guard listener == nil else { return }
        try await startListener(on: 0)
    }

    public func stop() async {
        guard let l = listener else { return }
        // Wait for the listener to reach .cancelled state so the OS port is released
        // before returning — prevents the next test's server from getting a RST.
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            var didResume = false
            l.stateUpdateHandler = { state in
                if case .cancelled = state, !didResume {
                    didResume = true
                    continuation.resume()
                }
            }
            l.cancel()
        }
        listener = nil
        port = 0
    }

    public var listeningPort: UInt16 {
        port
    }

    // MARK: - Private

    private func startListener(on candidatePort: UInt16) async throws {
        let params = NWParameters.tcp
        // Bind to the loopback interface only. This is a localhost-only companion server; binding
        // loopback means non-loopback peers cannot connect at the OS networking boundary (no LAN
        // exposure), rather than relying on client behavior or route-level checks. Loopback clients
        // (the Chrome extension and MCP helper, both via 127.0.0.1) are unaffected.
        // Verify externally with e.g. `nc <this-machine-LAN-IP> <port>` — the connection is refused.
        params.requiredInterfaceType = .loopback
        // candidatePort == 0 lets the OS assign an ephemeral port (used in tests).
        let nwPort: NWEndpoint.Port = candidatePort == 0 ? .any : {
            guard let p = NWEndpoint.Port(rawValue: candidatePort) else { return .any }
            return p
        }()

        let listener = try NWListener(using: params, on: nwPort)

        // Continuation carries the actual bound port so we read it inside the .ready callback,
        // where NWListener.port is guaranteed to be set.
        // A 3-second timeout guards against NWListener staying in .waiting forever
        // (observed when nw_path_create_evaluator fails in test environments).
        let boundPort: UInt16 = try await withThrowingTaskGroup(of: UInt16.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<UInt16, Error>) in
                    var didResume = false
                    let resume: (Result<UInt16, Error>) -> Void = { result in
                        if !didResume {
                            didResume = true
                            continuation.resume(with: result)
                        }
                    }

                    listener.stateUpdateHandler = { state in
                        switch state {
                        case .ready:
                            let actual = listener.port?.rawValue ?? candidatePort
                            resume(.success(actual))
                        case let .failed(error):
                            resume(.failure(error))
                        case .cancelled:
                            resume(.failure(ServerError.listenerCancelled))
                        case .waiting:
                            // .waiting means the port is temporarily unavailable — treat as failure
                            // so the caller can try the next candidate port.
                            resume(.failure(ServerError.listenerWaiting))
                        default:
                            break
                        }
                    }

                    listener.newConnectionHandler = { [weak self] connection in
                        Task { [weak self] in
                            await self?.handleConnection(connection)
                        }
                    }

                    listener.start(queue: .global(qos: .userInitiated))
                }
            }
            group.addTask {
                try await Task.sleep(nanoseconds: 3_000_000_000) // 3-second timeout
                listener.cancel()
                throw ServerError.listenerTimeout
            }
            guard let result = try await group.next() else {
                group.cancelAll()
                throw ServerError.listenerTimeout
            }
            group.cancelAll()
            return result
        }

        self.listener = listener
        if boundPort != 0 {
            port = boundPort
        }
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .userInitiated))
        receiveRequest(on: connection)
    }

    /// Maximum request body size per route (TASK-435). Captures carry full visible page text so
    /// they get the largest budget; site-reviews are tiny metadata; MCP payloads are moderate;
    /// everything else is small. Oversized requests are rejected with 413 before the body is read.
    static func maxBodySize(forPath path: String) -> Int {
        switch path {
        case "/captures": return 4 * 1_048_576 // 4 MB — full page text
        case "/site-reviews": return 256 * 1024 // 256 KB
        case _ where path.hasPrefix("/mcp/"): return 1_048_576 // 1 MB
        default: return 64 * 1024 // 64 KB (health/ping/by-url/focus)
        }
    }

    /// Header-block size cap (TASK-533). 64 KB is far above any legitimate request's headers and
    /// bounds resource use from a slow/malformed local client before the body is read.
    static let maxHeaderBytes = 64 * 1024

    // nonisolated: only touches NWConnection and spawns Tasks back onto the actor.
    // Accumulates TCP chunks until a complete HTTP request is available before processing.
    private nonisolated func receiveRequest(on connection: NWConnection, accumulated: Data = Data()) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1_048_576) { [self] data, _, isComplete, _ in
            var buffer = accumulated
            if let data, !data.isEmpty {
                buffer.append(data)
            }

            func reject(_ reason: String, _ code: Int) {
                Task { await self.sendResponse(HTTPResponse.error(reason, code: code), on: connection) }
            }
            func readMoreOrFail() {
                if !isComplete, buffer.count < 2 * 1_048_576 {
                    receiveRequest(on: connection, accumulated: buffer)
                } else {
                    reject("Bad request", 400)
                }
            }

            // Validate framing (header size + Content-Length) before routing — fail closed (TASK-533).
            switch inspectRequestFraming(buffer, maxHeaderBytes: Self.maxHeaderBytes) {
            case .incomplete:
                readMoreOrFail()
            case let .invalid(reason, code):
                reject(reason, code)
            case let .valid(_, path, contentLength):
                // TASK-435: reject an over-limit body early (by Content-Length) with 413.
                let limit = Self.maxBodySize(forPath: path)
                if contentLength > limit {
                    reject("Request body too large (\(contentLength) bytes; limit \(limit))", 413)
                    return
                }
                if let request = parseHTTPRequest(buffer) {
                    Task { await self.processRequest(request, on: connection) }
                } else {
                    // Headers framed but the body bytes haven't all arrived yet — keep reading.
                    readMoreOrFail()
                }
            }
        }
    }

    private func processRequest(_ request: HTTPRequest, on connection: NWConnection) async {
        var response = await routeRequest(request)
        let origin = request.headers["origin"] ?? ""
        let isPreflight = request.method == "OPTIONS"
        // Don't reflect CORS for a rejected preflight (unknown route → 404): a preflight only
        // earns CORS + private-network when it resolved to a real route (204).
        let preflightRejected = isPreflight && response.statusCode != 204
        if isAllowedExtensionOrigin(origin), !preflightRejected {
            response = response.withCORS(origin: origin, isPreflight: isPreflight)
        }
        sendResponse(response, on: connection)
    }

    // TASK-334 / TASK-431: Only approved Jobhunt extension origins may use the extension routes and
    // receive reflected CORS headers. Any installed Chrome extension can forge
    // `Origin: chrome-extension://<its-id>`, so reflecting CORS / authorizing routes for all
    // chrome-extension:// origins would let any extension drive capture/site-review/job-lookup/focus.
    //
    // The default allowlist is the published Chrome Web Store extension ("jobhunt-capture"). To
    // approve another build (e.g. a new CWS listing), add its `chrome-extension://<id>` origin via
    // the `allowedExtensionOrigins` init parameter or here.
    //
    // Locally-loaded *unpacked* dev extensions get a different, machine-specific ID, so debug builds
    // permit any chrome-extension:// origin via `allowArbitraryExtensionOrigins`. Release builds set
    // this to false and therefore fail closed — only the configured CWS origin is accepted.
    //
    // Published CWS extension ID (from chromewebstore.google.com/detail/jobhunt-capture/<id>).
    public static let productionExtensionOrigin = "chrome-extension://jekcbebhfeidkpapienoflbcaeeknlch"

    /// The repo's unpacked/dev extension, pinned to this stable id by the `key` in
    /// extension/manifest.json (whose matching public key hashes to this id). Allowlisted so a RELEASE
    /// build can be dogfooded with the locally-loaded extension without a settings toggle. The `key` is
    /// stripped from the published CWS zip (scripts/package-extension.sh), so the Web Store copy keeps
    /// its own id and this dev id only ever matches an unpacked load of this repo. Low-risk by design:
    /// the worst a forged-id extension can do over loopback is inject job captures / focus the app
    /// (no route exposes job content, résumés, or keys), and the published id is already clonable.
    public static let developmentExtensionOrigin = "chrome-extension://jbgompgalchfnhooogpblmfecocehdci"

    public static let defaultAllowedExtensionOrigins: Set<String> = [
        productionExtensionOrigin,
        developmentExtensionOrigin
    ]

    /// Permit arbitrary chrome-extension origins only in debug builds — never in release.
    public static var defaultAllowArbitraryExtensionOrigins: Bool {
        #if DEBUG
            return true
        #else
            return false
        #endif
    }

    /// Pure decision used by both the route guard and CORS reflection. Approves `origin` if it is a
    /// chrome-extension origin that is explicitly allowlisted, or — only when `allowArbitrary` —
    /// any chrome-extension origin. Non-extension origins are never approved here.
    static func isApprovedExtensionOrigin(
        _ origin: String,
        allowlist: Set<String>,
        allowArbitrary: Bool
    ) -> Bool {
        guard origin.hasPrefix("chrome-extension://") else { return false }
        if allowlist.contains(origin) { return true }
        return allowArbitrary
    }

    /// True when `origin` is an allowed Jobhunt extension origin for this server instance.
    private func isAllowedExtensionOrigin(_ origin: String) -> Bool {
        Self.isApprovedExtensionOrigin(
            origin,
            allowlist: allowedExtensionOrigins,
            allowArbitrary: allowArbitraryExtensionOrigins
        )
    }

    private func sendResponse(_ response: HTTPResponse, on connection: NWConnection) {
        let bytes = response.toHTTPBytes()
        connection.send(content: bytes, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    /// True when a non-OPTIONS (method, path) pair maps to a real route. Used to gate the
    /// CORS preflight so OPTIONS for an unknown route/method isn't answered with a blanket 204
    /// (which would advertise "any method, any path, private-network OK" to the browser).
    private func isKnownRoute(method: String, path: String) -> Bool {
        switch (method, path) {
        case ("GET", "/health"),
             ("GET", "/api/ping"),
             ("POST", "/captures"),
             ("POST", "/site-reviews"),
             ("GET", "/api/jobs/by-url"),
             ("POST", "/api/app/focus"):
            return true
        default:
            return false
        }
    }

    private func routeRequest(_ request: HTTPRequest) async -> HTTPResponse {
        // Answer a CORS preflight only when it targets a real route+method; otherwise 404 with
        // no CORS, so the preflight reflects the actual route table rather than a blanket allow.
        if request.method == "OPTIONS" {
            let requestedMethod = request.headers["access-control-request-method"] ?? ""
            if isKnownRoute(method: requestedMethod, path: request.path) {
                return HTTPResponse.noContent()
            }
            return HTTPResponse.error("Not found", code: 404)
        }

        // MCP bridge routes (DMG builds only)
        #if !MAS_BUILD
            if request.path.hasPrefix("/mcp/") {
                if let response = await routeMCPRequest(
                    request,
                    jobService: jobService,
                    siteService: siteService,
                    store: store,
                    mcpToken: mcpToken
                ) {
                    return response
                }
            }
        #endif

        // TASK-478: the request parser only frames bodies by Content-Length. A request using
        // Transfer-Encoding (e.g. chunked) would otherwise parse with an empty body and the POST
        // handlers would misreport it as invalid JSON. Reject it explicitly as unsupported.
        if request.headers["transfer-encoding"] != nil {
            return HTTPResponse.error("Transfer-Encoding is not supported; send a Content-Length body.", code: 400)
        }

        let origin = request.headers["origin"] ?? ""
        let fromExtension = isAllowedExtensionOrigin(origin)

        switch (request.method, request.path) {
        case ("GET", "/health"):
            return handleHealth()
        case ("GET", "/api/ping"):
            return handlePing()
        case ("POST", "/captures"):
            guard fromExtension else { return .error("Forbidden", code: 403) }
            return await handleCapture(request)
        case ("POST", "/site-reviews"):
            guard fromExtension else { return .error("Forbidden", code: 403) }
            return await handleSiteReview(request)
        case ("GET", "/api/jobs/by-url"):
            guard fromExtension else { return .error("Forbidden", code: 403) }
            return await handleJobByURL(request)
        case ("POST", "/api/app/focus"):
            guard fromExtension else { return .error("Forbidden", code: 403) }
            return await handleFocus(request)
        default:
            return HTTPResponse.error("Not found", code: 404)
        }
    }

    // MARK: - Route handlers

    private func handleHealth() -> HTTPResponse {
        HTTPResponse.ok(HealthResponse(isOK: true))
    }

    private func handlePing() -> HTTPResponse {
        HTTPResponse.ok(PingResponse(app: "jobhunt", version: appVersion, isDemo: isDemo))
    }

    private func handleCapture(_ request: HTTPRequest) async -> HTTPResponse {
        guard let captureReq = try? request.decodeBody(as: CaptureRequest.self) else {
            return HTTPResponse.error("Invalid JSON body")
        }

        let url = captureReq.url.trimmingCharacters(in: .whitespaces)
        let pageTitle = captureReq.pageTitle.trimmingCharacters(in: .whitespaces)

        if url.isEmpty {
            return HTTPResponse.error("url and page_title required")
        }
        if pageTitle.isEmpty {
            return HTTPResponse.error("url and page_title required")
        }

        let selectedTrimmed = captureReq.selectedText?.trimmingCharacters(in: .whitespaces) ?? ""
        let visibleTrimmed = captureReq.visibleText?.trimmingCharacters(in: .whitespaces) ?? ""
        if selectedTrimmed.isEmpty && visibleTrimmed.isEmpty {
            return HTTPResponse.error("visible_text or selected_text required")
        }

        // Resolve structured data from either the typed `structured_data_json` field or the
        // extension's raw `structured_data` array — one shared policy (TASK-442).
        let structuredJSON = CaptureRequestParsing.resolveStructuredDataJSON(
            typed: captureReq.structuredDataJSON, rawBody: request.body
        )

        let payload = CapturePayload(
            url: url,
            pageTitle: pageTitle,
            selectedText: captureReq.selectedText,
            visibleText: captureReq.visibleText,
            userNote: captureReq.userNote,
            canonicalURL: captureReq.canonicalURL,
            structuredDataJSON: structuredJSON
        )

        do {
            let result = try await jobService.ingestCapture(payload)
            return HTTPResponse.ok(CaptureResponse(
                isOK: true,
                captureID: result.captureID,
                jobNumber: result.jobNumber,
                duplicate: result.isDuplicate
            ))
        } catch {
            return HTTPResponse.error(safeServerError(error, context: "handleCapture"), code: 500)
        }
    }

    private func handleSiteReview(_ request: HTTPRequest) async -> HTTPResponse {
        guard let reviewReq = try? request.decodeBody(as: SiteReviewRequest.self),
              let resolved = reviewReq.resolvedURL?.trimmingCharacters(in: .whitespaces),
              !resolved.isEmpty else {
            return HTTPResponse.error("url required")
        }

        do {
            let siteReviewID: String
            if reviewReq.hasExtensionFields {
                // Rich extension payload: honor explicit reviewed_at / next_review_at / note / origin.
                siteReviewID = try await siteService.upsertSiteReview(
                    url: resolved,
                    origin: reviewReq.siteOrigin,
                    title: reviewReq.pageTitle,
                    note: reviewReq.note,
                    reviewedAt: Self.parseISODate(reviewReq.reviewedAt) ?? Date(),
                    nextReviewAt: Self.parseISODate(reviewReq.nextReviewAt)
                )
            } else {
                // Legacy / in-app payload: interval-based.
                siteReviewID = try await siteService.upsertSiteReview(
                    url: resolved,
                    title: reviewReq.pageTitle,
                    intervalDays: reviewReq.intervalDays ?? 14
                )
            }
            return HTTPResponse.ok(SiteReviewResponse(isOK: true, siteReviewID: siteReviewID))
        } catch {
            return HTTPResponse.error(safeServerError(error, context: "handleSiteReview"), code: 500)
        }
    }

    /// Parse an ISO-8601 timestamp (with or without fractional seconds) from the extension.
    private static func parseISODate(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = withFraction.date(from: raw) { return d }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: raw)
    }

    private func handleJobByURL(_ request: HTTPRequest) async -> HTTPResponse {
        guard let url = request.queryValue(for: "url"), !url.isEmpty else {
            return HTTPResponse.error("url required")
        }

        // Use JobService to find a job by URL via capture URL lookup
        do {
            let jobNumber = try await findJobNumber(byURL: url)
            if let jobNumber {
                return HTTPResponse.ok(JobByURLResponse(jobNumber: jobNumber))
            } else {
                return HTTPResponse.error("not found", code: 404)
            }
        } catch {
            return HTTPResponse.error(safeServerError(error, context: "handleJobByURL"), code: 500)
        }
    }

    private func findJobNumber(byURL url: String) async throws -> Int? {
        // We use the jobService's store via a workaround — fetch all captures and find matching URL
        // This is done by delegating to a helper on the service
        try await jobService.findJobNumber(byURL: url)
    }

    private func handleFocus(_ request: HTTPRequest) async -> HTTPResponse {
        let focusReq = try? request.decodeBody(as: FocusRequest.self)
        let jobNumber = focusReq?.jobNumber

        let userInfo: [AnyHashable: Any] = if let jobNumber {
            ["jobNumber": jobNumber]
        } else {
            [:]
        }

        NotificationCenter.default.post(
            name: Notification.Name("JobhuntFocusRequest"),
            object: nil,
            userInfo: userInfo
        )

        return HTTPResponse.ok(FocusResponse(isOK: true))
    }
}

// MARK: - ServerError

enum ServerError: Error {
    case noPortAvailable
    case listenerCancelled
    case listenerWaiting
    case listenerTimeout
}

enum JobhuntServerError: Error {
    case invalidPort(UInt16)
}
