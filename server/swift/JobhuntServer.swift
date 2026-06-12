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
    // Extension sends structured_data as a JSON array; we serialize it to JSON string if
    // structured_data_json (legacy string field) is absent.
    let structuredDataArray: [AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case url
        case pageTitle = "page_title"
        case selectedText = "selected_text"
        case visibleText = "visible_text"
        case userNote = "user_note"
        case canonicalURL = "canonical_url"
        case structuredDataJSON = "structured_data_json"
        case structuredDataArray = "structured_data"
    }

    /// Returns the best available structured data as a JSON string.
    /// Prefers `structured_data_json` (legacy); falls back to serializing `structured_data` array.
    var resolvedStructuredDataJSON: String? {
        if let s = structuredDataJSON { return s }
        guard let arr = structuredDataArray, !arr.isEmpty,
              let data = try? JSONEncoder().encode(arr),
              let str = String(data: data, encoding: .utf8) else { return nil }
        return str
    }
}

/// Wrapper to decode arbitrary JSON values so `structured_data` (heterogeneous array) round-trips cleanly.
private struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) { self.value = value }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let v = try? container.decode(Bool.self) { value = v }
        else if let v = try? container.decode(Int.self) { value = v }
        else if let v = try? container.decode(Double.self) { value = v }
        else if let v = try? container.decode(String.self) { value = v }
        else if let v = try? container.decode([AnyCodable].self) { value = v.map(\.value) }
        else if let v = try? container.decode([String: AnyCodable].self) { value = v.mapValues(\.value) }
        else { value = NSNull() }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let v as Bool: try container.encode(v)
        case let v as Int: try container.encode(v)
        case let v as Double: try container.encode(v)
        case let v as String: try container.encode(v)
        case let v as [Any]: try container.encode(v.map { AnyCodable($0) })
        case let v as [String: Any]: try container.encode(v.mapValues { AnyCodable($0) })
        default: try container.encodeNil()
        }
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
    // Extension sends: site_url, site_origin, reviewed_at, next_review_at, note, page_title
    // Legacy MCP/test sends: url, page_title, interval_days
    let url: String?
    let siteURL: String?
    let siteOrigin: String?
    let pageTitle: String?
    let intervalDays: Int?
    let reviewedAt: String?
    let nextReviewAt: String?
    let note: String?

    enum CodingKeys: String, CodingKey {
        case url
        case siteURL = "site_url"
        case siteOrigin = "site_origin"
        case pageTitle = "page_title"
        case intervalDays = "interval_days"
        case reviewedAt = "reviewed_at"
        case nextReviewAt = "next_review_at"
        case note
    }

    /// Resolved URL: prefer site_url (extension), fall back to url (legacy).
    var resolvedURL: String? { siteURL ?? url }
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

    /// Try ports 8765–8769 in order, start listening on first available.
    public func start() async throws {
        guard listener == nil else { return } // already running, no-op
        let candidatePorts: [UInt16] = [8765, 8766, 8767, 8768, 8769]

        for candidate in candidatePorts {
            do {
                try await startListener(on: candidate)
                port = candidate
                return
            } catch {
                // try next port
                continue
            }
        }
        throw ServerError.noPortAvailable
    }

    public func stop() async {
        listener?.cancel()
        listener = nil
        port = 0
    }

    public var listeningPort: UInt16 {
        port
    }

    // MARK: - Private

    private func startListener(on candidatePort: UInt16) async throws {
        let params = NWParameters.tcp
        guard let nwPort = NWEndpoint.Port(rawValue: candidatePort) else {
            throw JobhuntServerError.invalidPort(candidatePort)
        }

        let listener = try NWListener(using: params, on: nwPort)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var didResume = false
            let resume: (Result<Void, Error>) -> Void = { result in
                if !didResume {
                    didResume = true
                    continuation.resume(with: result)
                }
            }

            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    resume(.success(()))
                case let .failed(error):
                    resume(.failure(error))
                case .cancelled:
                    resume(.failure(ServerError.listenerCancelled))
                default:
                    break
                }
            }

            listener.newConnectionHandler = { [weak self] connection in
                // Reject connections from non-loopback addresses
                if !Self.isLoopbackEndpoint(connection.endpoint) {
                    connection.cancel()
                    return
                }
                Task { [weak self] in
                    await self?.handleConnection(connection)
                }
            }

            listener.start(queue: .global(qos: .userInitiated))
        }

        self.listener = listener
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .userInitiated))
        receiveRequest(on: connection, accumulated: Data())
    }

    // Maximum accumulated request size. Requests exceeding this are rejected with 413
    // before parsing, preventing unbounded memory growth from local clients.
    private static let maxRequestBytes = 10 * 1024 * 1024  // 10 MB

    private func receiveRequest(on connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1_048_576) { [weak self] data, _, isComplete, _ in
            guard let self else { return }
            var buffer = accumulated
            if let data, !data.isEmpty { buffer.append(data) }

            if buffer.count > Self.maxRequestBytes {
                let response = HTTPResponse.error("Request too large", code: 413)
                self.sendResponse(response, on: connection)
                return
            }

            if !buffer.isEmpty && (isComplete || isCompleteHTTPRequest(buffer)) {
                Task { await self.processReceivedData(buffer, on: connection) }
            } else if !isComplete {
                self.receiveRequest(on: connection, accumulated: buffer)
            } else {
                connection.cancel()
            }
        }
    }

    /// Returns true when `data` contains a full HTTP request (headers + complete body per Content-Length).
    /// Uses raw byte operations so non-ASCII bodies are measured correctly.
    private func isCompleteHTTPRequest(_ data: Data) -> Bool {
        let sep = Data([13, 10, 13, 10]) // \r\n\r\n
        guard let sepRange = data.range(of: sep),
              let headerString = String(data: data[data.startIndex ..< sepRange.lowerBound], encoding: .ascii)
        else { return false }

        var contentLength = 0
        for line in headerString.components(separatedBy: "\r\n").dropFirst() {
            if let colonIdx = line.firstIndex(of: ":") {
                let key = String(line[line.startIndex ..< colonIdx]).trimmingCharacters(in: .whitespaces).lowercased()
                if key == "content-length" {
                    let val = String(line[line.index(after: colonIdx)...]).trimmingCharacters(in: .whitespaces)
                    contentLength = Int(val) ?? 0
                }
            }
        }
        guard contentLength > 0 else { return true }
        let bodyByteCount = data.distance(from: sepRange.upperBound, to: data.endIndex)
        return bodyByteCount >= contentLength
    }

    private func processReceivedData(_ data: Data, on connection: NWConnection) async {
        guard let request = parseHTTPRequest(data) else {
            let response = HTTPResponse.error("Bad request", code: 400)
            sendResponse(response, on: connection)
            return
        }

        var response = await routeRequest(request)

        // Attach CORS headers when the origin is a chrome-extension:// scheme
        let origin = request.headers["origin"] ?? ""
        if origin.hasPrefix("chrome-extension://") {
            let isPreflight = request.method == "OPTIONS"
            response = response.withCORS(origin: origin, isPreflight: isPreflight)
        }

        sendResponse(response, on: connection)
    }

    private func sendResponse(_ response: HTTPResponse, on connection: NWConnection) {
        let bytes = response.toHTTPBytes()
        connection.send(content: bytes, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func routeRequest(_ request: HTTPRequest) async -> HTTPResponse {
        // Handle OPTIONS preflight for CORS (always allowed)
        if request.method == "OPTIONS" {
            return HTTPResponse.noContent()
        }

        // MCP bridge routes (DMG builds only) — authenticated by X-MCP-Token header
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

        switch (request.method, request.path) {
        case ("GET", "/health"):
            return handleHealth()
        case ("GET", "/api/ping"):
            return handlePing()
        case ("POST", "/captures"):
            guard isExtensionOrigin(request) else { return .error("Forbidden", code: 403) }
            return await handleCapture(request)
        case ("POST", "/site-reviews"):
            guard isExtensionOrigin(request) else { return .error("Forbidden", code: 403) }
            return await handleSiteReview(request)
        case ("GET", "/api/jobs/by-url"):
            // Extension-only: used for duplicate detection before capture. Same origin gate
            // as the mutating extension routes so a non-extension local caller cannot enumerate
            // job numbers by URL.
            guard isExtensionOrigin(request) else { return .error("Forbidden", code: 403) }
            return await handleJobByURL(request)
        case ("POST", "/api/app/focus"):
            guard isExtensionOrigin(request) else { return .error("Forbidden", code: 403) }
            return await handleFocus(request)
        default:
            return HTTPResponse.error("Not found", code: 404)
        }
    }

    /// True when the request comes from a chrome-extension:// origin.
    private func isExtensionOrigin(_ request: HTTPRequest) -> Bool {
        let origin = request.headers["origin"] ?? ""
        return origin.hasPrefix("chrome-extension://")
    }

    /// True when the NWEndpoint is a loopback address (IPv4 127.0.0.1 or IPv6 ::1).
    private static func isLoopbackEndpoint(_ endpoint: NWEndpoint) -> Bool {
        guard case let .hostPort(host, _) = endpoint else { return false }
        switch host {
        case .ipv4(let addr): return addr == .loopback
        case .ipv6(let addr): return addr == .loopback
        case .name(let name, _): return name == "localhost" || name == "127.0.0.1" || name == "::1"
        @unknown default: return false
        }
    }

    // MARK: - Route handlers

    private func handleHealth() -> HTTPResponse {
        HTTPResponse.ok(HealthResponse(isOK: true))
    }

    private func handlePing() -> HTTPResponse {
        HTTPResponse.ok(PingResponse(app: "jobhunt", version: appVersion, isDemo: isDemo))
    }

    // Field-level byte limits for capture ingestion.
    private enum CaptureFieldLimit {
        static let url = 2_048
        static let pageTitle = 2_048
        static let visibleText = 500 * 1_024     // 500 KB
        static let selectedText = 500 * 1_024    // 500 KB
        static let userNote = 10 * 1_024         // 10 KB
        static let structuredDataJSON = 100 * 1_024  // 100 KB
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

        // Field byte-limit checks (utf8 byte count matches what the extension measures).
        if url.utf8.count > CaptureFieldLimit.url {
            return HTTPResponse.error("url exceeds maximum length", code: 400)
        }
        if pageTitle.utf8.count > CaptureFieldLimit.pageTitle {
            return HTTPResponse.error("page_title exceeds maximum length", code: 400)
        }
        if let vt = captureReq.visibleText, vt.utf8.count > CaptureFieldLimit.visibleText {
            return HTTPResponse.error("visible_text exceeds maximum length", code: 400)
        }
        if let st = captureReq.selectedText, st.utf8.count > CaptureFieldLimit.selectedText {
            return HTTPResponse.error("selected_text exceeds maximum length", code: 400)
        }
        if let note = captureReq.userNote, note.utf8.count > CaptureFieldLimit.userNote {
            return HTTPResponse.error("user_note exceeds maximum length", code: 400)
        }
        if let sdj = captureReq.resolvedStructuredDataJSON, sdj.utf8.count > CaptureFieldLimit.structuredDataJSON {
            return HTTPResponse.error("structured_data_json exceeds maximum length", code: 400)
        }

        let selectedTrimmed = captureReq.selectedText?.trimmingCharacters(in: .whitespaces) ?? ""
        let visibleTrimmed = captureReq.visibleText?.trimmingCharacters(in: .whitespaces) ?? ""
        if selectedTrimmed.isEmpty && visibleTrimmed.isEmpty {
            return HTTPResponse.error("visible_text or selected_text required")
        }

        let payload = CapturePayload(
            url: url,
            pageTitle: pageTitle,
            selectedText: captureReq.selectedText,
            visibleText: captureReq.visibleText,
            userNote: captureReq.userNote,
            canonicalURL: captureReq.canonicalURL,
            structuredDataJSON: captureReq.resolvedStructuredDataJSON
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
            return HTTPResponse.error(error.localizedDescription)
        }
    }

    private func handleSiteReview(_ request: HTTPRequest) async -> HTTPResponse {
        guard let reviewReq = try? request.decodeBody(as: SiteReviewRequest.self) else {
            return HTTPResponse.error("Invalid JSON body")
        }

        guard let url = reviewReq.resolvedURL?.trimmingCharacters(in: .whitespaces), !url.isEmpty else {
            return HTTPResponse.error("url required")
        }

        do {
            let siteReviewID: String
            if reviewReq.siteURL != nil {
                // Extension payload: uses explicit reviewed_at / next_review_at ISO8601 strings
                let iso = ISO8601DateFormatter()
                let reviewedAt = reviewReq.reviewedAt.flatMap { iso.date(from: $0) } ?? Date()
                let nextReviewAt = reviewReq.nextReviewAt.flatMap { iso.date(from: $0) }
                siteReviewID = try await siteService.upsertSiteReview(
                    url: url,
                    origin: reviewReq.siteOrigin,
                    title: reviewReq.pageTitle,
                    note: reviewReq.note,
                    reviewedAt: reviewedAt,
                    nextReviewAt: nextReviewAt
                )
            } else {
                // Legacy payload (interval_days)
                let rawInterval = reviewReq.intervalDays ?? 14
                guard rawInterval >= 1 && rawInterval <= 365 else {
                    return HTTPResponse.error("interval_days must be between 1 and 365", code: 400)
                }
                siteReviewID = try await siteService.upsertSiteReview(
                    url: url,
                    title: reviewReq.pageTitle,
                    intervalDays: rawInterval
                )
            }
            return HTTPResponse.ok(SiteReviewResponse(isOK: true, siteReviewID: siteReviewID))
        } catch {
            return HTTPResponse.error(error.localizedDescription)
        }
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
            return HTTPResponse.error(error.localizedDescription, code: 500)
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
}

enum JobhuntServerError: Error {
    case invalidPort(UInt16)
}
