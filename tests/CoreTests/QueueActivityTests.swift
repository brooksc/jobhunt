import Foundation
import XCTest
@testable import JobhuntCore

/// The queue's displayed state has to be honest about the one case that used to be invisible:
/// outstanding work, nothing running, no pause in force.
final class QueueActivityTests: XCTestCase {
    func testPausedWinsOverEverything() {
        // Even mid-flight work reports paused — what matters is that nothing FURTHER will start.
        XCTAssertEqual(QueueActivity.state(isPaused: true, running: 2, queued: 5), .paused)
        XCTAssertEqual(QueueActivity.state(isPaused: true, running: 0, queued: 0), .paused)
    }

    func testRunningWhenSomethingIsExecuting() {
        XCTAssertEqual(QueueActivity.state(isPaused: false, running: 1, queued: 9), .running)
    }

    /// The wedge (TASK-657): requests waiting, nothing executing, not paused. Folding this into
    /// "Running" would hide the only symptom that distinguishes it.
    func testWaitingIsDistinctFromRunning() {
        XCTAssertEqual(QueueActivity.state(isPaused: false, running: 0, queued: 3), .queued)
        XCTAssertNotEqual(
            QueueActivity.state(isPaused: false, running: 0, queued: 3),
            QueueActivity.state(isPaused: false, running: 3, queued: 3)
        )
    }

    func testIdleWhenThereIsNoWork() {
        XCTAssertEqual(QueueActivity.state(isPaused: false, running: 0, queued: 0), .idle)
    }

    /// Every state needs both strings — a label with no explanation is how "Resume Queue" came to
    /// mean four different things.
    func testEveryStateIsDescribed() {
        for state in [QueueActivity.paused, .running, .queued, .idle] {
            XCTAssertFalse(state.label.isEmpty, "\(state) has no label")
            XCTAssertFalse(state.explanation.isEmpty, "\(state) has no explanation")
        }
    }
}
