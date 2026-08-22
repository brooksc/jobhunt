import Foundation
import XCTest
@testable import JobhuntCore

/// Shutdown deleted the MCP token file unconditionally. That is wrong whenever two instances overlap:
/// the second launch overwrites the file with its own token, the first then quits and deletes it, and
/// the LIVE instance is left serving a token no client can read. Observed exactly that way — two
/// Jobhunt processes during a rebuild, then a running app whose MCP bridge answered nothing
/// (TASK-688).
final class MCPTokenOwnershipTests: XCTestCase {
    private var tokenURL: URL!

    override func setUpWithError() throws {
        tokenURL = FileManager.default.temporaryDirectory
            .appending(path: "mcp-token-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tokenURL)
    }

    func testDeletesTheFileWhenItIsStillOurs() throws {
        let token = try MCPTokenManager.generateAndWrite(at: tokenURL)
        XCTAssertTrue(MCPTokenManager.deleteIfOurs(token, at: tokenURL))
        XCTAssertFalse(FileManager.default.fileExists(atPath: tokenURL.path))
    }

    /// The regression: a newer instance's token must survive our shutdown.
    func testLeavesAnotherInstancesTokenAlone() throws {
        _ = try MCPTokenManager.generateAndWrite(at: tokenURL) // our launch
        let newer = try MCPTokenManager.generateAndWrite(at: tokenURL) // a second launch overwrites

        XCTAssertFalse(
            MCPTokenManager.deleteIfOurs("a-stale-token-from-our-launch", at: tokenURL),
            "the file no longer holds our token, so it is not ours to delete"
        )
        XCTAssertEqual(
            MCPTokenManager.read(at: tokenURL), newer,
            "the live instance's token must survive our shutdown"
        )
    }

    func testAnEmptyTokenNeverDeletesAnything() throws {
        let existing = try MCPTokenManager.generateAndWrite(at: tokenURL)
        XCTAssertFalse(MCPTokenManager.deleteIfOurs("", at: tokenURL))
        XCTAssertEqual(MCPTokenManager.read(at: tokenURL), existing)
    }

    func testMissingFileIsNotAnError() {
        XCTAssertFalse(MCPTokenManager.deleteIfOurs("anything", at: tokenURL))
    }

    /// A token file readable by anyone is refused, so ownership can't be established from it either.
    func testOverPermissiveFileIsNotTreatedAsOurs() throws {
        let token = try MCPTokenManager.generateAndWrite(at: tokenURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: tokenURL.path)
        XCTAssertFalse(MCPTokenManager.deleteIfOurs(token, at: tokenURL))
    }
}
