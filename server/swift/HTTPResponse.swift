import Foundation

struct HTTPResponse {
    let statusCode: Int
    var headers: [String: String]
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

    /// Returns a copy of this response with CORS headers set for the given extension origin.
    /// Only call this for origins that have already been validated by `isAllowedExtensionOrigin`.
    func withCORS(origin: String, isPreflight: Bool) -> HTTPResponse {
        var updated = self
        updated.headers["Access-Control-Allow-Origin"] = origin
        updated.headers["Access-Control-Allow-Methods"] = "GET,POST,OPTIONS"
        updated.headers["Access-Control-Allow-Headers"] = "Content-Type,X-MCP-Token"
        if isPreflight {
            updated.headers["Access-Control-Allow-Private-Network"] = "true"
        }
        return updated
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
        case 401: "Unauthorized"
        case 403: "Forbidden"
        case 404: "Not Found"
        case 413: "Request Entity Too Large"
        case 500: "Internal Server Error"
        case 503: "Service Unavailable"
        default: "Unknown"
        }
    }
}
