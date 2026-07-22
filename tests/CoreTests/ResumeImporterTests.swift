import XCTest
@testable import JobhuntCore

/// TASK-547 AC#5: onboarding resume import maps a persistence success/failure to the right outcome —
/// success never before the save completes, and a failure is surfaced (not swallowed).
final class ResumeImporterTests: XCTestCase {
    private struct SaveError: Error {}

    func testImportedOnSuccess() async {
        let outcome = await ResumeImporter.save(name: "My Resume", text: "Swift dev") { _, _ in }
        XCTAssertEqual(outcome, .imported(name: "My Resume", text: "Swift dev"))
    }

    func testFailedOnThrow() async {
        let outcome = await ResumeImporter.save(name: "My Resume", text: "Swift dev") { _, _ in
            throw SaveError()
        }
        guard case let .failed(message) = outcome else {
            return XCTFail("a throwing save must map to .failed, not .imported")
        }
        XCTAssertTrue(message.contains("Couldn't save the resume"), "message must be user-facing")
    }

    func testForwardsNameAndText() async {
        var captured: (String, String)?
        _ = await ResumeImporter.save(name: "R", text: "T") { name, text in captured = (name, text) }
        XCTAssertEqual(captured?.0, "R")
        XCTAssertEqual(captured?.1, "T")
    }
}
