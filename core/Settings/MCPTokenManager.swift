import Foundation

/// Manages the MCP authentication token written to ~/.jobhunt-mcp-token.
/// The app generates a fresh token on each launch; the JobhuntMCP executable
/// reads it to authenticate requests to the HTTP bridge endpoints.
public enum MCPTokenManager {
    public static let tokenURL = URL.homeDirectory.appending(path: ".jobhunt-mcp-token")

    /// Generate a fresh UUID token, write it to ~/.jobhunt-mcp-token with 0600
    /// permissions (owner read/write only), and return the token.
    @discardableResult
    public static func generateAndWrite() -> String {
        let token = UUID().uuidString
        let path = tokenURL.path
        // Write atomically then lock down permissions immediately
        do {
            try token.write(to: tokenURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
        } catch {
            NSLog("MCPTokenManager: failed to write token: \(error)")
        }
        return token
    }

    /// Read the current token from ~/.jobhunt-mcp-token.
    /// Returns nil if the file is missing, unreadable, or has permissions
    /// broader than 0600 (e.g. group- or world-readable).
    public static func read() -> String? {
        let path = tokenURL.path
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let perms = attrs[.posixPermissions] as? Int,
              perms & 0o077 == 0 else {
            // File missing or permissions too broad — refuse to use the token
            return nil
        }
        return try? String(contentsOf: tokenURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Remove the token file (e.g. on logout or app uninstall).
    public static func delete() {
        try? FileManager.default.removeItem(at: tokenURL)
    }
}
