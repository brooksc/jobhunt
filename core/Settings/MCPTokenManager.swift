import Foundation

/// Manages the MCP authentication token written to ~/.jobhunt-mcp-token.
///
/// The token is **persistent**: minted once and reused across launches. It used to be rotated on
/// every launch and deleted on shutdown (TASK-530), which broke the MCP bridge for every third-party
/// AI client — clients dial their stdio helper only at startup, so a helper spawned while Jobhunt was
/// closed found no token, exited, and the connection stayed dead until the *client* was restarted.
///
/// Rotation bought nothing security-wise. The loopback binding is the boundary (see CLAUDE.md): a
/// leaked token is useless from another machine, and a hostile process running as this user could
/// read the SwiftData store directly. The token's real job is scoping *which* AI client may act on
/// the user's data, and that is served by the token existing, not by it changing.
public enum MCPTokenManager {
    public static let tokenURL = URL.homeDirectory.appending(path: ".jobhunt-mcp-token")

    // MARK: - Public API (operates on the real ~/.jobhunt-mcp-token)

    /// Return the existing token, or mint and persist one if the file is absent or unreadable
    /// (missing, or with permissions broader than 0600). This is the launch-path entry point —
    /// reusing the token is what lets an MCP helper spawned while the app was closed keep working.
    @discardableResult
    public static func ensureToken() throws -> String {
        try ensureToken(at: tokenURL)
    }

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

    // periphery:ignore - No automatic caller by design; kept as the only way to clear the token
    // (a deliberate reset, or uninstall).
    /// Remove the token file. **Never call this from app shutdown.** Deleting on quit is what broke
    /// two things in turn: unconditionally, it wiped a *live* second instance's token during a
    /// rebuild (TASK-688); conditionally (`deleteIfOurs`), it still left a helper spawned after the
    /// last quit with no token at all. The token is persistent now — deleting it is a user action.
    public static func delete() {
        delete(at: tokenURL)
    }

    // MARK: - Shared URL-seam implementation

    // Operate on an explicit URL so the lifecycle can be unit-tested without touching the user's real
    // home directory (TASK-530), and so the MCP command-line helper can share the exact same path +
    // permission policy instead of duplicating it (TASK-531). Public for the separate JobhuntMCP target.

    public static func ensureToken(at url: URL) throws -> String {
        if let existing = read(at: url), !existing.isEmpty { return existing }
        return try generateAndWrite(at: url)
    }

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
