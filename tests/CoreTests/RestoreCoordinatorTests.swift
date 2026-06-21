import XCTest
@testable import JobhuntCore

/// TASK-546: the restore boundary must quiesce runtime writers BEFORE replacing the store, and abort
/// before the destructive swap if the safety backup fails.
@MainActor
final class RestoreCoordinatorTests: XCTestCase {
    private enum TestError: Error { case boom }
    private let backupURL = URL(fileURLWithPath: "/tmp/jh-restore-test/backup.sqlite")
    private let storeURL = URL(fileURLWithPath: "/tmp/jh-restore-test/store.sqlite")
    private let safetyURL = URL(fileURLWithPath: "/tmp/jh-restore-test/safety.sqlite")

    func testQuiescesAndBacksUpBeforeRestoring() async throws {
        var order: [String] = []
        try await RestoreCoordinator.perform(
            backupURL: backupURL, storeURL: storeURL, safetyBackupURL: safetyURL,
            quiesceRuntime: { order.append("quiesce") },
            backup: { _, _ in order.append("backup") },
            restore: { _, _ in order.append("restore") }
        )
        XCTAssertEqual(
            order,
            ["quiesce", "backup", "restore"],
            "runtime must be quiesced, then safety-backed-up, then swapped"
        )
    }

    func testSafetyBackupFailure_quiescesButAbortsBeforeSwap() async {
        var quiesced = false
        var restoreCalled = false
        do {
            try await RestoreCoordinator.perform(
                backupURL: backupURL, storeURL: storeURL, safetyBackupURL: safetyURL,
                quiesceRuntime: { quiesced = true },
                backup: { _, _ in throw TestError.boom },
                restore: { _, _ in restoreCalled = true }
            )
            XCTFail("expected a StageError")
        } catch let err as RestoreCoordinator.StageError {
            XCTAssertEqual(err.stage, .safetyBackup)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
        XCTAssertTrue(quiesced, "runtime must be quiesced even when the safety backup fails")
        XCTAssertFalse(restoreCalled, "the destructive swap must not run if the safety backup failed")
    }

    func testRestoreFailure_reportsRestoreStage() async {
        do {
            try await RestoreCoordinator.perform(
                backupURL: backupURL, storeURL: storeURL, safetyBackupURL: safetyURL,
                quiesceRuntime: {},
                backup: { _, _ in },
                restore: { _, _ in throw TestError.boom }
            )
            XCTFail("expected a StageError")
        } catch let err as RestoreCoordinator.StageError {
            XCTAssertEqual(err.stage, .restore)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }
}
