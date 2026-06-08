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
    let url: String
    let pageTitle: String?
    let intervalDays: Int?

    enum CodingKeys: String, CodingKey {
        case url
        case pageTitle = "page_title"
        case intervalDays = "interval_days"
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

    /// Try ports 8765–8769 in order, start listening on first available.
    public func start() async throws {
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
        receiveRequest(on: connection)
    }

    private func receiveRequest(on connection: NWConnection) {
        // Read up to 1MB of data
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1_048_576) { [weak self] data, _, isComplete, _ in
            guard let self else { return }
            if let data, !data.isEmpty {
                Task {
                    await self.processReceivedData(data, on: connection)
                }
            } else if !isComplete {
                // If we didn't get data and it's not complete, try reading more
                receiveRequest(on: connection)
            } else {
                connection.cancel()
            }
        }
    }

    private func processReceivedData(_ data: Data, on connection: NWConnection) async {
        guard let request = parseHTTPRequest(data) else {
            let response = HTTPResponse.error("Bad request", code: 400)
            sendResponse(response, on: connection)
            return
        }

        let response = await routeRequest(request)
        sendResponse(response, on: connection)
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

        switch (request.method, request.path) {
        case ("GET", "/health"):
            return handleHealth()
        case ("GET", "/api/ping"):
            return handlePing()
        case ("POST", "/captures"):
            return await handleCapture(request)
        case ("POST", "/site-reviews"):
            return await handleSiteReview(request)
        case ("GET", "/api/jobs/by-url"):
            return await handleJobByURL(request)
        case ("POST", "/api/app/focus"):
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

        let payload = CapturePayload(
            url: url,
            pageTitle: pageTitle,
            selectedText: captureReq.selectedText,
            visibleText: captureReq.visibleText,
            userNote: captureReq.userNote,
            canonicalURL: captureReq.canonicalURL,
            structuredDataJSON: captureReq.structuredDataJSON
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

        let url = reviewReq.url.trimmingCharacters(in: .whitespaces)
        if url.isEmpty {
            return HTTPResponse.error("url required")
        }

        let intervalDays = reviewReq.intervalDays ?? 14

        do {
            let siteReviewID = try await siteService.upsertSiteReview(
                url: url,
                title: reviewReq.pageTitle,
                intervalDays: intervalDays
            )
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
