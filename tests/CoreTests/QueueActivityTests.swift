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

/// The queue showed how long each request took but never when, so a row sitting since yesterday
/// looked identical to one enqueued a minute ago — the distinction you need when it appears stuck.
final class QueueTimestampTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)
    private let locale = Locale(identifier: "en_US_POSIX")

    private func label(_ date: Date?, now: Date) -> String {
        QueueTimestamp.label(for: date, now: now, calendar: calendar, locale: locale)
    }

    /// #3: today is time-only. A column wide enough for a date on every row would spend most of its
    /// width repeating today's date.
    func testTodayShowsTimeOnly() {
        let now = Date(timeIntervalSince1970: 1_760_000_000)
        let earlier = now.addingTimeInterval(-3600)
        let text = label(earlier, now: now)
        XCTAssertFalse(text.contains("/"), "same-day rows must not carry a date: \(text)")
        XCTAssertTrue(text.contains(":"), "expected a time: \(text)")
    }

    /// #3: once it isn't today, the date is the part that carries information.
    func testOlderRowsIncludeTheDate() {
        let now = Date(timeIntervalSince1970: 1_760_000_000)
        let yesterday = now.addingTimeInterval(-36 * 3600)
        let text = label(yesterday, now: now)
        XCTAssertTrue(text.contains("/"), "an older row must show its date: \(text)")
    }

    /// #4: a queued-but-unstarted request has no finish time; the column must not invent one.
    func testNilRendersAsADash() {
        XCTAssertEqual(label(nil, now: Date()), "—")
    }
}
