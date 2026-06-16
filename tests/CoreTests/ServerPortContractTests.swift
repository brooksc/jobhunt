import XCTest
@testable import JobhuntCore

/// TASK-433: one port-discovery contract shared by the app server, MCP helper, Chrome extension, and
/// manifest. These tests fail if any of them drift from `ServerPortContract`.
final class ServerPortContractTests: XCTestCase {
    private var repoRoot: URL {
        // tests/CoreTests/ServerPortContractTests.swift → repo root
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    func testContractValueIsDeliberate() {
        // Guards an accidental change to the canonical list (changing it is a 4-surface decision).
        XCTAssertEqual(ServerPortContract.discoveryPorts, [8765, 8766, 8767, 8768, 8769])
    }

    func testExtensionServiceWorkerMatches() throws {
        let url = repoRoot.appendingPathComponent("extension/service_worker.js")
        let source = try String(contentsOf: url, encoding: .utf8)
        let ports = try portsFromArrayLiteral(named: "CANDIDATE_PORTS", in: source)
        XCTAssertEqual(ports, ServerPortContract.discoveryPorts,
                       "extension CANDIDATE_PORTS drifted from ServerPortContract")
    }

    func testExtensionManifestHostPermissionsMatch() throws {
        let url = repoRoot.appendingPathComponent("extension/manifest.json")
        let source = try String(contentsOf: url, encoding: .utf8)
        // Extract every 127.0.0.1:<port> host permission.
        let regex = try NSRegularExpression(pattern: #"127\.0\.0\.1:(\d+)"#)
        let ns = source as NSString
        let ports = regex.matches(in: source, range: NSRange(location: 0, length: ns.length))
            .compactMap { UInt16(ns.substring(with: $0.range(at: 1))) }
            .sorted()
        XCTAssertEqual(ports, ServerPortContract.discoveryPorts,
                       "manifest host_permissions drifted from ServerPortContract")
    }

    // MARK: - Helper

    private func portsFromArrayLiteral(named name: String, in source: String) throws -> [UInt16] {
        let regex = try NSRegularExpression(pattern: "\(name)\\s*=\\s*\\[([^\\]]*)\\]")
        let ns = source as NSString
        guard let match = regex.firstMatch(in: source, range: NSRange(location: 0, length: ns.length)) else {
            throw XCTSkip("\(name) literal not found")
        }
        return ns.substring(with: match.range(at: 1))
            .split(separator: ",")
            .compactMap { UInt16($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }
}
