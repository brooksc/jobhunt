import Foundation

struct HTTPRequest {
    let method: String
    let path: String
    let queryItems: [URLQueryItem]
    let headers: [String: String]
    let body: Data?

    func queryValue(for name: String) -> String? {
        queryItems.first { $0.name == name }?.value
    }

    func decodeBody<T: Decodable>(as type: T.Type) throws -> T {
        guard let data = body else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: [], debugDescription: "Empty body")
            )
        }
        return try JSONDecoder().decode(type, from: data)
    }
}

/// Peek the request target path and declared Content-Length once the header block is complete,
/// WITHOUT waiting for the body. Used to reject oversized requests early (TASK-435) before
/// accumulating the whole body. Returns nil if the header terminator hasn't arrived yet.
func peekRequestHeaders(_ data: Data) -> (path: String, contentLength: Int)? {
    let sepBytes = Data([13, 10, 13, 10]) // \r\n\r\n
    guard let sepRange = data.range(of: sepBytes),
          let headerString = String(data: data[data.startIndex ..< sepRange.lowerBound], encoding: .ascii)
    else { return nil }
    var lines = headerString.components(separatedBy: "\r\n")
    guard !lines.isEmpty else { return nil }
    let requestLine = lines.removeFirst()
    let parts = requestLine.split(separator: " ", maxSplits: 2).map(String.init)
    guard parts.count >= 2 else { return nil }
    let rawTarget = parts[1]
    let path = rawTarget.firstIndex(of: "?").map { String(rawTarget[rawTarget.startIndex ..< $0]) } ?? rawTarget
    var contentLength = 0
    for line in lines {
        if let colonIdx = line.firstIndex(of: ":") {
            let key = String(line[line.startIndex ..< colonIdx]).trimmingCharacters(in: .whitespaces).lowercased()
            if key == "content-length" {
                contentLength = Int(String(line[line.index(after: colonIdx)...]).trimmingCharacters(in: .whitespaces)) ?? 0
            }
        }
    }
    return (path, contentLength)
}

/// Parse raw HTTP request bytes into an HTTPRequest.
/// Returns nil if the request is malformed or incomplete.
/// Body is sliced from the original Data using Content-Length as a byte count,
/// so non-ASCII (e.g. UTF-8 multi-byte) JSON bodies are never truncated.
func parseHTTPRequest(_ data: Data) -> HTTPRequest? {
    // Locate the header/body separator as raw bytes — never convert the body to String first.
    let sepBytes = Data([13, 10, 13, 10]) // \r\n\r\n
    guard let sepRange = data.range(of: sepBytes) else { return nil }

    // HTTP headers are always ASCII; body encoding is determined by Content-Type.
    guard let headerString = String(data: data[data.startIndex ..< sepRange.lowerBound], encoding: .ascii)
    else { return nil }

    var lines = headerString.components(separatedBy: "\r\n")
    guard !lines.isEmpty else { return nil }

    let requestLine = lines.removeFirst()
    let parts = requestLine.split(separator: " ", maxSplits: 2).map(String.init)
    guard parts.count >= 2 else { return nil }

    let method = parts[0]
    let rawTarget = parts[1]

    var path = rawTarget
    var queryItems: [URLQueryItem] = []
    if let qIdx = rawTarget.firstIndex(of: "?") {
        path = String(rawTarget[rawTarget.startIndex ..< qIdx])
        let queryString = String(rawTarget[rawTarget.index(after: qIdx)...])
        let components = URLComponents(string: "http://x?\(queryString)")
        queryItems = components?.queryItems ?? []
    }

    var headers: [String: String] = [:]
    for line in lines {
        if let colonIdx = line.firstIndex(of: ":") {
            let key = String(line[line.startIndex ..< colonIdx]).trimmingCharacters(in: .whitespaces).lowercased()
            let value = String(line[line.index(after: colonIdx)...]).trimmingCharacters(in: .whitespaces)
            headers[key] = value
        }
    }

    // Slice body from raw Data using Content-Length as a byte count (not character count).
    // Return nil if body bytes haven't fully arrived yet — caller should read more data.
    var bodyData: Data?
    let bodyStart = sepRange.upperBound
    if let contentLengthStr = headers["content-length"],
       let contentLength = Int(contentLengthStr),
       contentLength > 0 {
        let bodyBytesAvailable = bodyStart <= data.endIndex ? (data.endIndex - bodyStart) : 0
        guard bodyBytesAvailable >= contentLength else { return nil }
        bodyData = Data(data[bodyStart...].prefix(contentLength))
    }

    return HTTPRequest(method: method, path: path, queryItems: queryItems, headers: headers, body: bodyData)
}
