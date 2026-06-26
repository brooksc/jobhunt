import Foundation

/// Manages the MCP authentication token written to ~/.jobhunt-mcp-token.
/// The app generates a fresh token on each launch and deletes it on normal shutdown
/// (TASK-530), so the credential is transient and doesn't outlive the running server;
/// the JobhuntMCP executable reads it to authenticate requests to the HTTP bridge endpoints.
public enum MCPTokenManager {
    public static let tokenURL = URL.homeDirectory.appending(path: ".jobhunt-mcp-token")

    // MARK: - Public API (operates on the real ~/.jobhunt-mcp-token)

    /// Generate a fresh UUID token, write it with 0600 permissions, and return it. Throws if the
    /// file cannot be written or permissions cannot be set — callers must not start MCP routes if
    /// this fails (a partial/over-permissive file is removed before throwing).
    @discardableResult
    public static func generateAndWrite() throws -> String {
        try generateAndWrite(at: tokenURL)
    }

    /// Read the current token. Returns nil if the file is missing, unreadable, or has permissions
    /// broader than 0600 (e.g. group- or world-readable).
    public static func read() -> String? {
        read(at: tokenURL)
    }

    /// Remove the token file (on normal shutdown, logout, or uninstall).
    public static func delete() {
        delete(at: tokenURL)
    }

    // MARK: - Shared URL-seam implementation

    // Operate on an explicit URL so the lifecycle can be unit-tested without touching the user's real
    // home directory (TASK-530), and so the MCP command-line helper can share the exact same path +
    // permission policy instead of duplicating it (TASK-531). Public for the separate JobhuntMCP target.

    @discardableResult
    public static func generateAndWrite(at url: URL) throws -> String {
        let token = UUID().uuidString
        do {
            // Write atomically then lock down permissions immediately.
            try token.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            // Don't leave a partial or over-permissive token file behind on failure (TASK-530).
            try? FileManager.default.removeItem(at: url)
            throw error
        }
        return token
    }

    public static func read(at url: URL) -> String? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let perms = attrs[.posixPermissions] as? Int,
              perms & 0o077 == 0 else {
            // File missing or permissions too broad — refuse to use the token.
            return nil
        }
        return try? String(contentsOf: url, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func delete(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
