import Foundation

/// Manages the MCP authentication token written to ~/.jobhunt-mcp-token.
/// The app generates a fresh token on each launch; the JobhuntMCP executable
/// reads it to authenticate requests to the HTTP bridge endpoints.
public enum MCPTokenManager {
    public static let tokenURL = URL.homeDirectory.appending(path: ".jobhunt-mcp-token")

    /// Generate a fresh UUID token, write it to ~/.jobhunt-mcp-token, and return it.
    @discardableResult
    public static func generateAndWrite() -> String {
        let token = UUID().uuidString
        try? token.write(to: tokenURL, atomically: true, encoding: .utf8)
        return token
    }

    /// Read the current token from ~/.jobhunt-mcp-token, or nil if not present.
    public static func read() -> String? {
        try? String(contentsOf: tokenURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
