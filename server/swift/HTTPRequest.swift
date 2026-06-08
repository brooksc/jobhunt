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

/// Parse raw HTTP request bytes into an HTTPRequest.
/// Returns nil if the request is malformed or incomplete.
func parseHTTPRequest(_ data: Data) -> HTTPRequest? {
    guard let raw = String(data: data, encoding: .utf8) else { return nil }

    // Split headers from body on \r\n\r\n
    guard let headerBodySep = raw.range(of: "\r\n\r\n") else { return nil }
    let headerSection = String(raw[raw.startIndex ..< headerBodySep.lowerBound])
    let bodyStart = headerBodySep.upperBound

    var lines = headerSection.components(separatedBy: "\r\n")
    guard !lines.isEmpty else { return nil }

    let requestLine = lines.removeFirst()
    let parts = requestLine.split(separator: " ", maxSplits: 2).map(String.init)
    guard parts.count >= 2 else { return nil }

    let method = parts[0]
    let rawTarget = parts[1]

    // Parse path and query from request target
    var path = rawTarget
    var queryItems: [URLQueryItem] = []
    if let qIdx = rawTarget.firstIndex(of: "?") {
        path = String(rawTarget[rawTarget.startIndex ..< qIdx])
        let queryString = String(rawTarget[rawTarget.index(after: qIdx)...])
        let components = URLComponents(string: "http://x?\(queryString)")
        queryItems = components?.queryItems ?? []
    }

    // Parse headers into a [String: String] dict (lowercased keys)
    var headers: [String: String] = [:]
    for line in lines {
        if let colonIdx = line.firstIndex(of: ":") {
            let key = String(line[line.startIndex ..< colonIdx]).trimmingCharacters(in: .whitespaces).lowercased()
            let value = String(line[line.index(after: colonIdx)...]).trimmingCharacters(in: .whitespaces)
            headers[key] = value
        }
    }

    // Extract body based on Content-Length
    var bodyData: Data?
    if let contentLengthStr = headers["content-length"],
       let contentLength = Int(contentLengthStr),
       contentLength > 0 {
        let bodyString = String(raw[bodyStart...])
        if let bodyBytes = bodyString.data(using: .utf8) {
            bodyData = bodyBytes.prefix(contentLength)
        }
    }

    return HTTPRequest(
        method: method,
        path: path,
        queryItems: queryItems,
        headers: headers,
        body: bodyData
    )
}
