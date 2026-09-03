// JobhuntMCP — stdio→HTTP bridge (DMG only).
// MAS builds exclude this target via the Jobhunt-MAS scheme.
// Reads MCP JSON-RPC 2.0 requests from stdin, forwards to the running Jobhunt.app
// HTTP server via /mcp/* endpoints authenticated with X-MCP-Token.
// All helpers live in MCPHelpers.swift so they can be @testable-imported by MCPTests.
//
// The helper starts unconditionally — with no token file and nothing listening on the discovery
// ports. It used to exit(1) in both cases, so a helper spawned while Jobhunt was closed died at
// once and the client reported "MCP error -32000: Connection closed" until the *client* was
// restarted (clients dial their stdio helper only at startup). Token and port are now resolved per
// tool call instead; see MCPSession.
import Foundation

let session = MCPSession()

while let line = readLine() {
    if let response = handleRequest(line: line, session: session) {
        writeResponse(response)
    }
}
