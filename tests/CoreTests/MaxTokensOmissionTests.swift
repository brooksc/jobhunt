import Foundation
import XCTest
@testable import JobhuntCore

/// TASK-607: the OpenAI-compatible request omits `max_tokens` by default so reasoning models aren't
/// truncated, and still sends it when a caller sets an explicit cap (e.g. the connectivity ping).
final class MaxTokensOmissionTests: XCTestCase {
    private func bodyObject(_ request: ChatRequest) throws -> [String: Any] {
        let data = try OpenAICompatibleTransport.buildBody(request: request, fmt: nil)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testOmitsMaxTokensByDefault() throws {
        let request = ChatRequest(messages: [ChatMessage(role: "user", content: "hi")], model: "gpt-x")
        let obj = try bodyObject(request)
        XCTAssertNil(obj["max_tokens"], "no cap should be sent when maxTokens is nil")
        XCTAssertEqual(obj["model"] as? String, "gpt-x")
    }

    func testSendsMaxTokensWhenSet() throws {
        let request = ChatRequest(
            messages: [ChatMessage(role: "user", content: "hi")], model: "gpt-x", maxTokens: 16
        )
        let obj = try bodyObject(request)
        XCTAssertEqual(obj["max_tokens"] as? Int, 16, "an explicit cap must still be sent")
    }
}
