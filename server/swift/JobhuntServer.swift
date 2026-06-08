import Foundation
import Network
import JobhuntCore

// MARK: - Request/Response Codable types

private struct PingResponse: Encodable {
    let app: String
    let version: String
    let isDemo: Bool
}

private struct HealthResponse: Encodable {
    let ok: Bool
}

private struct CaptureRequest: Decodable {
    let url: String
    let page_title: String
    let selected_text: String?
    let visible_text: String?
    let user_note: String?
    let canonical_url: String?
    let structured_data_json: String?
}

private struct CaptureResponse: Encodable {
    let ok: Bool
    let capture_id: String
    let job_number: Int
    let duplicate: Bool
}

private struct SiteReviewRequest: Decodable {
    let url: String
    let page_title: String?
    let interval_days: Int?
}

private struct SiteReviewResponse: Encodable {
    let ok: Bool
    let site_review_id: String
}

private struct JobByURLResponse: Encodable {
    let job_number: Int
}

private struct FocusRequest: Decodable {
    let job_number: Int?
}

private struct FocusResponse: Encodable {
    let ok: Bool
}

// MARK: - JobhuntServer

public actor JobhuntServer {
    public private(set) var port: UInt16 = 0
    private var listener: NWListener?
    private let jobService: JobService
    private let siteService: SiteService
    private let appVersion: String
    private let isDemo: Bool

    public init(
        jobService: JobService,
        siteService: SiteService,
        appVersion: String = "1.0.0",
        isDemo: Bool = false
    ) {
        self.jobService = jobService
        self.siteService = siteService
        self.appVersion = appVersion
        self.isDemo = isDemo
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

    public var listeningPort: UInt16 { port }

    // MARK: - Private

    private func startListener(on candidatePort: UInt16) async throws {
        let params = NWParameters.tcp
        let nwPort = NWEndpoint.Port(rawValue: candidatePort)!

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
                case .failed(let error):
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
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1_048_576) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                Task {
                    await self.processReceivedData(data, on: connection)
                }
            } else if !isComplete {
                // If we didn't get data and it's not complete, try reading more
                self.receiveRequest(on: connection)
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
        HTTPResponse.ok(HealthResponse(ok: true))
    }

    private func handlePing() -> HTTPResponse {
        HTTPResponse.ok(PingResponse(app: "jobhunt", version: appVersion, isDemo: isDemo))
    }

    private func handleCapture(_ request: HTTPRequest) async -> HTTPResponse {
        guard let captureReq = try? request.decodeBody(as: CaptureRequest.self) else {
            return HTTPResponse.error("Invalid JSON body")
        }

        let url = captureReq.url.trimmingCharacters(in: .whitespaces)
        let pageTitle = captureReq.page_title.trimmingCharacters(in: .whitespaces)

        if url.isEmpty {
            return HTTPResponse.error("url and page_title required")
        }
        if pageTitle.isEmpty {
            return HTTPResponse.error("url and page_title required")
        }

        let selectedTrimmed = captureReq.selected_text?.trimmingCharacters(in: .whitespaces) ?? ""
        let visibleTrimmed = captureReq.visible_text?.trimmingCharacters(in: .whitespaces) ?? ""
        if selectedTrimmed.isEmpty && visibleTrimmed.isEmpty {
            return HTTPResponse.error("visible_text or selected_text required")
        }

        let payload = CapturePayload(
            url: url,
            pageTitle: pageTitle,
            selectedText: captureReq.selected_text,
            visibleText: captureReq.visible_text,
            userNote: captureReq.user_note,
            canonicalURL: captureReq.canonical_url,
            structuredDataJSON: captureReq.structured_data_json
        )

        do {
            let result = try await jobService.ingestCapture(payload)
            return HTTPResponse.ok(CaptureResponse(
                ok: true,
                capture_id: result.captureID,
                job_number: result.jobNumber,
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

        let intervalDays = reviewReq.interval_days ?? 14

        do {
            let siteReviewID = try await siteService.upsertSiteReview(
                url: url,
                title: reviewReq.page_title,
                intervalDays: intervalDays
            )
            return HTTPResponse.ok(SiteReviewResponse(ok: true, site_review_id: siteReviewID))
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
                return HTTPResponse.ok(JobByURLResponse(job_number: jobNumber))
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
        return try await jobService.findJobNumber(byURL: url)
    }

    private func handleFocus(_ request: HTTPRequest) async -> HTTPResponse {
        let focusReq = try? request.decodeBody(as: FocusRequest.self)
        let jobNumber = focusReq?.job_number

        let userInfo: [AnyHashable: Any]
        if let jobNumber {
            userInfo = ["jobNumber": jobNumber]
        } else {
            userInfo = [:]
        }

        NotificationCenter.default.post(
            name: Notification.Name("JobhuntFocusRequest"),
            object: nil,
            userInfo: userInfo
        )

        return HTTPResponse.ok(FocusResponse(ok: true))
    }
}

// MARK: - ServerError

enum ServerError: Error {
    case noPortAvailable
    case listenerCancelled
}
