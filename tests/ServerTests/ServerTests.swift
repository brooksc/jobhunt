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
