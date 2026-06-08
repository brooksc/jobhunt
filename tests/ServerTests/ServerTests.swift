import XCTest
@testable import JobhuntServer

final class ServerTests: XCTestCase {
    func testServerErrorCases() {
        // Ensure the error enum is accessible
        _ = ServerError.noPortAvailable
        _ = ServerError.listenerCancelled
    }
}
