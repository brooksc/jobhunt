import XCTest
@testable import JobhuntServer

// TASK-390: a value that fails to serialize must yield a 500, not a 200 with "{}".
private struct ThrowingEncodable: Encodable {
    func encode(to _: Encoder) throws {
        throw NSError(domain: "ThrowingEncodable", code: 1)
    }
}

final class HTTPResponseSerializationTests: XCTestCase {
    func testOk_serializationFailureReturns500() {
        let response = HTTPResponse.ok(ThrowingEncodable())
        XCTAssertEqual(response.statusCode, 500, "Encode failure must be a 500, not a 200")
        XCTAssertFalse(response.body.isEmpty)
        XCTAssertFalse(
            String(decoding: response.body, as: UTF8.self).contains("{}"),
            "must not masquerade as an empty successful body"
        )
    }

    func testOk_validValueReturns200() {
        struct Payload: Encodable { let ok: Bool }
        let response = HTTPResponse.ok(Payload(ok: true))
        XCTAssertEqual(response.statusCode, 200)
    }

    // TASK-534: every status code the server can emit must map to a real reason phrase, never the
    // fallback "Unknown" (which would produce misleading raw HTTP diagnostics like "405 Unknown").
    func testStatusText_coversEveryEmittedCode() {
        // Mirror the codes emitted across HTTPResponse, MCPBridgeRoutes, and inspectRequestFraming.
        let emitted = [200, 201, 204, 400, 401, 403, 404, 405, 413, 431, 500, 503]
        for code in emitted {
            XCTAssertNotEqual(
                HTTPResponse.statusText(for: code), "Unknown",
                "status \(code) must have a reason phrase"
            )
        }
        XCTAssertEqual(HTTPResponse.statusText(for: 405), "Method Not Allowed")
        XCTAssertEqual(HTTPResponse.statusText(for: 431), "Request Header Fields Too Large")
    }

    // AC#3: the serialized status line carries the reason phrase (not "Unknown") for codes that
    // previously fell through — proven against the actual response bytes.
    func testSerializedStatusLine_includesReasonPhrase() {
        let response = HTTPResponse.error("Method not allowed", code: 405)
        let firstLine = String(decoding: response.toHTTPBytes(), as: UTF8.self)
            .components(separatedBy: "\r\n").first ?? ""
        XCTAssertEqual(firstLine, "HTTP/1.1 405 Method Not Allowed")
    }
}

final class ServerErrorTests: XCTestCase {
    func testServerErrorCasesAreDistinct() {
        // Verify the two error cases produce different descriptions so they
        // remain distinguishable in logs and aren't accidentally collapsed.
        let noPort = ServerError.noPortAvailable as NSError
        let cancelled = ServerError.listenerCancelled as NSError
        XCTAssertFalse(
            noPort.localizedDescription.isEmpty,
            "noPortAvailable must have a non-empty description"
        )
        XCTAssertFalse(
            cancelled.localizedDescription.isEmpty,
            "listenerCancelled must have a non-empty description"
        )
        XCTAssertNotEqual(
            noPort.localizedDescription,
            cancelled.localizedDescription,
            "Error cases must be distinguishable by description"
        )
    }
}

// MARK: - Request framing (TASK-533)

final class RequestFramingTests: XCTestCase {
    private let cap = 64 * 1024
    private func raw(_ s: String) -> Data {
        Data(s.utf8)
    }

    func testIncompleteWhenHeaderTerminatorNotSeen() {
        let r = raw("POST /x HTTP/1.1\r\nContent-Length: 5")
        XCTAssertEqual(inspectRequestFraming(r, maxHeaderBytes: cap), .incomplete)
    }

    func testOversizedHeadersRejectedWith431() {
        let big = raw("GET / HTTP/1.1\r\n" + String(repeating: "a", count: cap + 10))
        XCTAssertEqual(
            inspectRequestFraming(big, maxHeaderBytes: cap),
            .invalid(reason: "Request header fields too large", statusCode: 431)
        )
    }

    func testValidGetFramesWithZeroLength() {
        let r = raw("GET /health HTTP/1.1\r\nHost: x\r\n\r\n")
        XCTAssertEqual(
            inspectRequestFraming(r, maxHeaderBytes: cap),
            .valid(method: "GET", path: "/health", contentLength: 0)
        )
    }

    func testMalformedContentLengthRejected() {
        let r = raw("POST /x HTTP/1.1\r\nContent-Length: abc\r\n\r\n")
        XCTAssertEqual(
            inspectRequestFraming(r, maxHeaderBytes: cap),
            .invalid(reason: "Malformed Content-Length", statusCode: 400)
        )
    }

    func testNegativeContentLengthRejected() {
        let r = raw("POST /x HTTP/1.1\r\nContent-Length: -5\r\n\r\n")
        XCTAssertEqual(
            inspectRequestFraming(r, maxHeaderBytes: cap),
            .invalid(reason: "Malformed Content-Length", statusCode: 400)
        )
    }

    func testConflictingDuplicateContentLengthRejected() {
        let r = raw("POST /x HTTP/1.1\r\nContent-Length: 5\r\nContent-Length: 9\r\n\r\nhello")
        XCTAssertEqual(
            inspectRequestFraming(r, maxHeaderBytes: cap),
            .invalid(reason: "Conflicting Content-Length headers", statusCode: 400)
        )
    }

    func testMissingContentLengthOnPostRejected() {
        let r = raw("POST /x HTTP/1.1\r\nHost: x\r\n\r\n")
        XCTAssertEqual(
            inspectRequestFraming(r, maxHeaderBytes: cap),
            .invalid(reason: "Missing Content-Length on POST", statusCode: 400)
        )
    }

    func testValidPostWithMultiByteJSONBodyFramesAndParses() {
        let body = Data(#"{"q":"café"}"#.utf8) // 13 bytes (é is 2)
        var data = raw("POST /captures HTTP/1.1\r\nContent-Length: \(body.count)\r\n\r\n")
        data.append(body)
        XCTAssertEqual(
            inspectRequestFraming(data, maxHeaderBytes: cap),
            .valid(method: "POST", path: "/captures", contentLength: body.count)
        )
        XCTAssertEqual(parseHTTPRequest(data)?.body, body, "multi-byte JSON body must frame by byte count")
    }
}
