// JobhuntMCP — stdio→HTTP bridge (DMG only).
// MAS builds exclude this target via the Jobhunt-MAS scheme.
// Reads MCP JSON-RPC 2.0 requests from stdin, forwards to the running Jobhunt.app
// HTTP server via /mcp/* endpoints authenticated with X-MCP-Token.
// All helpers live in MCPHelpers.swift so they can be @testable-imported by MCPTests.
import Foundation

guard let token = readToken() else {
    fputs("jobhunt-mcp: no token found at ~/.jobhunt-mcp-token\n", stderr)
    exit(1)
}

guard let port = discoverPort() else {
    fputs("jobhunt-mcp: Jobhunt.app not running on ports 8765-8769\n", stderr)
    exit(1)
}

/// Held mutably so a token rotation / port change from an app relaunch is picked up on the next call
/// (the bridge outlives the app it forwards to during development) — see MCPSession (TASK-629).
let session = MCPSession(token: token, port: port)

// Read JSON-RPC 2.0 requests from stdin line by line
while let line = readLine() {
    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { continue }

    guard let data = trimmed.data(using: .utf8),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        writeResponse(errorResponse(id: nil, code: -32700, message: "Parse error"))
        continue
    }

    let id = json["id"]
    let method = json["method"] as? String ?? ""
    let params = json["params"] as? [String: Any] ?? [:]

    switch method {
    case "initialize":
        writeResponse(successResponse(id: id, result: [
            "protocolVersion": "2024-11-05",
            "capabilities": ["tools": [:] as [String: Any]],
            "serverInfo": ["name": "jobhunt", "version": "1.0.0"]
        ] as [String: Any]))

    case "notifications/initialized":
        // No response needed for notifications
        continue

    case "tools/list":
        writeResponse(successResponse(id: id, result: ["tools": tools]))

    case "tools/call":
        let toolName = params["name"] as? String ?? ""
        let toolArgs = params["arguments"] as? [String: Any] ?? [:]

        switch callTool(name: toolName, args: toolArgs, session: session) {
        case let .success(result):
            writeResponse(successResponse(id: id, result: result))
        case let .failure(err):
            writeResponse(successResponse(id: id, result: [
                "isError": true,
                "content": [["type": "text", "text": err.message]]
            ] as [String: Any]))
        }

    default:
        writeResponse(errorResponse(id: id, code: -32601, message: "Method not found: \(method)"))
    }
}
