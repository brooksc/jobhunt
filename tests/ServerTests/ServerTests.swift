import XCTest
@testable import JobhuntServer

final class ServerErrorTests: XCTestCase {
    func testServerErrorCasesAreDistinct() {
        // Verify the two error cases produce different descriptions so they
        // remain distinguishable in logs and aren't accidentally collapsed.
        let noPort = ServerError.noPortAvailable as NSError
        let cancelled = ServerError.listenerCancelled as NSError
        XCTAssertFalse(noPort.localizedDescription.isEmpty,
                       "noPortAvailable must have a non-empty description")
        XCTAssertFalse(cancelled.localizedDescription.isEmpty,
                       "listenerCancelled must have a non-empty description")
        XCTAssertNotEqual(noPort.localizedDescription, cancelled.localizedDescription,
                          "Error cases must be distinguishable by description")
    }
}
