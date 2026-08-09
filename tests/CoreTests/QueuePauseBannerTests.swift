import Foundation
import SwiftData
import XCTest
@testable import JobhuntCore

/// When a paused queue should speak up, and in whose voice (TASK-524).
///
/// The reported failure was silence: four fit scores and a re-queued extraction that never ran,
/// because an earlier flaky extraction had auto-paused the queue and the only on-screen cue was a
/// small button in a header.
final class QueuePauseBannerTests: XCTestCase {
    /// #4 (half of it): a running queue says nothing, whatever is in it.
    func testNoBannerWhileRunning() {
        XCTAssertNil(QueuePauseBanner.make(isPaused: false, reason: .repeatedFailures, waiting: 12))
    }

    /// The other half, and the reason this isn't just `isPaused`: paused-and-empty costs the user
    /// nothing, and a banner that's always on screen is one people stop reading before the one time
    /// it matters.
    func testNoBannerWhenNothingIsWaiting() {
        XCTAssertNil(QueuePauseBanner.make(isPaused: true, reason: .repeatedFailures, waiting: 0))
    }

    /// #1 and #3: it appears with work waiting, and says how much.
    func testBannerAppearsWithWaitingWorkAndCountsIt() throws {
        let banner = try XCTUnwrap(
            QueuePauseBanner.make(isPaused: true, reason: .user, waiting: 5)
        )
        XCTAssertTrue(banner.title.contains("5 items waiting"), banner.title)
    }

    func testSingularWording() throws {
        let banner = try XCTUnwrap(
            QueuePauseBanner.make(isPaused: true, reason: .user, waiting: 1)
        )
        XCTAssertTrue(banner.title.contains("1 item waiting"), banner.title)
    }

    /// #2: the two cases need different words AND different urgency. A user pause is a decision; an
    /// auto-pause is a symptom the user probably doesn't know about.
    func testAutoPauseIsDistinguishedFromAUserPause() throws {
        let auto = try XCTUnwrap(
            QueuePauseBanner.make(isPaused: true, reason: .repeatedFailures, waiting: 3)
        )
        let manual = try XCTUnwrap(
            QueuePauseBanner.make(isPaused: true, reason: .user, waiting: 3)
        )
        XCTAssertTrue(auto.isAutomatic)
        XCTAssertFalse(manual.isAutomatic)
        XCTAssertTrue(auto.title.lowercased().contains("auto-paused"), auto.title)
        XCTAssertFalse(manual.title.lowercased().contains("auto-paused"), manual.title)
        XCTAssertNotEqual(auto.detail, manual.detail)
    }

    /// A rejected key is its own case: resuming without fixing the key just fails again, so the
    /// detail has to point at Settings rather than at the Resume button.
    func testAuthFailureSaysWhereToFixIt() throws {
        let banner = try XCTUnwrap(
            QueuePauseBanner.make(isPaused: true, reason: .authenticationFailed, waiting: 2)
        )
        XCTAssertTrue(banner.isAutomatic)
        XCTAssertTrue(banner.detail.contains("Settings"), banner.detail)
    }
}

/// The persisted half: the reason has to survive a relaunch and must not outlive the pause it
/// describes.
@MainActor
final class QueuePauseReasonPersistenceTests: XCTestCase {
    private func makeStore() throws -> SettingsStore {
        let container = try ModelContainerFactory.inMemory()
        return SettingsStore(modelContext: ModelContext(container))
    }

    func testDefaultsToUser() throws {
        XCTAssertEqual(try makeStore().llmQueuePauseReason, .user)
    }

    func testPausingRecordsTheReason() throws {
        let store = try makeStore()
        store.setQueuePaused(true, reason: .repeatedFailures)
        XCTAssertTrue(store.llmQueuePaused)
        XCTAssertEqual(store.llmQueuePauseReason, .repeatedFailures)
    }

    /// A stale "auto-paused after failures" surviving a successful resume would mislabel the user's
    /// *next* deliberate pause as a provider problem.
    func testResumingClearsTheReason() throws {
        let store = try makeStore()
        store.setQueuePaused(true, reason: .authenticationFailed)
        store.setQueuePaused(false)
        XCTAssertFalse(store.llmQueuePaused)
        XCTAssertEqual(store.llmQueuePauseReason, .user)
    }

    /// Reading back something unrecognised (an older build, a hand-edited store) must not claim an
    /// automatic failure that never happened.
    func testUnknownStoredValueReadsAsUser() throws {
        let store = try makeStore()
        store.setBool(true, forKey: SettingsKey.llmQueuePaused)
        try store.set("something-else", forKey: SettingsKey.llmQueuePauseReason)
        XCTAssertEqual(store.llmQueuePauseReason, .user)
    }
}
