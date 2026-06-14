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
        mcpToken: String = ""
    ) {
        self.jobService = jobService
        self.siteService = siteService
        self.appVersion = appVersion
        self.isDemo = isDemo
        #if !MAS_BUILD
            self.store = store
            self.mcpToken = mcpToken
        #endif
    }

    /// Try fixed ports 8765–8784; fall back to an OS-assigned ephemeral port.
    public func start() async throws {
        let candidatePorts: [UInt16] = Array(8765 ... 8784)

        for candidate in candidatePorts {
            do {
                try await startListener(on: candidate)
                port = candidate
                return
            } catch {
                continue
            }
        }
        // Fall back to an OS-assigned ephemeral port (port 0). This always succeeds
        // and the actual port is read back from the listener in startListener.
        try await startListener(on: 0)
    }

    /// Start on an OS-assigned ephemeral port. Suitable for tests where the exact port
    /// doesn't matter and port reuse/TIME_WAIT must be avoided.
    public func startOnAnyPort() async throws {
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
            let result = try await group.next()!
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

    // nonisolated: only touches NWConnection and spawns Tasks back onto the actor.
    // Accumulates TCP chunks until a complete HTTP request is available before processing.
    private nonisolated func receiveRequest(on connection: NWConnection, accumulated: Data = Data()) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1_048_576) { [self] data, _, isComplete, _ in
            var buffer = accumulated
            if let data, !data.isEmpty {
                buffer.append(data)
            }

            if let request = parseHTTPRequest(buffer) {
                Task {
                    await self.processRequest(request, on: connection)
                }
                return
            }

            if !isComplete, buffer.count < 2 * 1_048_576 {
                // Need more data
                self.receiveRequest(on: connection, accumulated: buffer)
            } else {
                // Connection closed or buffer too large without a parseable request
                let response = HTTPResponse.error("Bad request", code: 400)
                Task { await self.sendResponse(response, on: connection) }
            }
        }
    }

    private func processRequest(_ request: HTTPRequest, on connection: NWConnection) async {
        var response = await routeRequest(request)
        let origin = request.headers["origin"] ?? ""
        if isAllowedExtensionOrigin(origin) {
            let isPreflight = request.method == "OPTIONS"
            response = response.withCORS(origin: origin, isPreflight: isPreflight)
        }
        sendResponse(response, on: connection)
    }

    // TASK-334: Only the Jobhunt extension may receive reflected CORS headers.
    // Chrome extension IDs are assigned dynamically by the browser (no static ID in manifest.json),
    // so we maintain an explicit allowlist. To add a new approved extension ID (e.g. after
    // publishing to the Chrome Web Store), append it to this set.
    //
    // Rationale: any installed Chrome extension can forge Origin: chrome-extension://<its-id>.
    // Reflecting CORS for all chrome-extension:// origins would let any extension call capture
    // routes. The allowlist ensures only the known Jobhunt extension(s) can.
    //
    // While the allowlist is empty (pre-CWS-publish), all chrome-extension:// origins are
    // permitted so development/test flows work. Once a CWS ID is assigned, add it here and
    // remove the fallback by making the empty-set branch return false.
    //
    // Production CWS ID: add "chrome-extension://<CWS_ID>" here after publishing.
    private static let allowedExtensionOrigins: Set<String> = [
        // "chrome-extension://REPLACE_WITH_CWS_ID"
    ]

    /// True when `origin` is an allowed Jobhunt extension origin.
    private func isAllowedExtensionOrigin(_ origin: String) -> Bool {
        guard origin.hasPrefix("chrome-extension://") else { return false }
        // If the allowlist is populated, require an exact match.
        if !Self.allowedExtensionOrigins.isEmpty {
            return Self.allowedExtensionOrigins.contains(origin)
        }
        // Allowlist is empty (no CWS ID assigned yet): permit any chrome-extension:// origin.
        return true
    }

    private func sendResponse(_ response: HTTPResponse, on connection: NWConnection) {
        let bytes = response.toHTTPBytes()
        connection.send(content: bytes, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func routeRequest(_ request: HTTPRequest) async -> HTTPResponse {
        // Handle OPTIONS preflight for CORS
        if request.method == "OPTIONS" {
            return HTTPResponse.noContent()
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

        // The extension sends JSON-LD/Greenhouse data as a `structured_data` array; the
        // typed CaptureRequest only sees the pre-stringified `structured_data_json`. When the
        // latter is absent, serialize the array from the raw body so it reaches extraction.
        var structuredJSON = captureReq.structuredDataJSON
        if structuredJSON == nil,
           let body = request.body,
           let obj = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
           let arr = obj["structured_data"], !(arr is NSNull),
           let data = try? JSONSerialization.data(withJSONObject: arr) {
            structuredJSON = String(data: data, encoding: .utf8)
        }

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
