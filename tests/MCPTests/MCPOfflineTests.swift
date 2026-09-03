// MCPHelpers.swift is compiled directly into this test bundle (JobhuntMCP is a tool, not a framework).
import Foundation
import XCTest

/// Regression cover for "MCP error -32000: Connection closed" (TASK-715): the helper used to
/// `exit(1)` at startup when the token file was absent or nothing answered on the discovery ports,
/// so a helper spawned while Jobhunt was closed was dead for the whole life of the MCP client — and
/// clients dial their stdio helper only at startup. It must now start regardless, do the handshake
/// itself, and degrade to a readable tool error for calls it cannot forward.
final class MCPOfflineTests: XCTestCase {
    /// A session that behaves as if the app were closed: nothing on the ports, no token on disk.
    private func offlineSession() -> MCPSession {
        MCPSession(loadToken: { nil }, findPort: { nil })
    }

    private func request(_ method: String, id: Int = 1, params: [String: Any] = [:]) throws -> String {
        let body: [String: Any] = ["jsonrpc": "2.0", "id": id, "method": method, "params": params]
        let data = try JSONSerialization.data(withJSONObject: body)
        return try XCTUnwrap(String(data: data, encoding: .utf8))
    }

    private func toolCall(_ name: String) throws -> String {
        try request("tools/call", params: ["name": name, "arguments": [:] as [String: Any]])
    }

    /// The text of an `isError` tool result, or nil if the response isn't one.
    private func errorText(_ response: [String: Any]?) -> String? {
        guard let result = response?["result"] as? [String: Any],
              result["isError"] as? Bool == true,
              let content = result["content"] as? [[String: Any]] else { return nil }
        return content.first?["text"] as? String
    }

    // MARK: - Handshake works with the app down

    func testInitializeAnsweredWithNoTokenAndNoServer() throws {
        let response = try handleRequest(line: request("initialize"), session: offlineSession())
        let result = try XCTUnwrap(response?["result"] as? [String: Any])
        XCTAssertEqual(result["protocolVersion"] as? String, "2024-11-05")
        XCTAssertEqual((result["serverInfo"] as? [String: Any])?["name"] as? String, "jobhunt")
        XCTAssertNil(response?["error"], "the handshake must not depend on the app being up")
    }

    func testToolsListAnsweredWithNoTokenAndNoServer() throws {
        let response = try handleRequest(line: request("tools/list"), session: offlineSession())
        let result = try XCTUnwrap(response?["result"] as? [String: Any])
        let listed = result["tools"] as? [[String: Any]]
        XCTAssertEqual(listed?.count, tools.count, "tools/list is served by the helper itself")
    }

    // MARK: - tools/call degrades to a displayable error, never an exit

    func testToolCallWithNoServerReturnsAReadableErrorResult() throws {
        let response = try handleRequest(line: toolCall("list_sites"), session: offlineSession())
        XCTAssertEqual(errorText(response), appNotRunningMessage)
        XCTAssertNil(response?["error"], "a down app is a tool result the client shows, not a protocol error")
    }

    /// A reachable app with an unusable token is a different problem from a closed app, and the
    /// message has to say which — the two need different fixes.
    func testToolCallWithServerButNoTokenSaysSo() throws {
        let session = MCPSession(loadToken: { nil }, findPort: { 8765 })
        let response = try handleRequest(line: toolCall("list_sites"), session: session)
        XCTAssertEqual(errorText(response), tokenUnavailableMessage)
    }

    /// Argument validation still happens before any connection attempt.
    func testToolCallWithBadArgumentsStillReportsTheArgumentError() throws {
        let response = try handleRequest(
            line: request("tools/call", params: ["name": "add_site", "arguments": [:] as [String: Any]]),
            session: offlineSession()
        )
        XCTAssertEqual(errorText(response), "url required")
    }

    // MARK: - Recovery without a client restart

    /// The point of resolving per call: once the app comes up, the next call connects with no
    /// restart of the helper or the client.
    func testConnectSucceedsOnceTheAppComesUp() {
        var appIsUp = false
        let session = MCPSession(
            loadToken: { appIsUp ? "tok" : nil },
            findPort: { appIsUp ? 8765 : nil }
        )
        guard case .failure = session.connect() else {
            return XCTFail("must not connect while the app is down")
        }
        appIsUp = true
        guard case let .success(credentials) = session.connect() else {
            return XCTFail("must connect on a later call once the app is up")
        }
        XCTAssertEqual(credentials.token, "tok")
        XCTAssertEqual(credentials.port, 8765)
    }

    func testConnectRejectsAnEmptyToken() {
        let session = MCPSession(loadToken: { "" }, findPort: { 8765 })
        guard case let .failure(error) = session.connect() else {
            return XCTFail("an empty token must never be forwarded — the server fails it closed anyway")
        }
        XCTAssertEqual(error.message, tokenUnavailableMessage)
    }

    /// A 401 means we reached the server, so the port stays put and only the token is re-read
    /// (the TASK-629 refresh behaviour, preserved).
    func testRefreshWithoutPortKeepsThePortAndRereadsTheToken() {
        var current = "old"
        var portProbes = 0
        let session = MCPSession(
            token: "old",
            port: 8765,
            loadToken: { current },
            findPort: {
                portProbes += 1
                return 8766
            }
        )
        current = "new"
        session.refresh(includePort: false)
        XCTAssertEqual(session.token, "new")
        XCTAssertEqual(session.port, 8765)
        XCTAssertEqual(portProbes, 0, "a 401 is not a reason to re-probe the port")

        session.refresh(includePort: true)
        XCTAssertEqual(session.port, 8766, "a connection failure does re-probe")
    }

    // MARK: - Protocol plumbing

    func testNotificationAndBlankLineProduceNoResponse() throws {
        XCTAssertNil(try handleRequest(line: request("notifications/initialized"), session: offlineSession()))
        XCTAssertNil(handleRequest(line: "   ", session: offlineSession()))
    }

    func testMalformedLineIsAParseErrorNotAnExit() {
        let response = handleRequest(line: "{not json", session: offlineSession())
        XCTAssertEqual((response?["error"] as? [String: Any])?["code"] as? Int, -32700)
    }

    func testUnknownMethodIsMethodNotFound() throws {
        let response = try handleRequest(line: request("resources/list"), session: offlineSession())
        XCTAssertEqual((response?["error"] as? [String: Any])?["code"] as? Int, -32601)
    }
}
