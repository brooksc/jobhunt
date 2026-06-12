import Foundation

struct HTTPResponse {
    let statusCode: Int
    let headers: [String: String]
    let body: Data

    static func ok(_ value: some Encodable) -> HTTPResponse {
        let encoder = JSONEncoder()
        let data = (try? encoder.encode(value)) ?? Data("{}".utf8)
        return HTTPResponse(
            statusCode: 200,
            headers: ["Content-Type": "application/json"],
            body: data
        )
    }

    static func error(_ message: String, code: Int = 400) -> HTTPResponse {
        struct ErrorBody: Encodable { let error: String }
        let data = (try? JSONEncoder().encode(ErrorBody(error: message))) ?? Data()
        return HTTPResponse(
            statusCode: code,
            headers: ["Content-Type": "application/json"],
            body: data
        )
    }

    static func noContent() -> HTTPResponse {
        HTTPResponse(statusCode: 204, headers: [:], body: Data())
    }

    /// Add CORS headers for the given chrome-extension:// origin (used on both
    /// preflight and actual responses). `isPreflight` also adds PNA header.
    func withCORS(origin: String, isPreflight: Bool = false) -> HTTPResponse {
        var h = headers
        h["Access-Control-Allow-Origin"] = origin
        h["Access-Control-Allow-Methods"] = "GET,POST,OPTIONS"
        h["Access-Control-Allow-Headers"] = "Content-Type"
        if isPreflight {
            h["Access-Control-Allow-Private-Network"] = "true"
        }
        return HTTPResponse(statusCode: statusCode, headers: h, body: body)
    }

    func toHTTPBytes() -> Data {
        let statusText = Self.statusText(for: statusCode)
        var headerLines = "HTTP/1.1 \(statusCode) \(statusText)\r\n"
        headerLines += "Content-Length: \(body.count)\r\n"
        for (key, value) in headers {
            headerLines += "\(key): \(value)\r\n"
        }
        headerLines += "\r\n"
        var result = Data(headerLines.utf8)
        result.append(body)
        return result
    }

    private static func statusText(for code: Int) -> String {
        switch code {
        case 200: "OK"
        case 201: "Created"
        case 204: "No Content"
        case 400: "Bad Request"
        case 404: "Not Found"
        case 500: "Internal Server Error"
        default: "Unknown"
        }
    }
}
