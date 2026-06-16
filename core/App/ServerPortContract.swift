import Foundation

/// The single source of truth for which localhost ports the companion HTTP server may bind and that
/// every client probes to find it (TASK-433).
///
/// The app server, the MCP helper, and the Chrome extension MUST all use this exact list, otherwise
/// the server can run on a port a client never checks ("running but not found"). The Swift consumers
/// (`JobhuntServer`, `MCPHelpers`) reference this constant directly so they can't drift; the
/// extension's `CANDIDATE_PORTS` in `extension/service_worker.js` and the docs duplicate it and must
/// be kept in sync — `ServerPortContractTests` guards the value so any change is deliberate.
///
/// The server binds ONLY these fixed ports (no ephemeral fallback in production): an ephemeral port
/// is undiscoverable by the extension/MCP helper, so the server fails closed (surfaced in Settings →
/// Local Server, with Retry) rather than running on a port no client can reach.
public enum ServerPortContract {
    public static let firstPort: UInt16 = 8765
    public static let lastPort: UInt16 = 8769

    /// All bindable/probed ports, in priority order.
    public static let discoveryPorts: [UInt16] = Array(firstPort ... lastPort)
}
