import Foundation
import Network

/// A minimal localhost HTTP/1.1 server that speaks the OpenAI-compatible API (`/v1/chat/completions`
/// and `/v1/models`), returning deterministic canned responses from `MockLLMResponder`. Point an
/// OpenAI-compatible provider (LM Studio / Custom) at `baseURL` to exercise the real
/// provider → transport → parse inference path with no API key.
///
/// Test-support only (compiled into CoreTests / AppUITests). Binds an ephemeral port on 127.0.0.1.
final class MockLLMServer {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "mock-llm-server")
    private(set) var port: UInt16 = 0

    init() throws {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        // Bind loopback only — this is a test fixture, not a public service.
        params.requiredInterfaceType = .loopback
        listener = try NWListener(using: params, on: .any)
    }

    var baseURL: String {
        "http://127.0.0.1:\(port)"
    }

    /// Start listening and block until the OS has assigned a port (so `baseURL` is usable on return).
    func start(timeout: TimeInterval = 5) throws {
        let ready = DispatchSemaphore(value: 0)
        var startError: Error?
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready: ready.signal()
            case let .failed(error): startError = error; ready.signal()
            default: break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in self?.handle(connection) }
        listener.start(queue: queue)

        guard ready.wait(timeout: .now() + timeout) == .success else {
            throw MockLLMServerError.startTimedOut
        }
        if let startError { throw startError }
        guard let assigned = listener.port?.rawValue else { throw MockLLMServerError.noPort }
        port = assigned
    }

    func stop() {
        listener.cancel()
    }

    // MARK: - Connection handling

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(connection, buffer: Data())
    }

    private func receive(_ connection: NWConnection, buffer: Data) {
        connection
            .receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { [weak self] data, _, isComplete, error in
                guard let self else { connection.cancel(); return }
                var accumulated = buffer
                if let data { accumulated.append(data) }

                if let request = Self.parse(accumulated) {
                    let response = httpResponse(for: request)
                    connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
                } else if isComplete || error != nil {
                    connection.cancel()
                } else {
                    receive(connection, buffer: accumulated) // headers/body not complete yet
                }
            }
    }

    // MARK: - Routing

    private func httpResponse(for request: ParsedRequest) -> Data {
        let bodyString: String
        switch (request.method, request.path) {
        case ("POST", "/v1/chat/completions"):
            bodyString = MockLLMResponder.chatCompletion(requestBody: request.body)
        case ("GET", "/v1/models"):
            bodyString = MockLLMResponder.models()
        default:
            return Self.rawResponse(status: "404 Not Found", body: "{\"error\":\"not found\"}")
        }
        return Self.rawResponse(status: "200 OK", body: bodyString)
    }

    private static func rawResponse(status: String, body: String) -> Data {
        let bodyData = Data(body.utf8)
        let headers = "HTTP/1.1 \(status)\r\n"
            + "Content-Type: application/json\r\n"
            + "Content-Length: \(bodyData.count)\r\n"
            + "Connection: close\r\n\r\n"
        return Data(headers.utf8) + bodyData
    }

    // MARK: - Request parsing

    private struct ParsedRequest {
        let method: String
        let path: String
        let body: Data
    }

    /// Returns a parsed request once headers AND the full Content-Length body have arrived, else nil
    /// (caller keeps reading). Mirrors the accumulate-until-complete approach in JobhuntServer.
    private static func parse(_ buffer: Data) -> ParsedRequest? {
        let separator = Data("\r\n\r\n".utf8)
        guard let headerEnd = buffer.range(of: separator) else { return nil }
        let headerData = buffer[buffer.startIndex ..< headerEnd.lowerBound]
        guard let headerText = String(data: headerData, encoding: .utf8) else { return nil }

        let lines = headerText.components(separatedBy: "\r\n")
        let requestLine = lines.first?.components(separatedBy: " ") ?? []
        guard requestLine.count >= 2 else { return nil }
        let method = requestLine[0]
        let path = requestLine[1]

        var contentLength = 0
        for line in lines.dropFirst() where line.lowercased().hasPrefix("content-length:") {
            contentLength = Int(line.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)) ?? 0
        }

        let bodyStart = headerEnd.upperBound
        let available = buffer.distance(from: bodyStart, to: buffer.endIndex)
        guard available >= contentLength else { return nil } // body not fully arrived
        let body = Data(buffer[bodyStart ..< buffer.index(bodyStart, offsetBy: contentLength)])
        return ParsedRequest(method: method, path: path, body: body)
    }
}

enum MockLLMServerError: Error {
    case startTimedOut
    case noPort
}
