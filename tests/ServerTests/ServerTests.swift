import XCTest
@testable import JobhuntServer

final class ServerTests: XCTestCase {
    func testVersion() {
        XCTAssertFalse(JobhuntServer.version.isEmpty)
    }
}
