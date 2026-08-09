import Foundation
import XCTest
@testable import JobhuntCore

/// Start Fresh is a last-resort data-boundary action that promises the corrupt store is *moved
/// aside, not deleted*. It used to do all four moves with `try?` and terminate regardless, so a
/// failed move quit the app straight back into the same corrupt store with nothing said.
final class StoreQuarantineTests: XCTestCase {
    private let store = URL(fileURLWithPath: "/tmp/jh/jobhunt.store")

    /// Records what was asked of the filesystem, and can be told to refuse specific paths.
    private final class FakeFS: @unchecked Sendable {
        var present: Set<String>
        var failMoves: Set<String> = []
        var failRemoves: Set<String> = []
        private(set) var moves: [(String, String)] = []
        private(set) var removes: [String] = []

        init(present: [String]) {
            self.present = Set(present)
        }

        struct Refused: Error, LocalizedError {
            var errorDescription: String? {
                "Operation not permitted"
            }
        }

        var ops: StoreQuarantine.FileOps {
            StoreQuarantine.FileOps(
                exists: { [self] in present.contains($0.path) },
                move: { [self] from, to in
                    if failMoves.contains(from.path) { throw Refused() }
                    moves.append((from.path, to.path))
                    present.remove(from.path)
                    present.insert(to.path)
                },
                remove: { [self] url in
                    if failRemoves.contains(url.path) { throw Refused() }
                    removes.append(url.path)
                    present.remove(url.path)
                }
            )
        }
    }

    /// #1: the whole point — a failed main move must be an error, not a silent quit.
    func testAFailedMainStoreMoveThrows() {
        let fs = FakeFS(present: [store.path])
        fs.failMoves = [store.path]
        XCTAssertThrowsError(try StoreQuarantine.moveAside(storeURL: store, ops: fs.ops)) { error in
            guard case StoreQuarantine.QuarantineError.mainStoreMoveFailed = error else {
                return XCTFail("expected mainStoreMoveFailed, got \(error)")
            }
        }
        XCTAssertTrue(fs.removes.isEmpty, "a failed move must not fall back to deleting the user's data")
    }

    /// #2: moved, never deleted.
    func testTheStoreIsMovedNotDeleted() throws {
        let fs = FakeFS(present: [store.path])
        let outcome = try StoreQuarantine.moveAside(storeURL: store, ops: fs.ops)

        XCTAssertEqual(fs.moves.count, 1)
        XCTAssertEqual(fs.moves[0].0, store.path)
        XCTAssertEqual(fs.moves[0].1, outcome.movedAside.path)
        XCTAssertTrue(fs.removes.isEmpty)
        XCTAssertTrue(outcome.movedAside.lastPathComponent.contains("corrupt-"))
    }

    /// #3: companions present are moved with the store.
    func testCompanionsMoveAlongside() throws {
        let fs = FakeFS(present: [store.path, store.path + "-wal", store.path + "-shm"])
        let outcome = try StoreQuarantine.moveAside(storeURL: store, ops: fs.ops)

        XCTAssertEqual(fs.moves.count, 3)
        XCTAssertTrue(outcome.strandedCompanions.isEmpty)
    }

    /// #3: absent companions are not an error — most stores have no `-shm` at rest.
    func testMissingCompanionsAreFine() throws {
        let fs = FakeFS(present: [store.path])
        let outcome = try StoreQuarantine.moveAside(storeURL: store, ops: fs.ops)
        XCTAssertEqual(fs.moves.count, 1)
        XCTAssertTrue(outcome.strandedCompanions.isEmpty)
    }

    /// #3, the dangerous case: a `-wal` that can't be moved is DELETED rather than left beside the
    /// new store, because SQLite may try to replay it into a database it doesn't belong to.
    func testAnUnmovableCompanionIsDeleted() throws {
        let fs = FakeFS(present: [store.path, store.path + "-wal"])
        fs.failMoves = [store.path + "-wal"]

        let outcome = try StoreQuarantine.moveAside(storeURL: store, ops: fs.ops)
        XCTAssertEqual(fs.removes, [store.path + "-wal"])
        XCTAssertTrue(outcome.strandedCompanions.isEmpty, "deleting it counts as handled")
    }

    /// …and if it can be neither moved nor deleted, the caller is told so it can warn instead of
    /// relaunching into a store with a foreign journal next to it.
    func testACompanionThatCannotBeRemovedIsReported() throws {
        let fs = FakeFS(present: [store.path, store.path + "-wal"])
        fs.failMoves = [store.path + "-wal"]
        fs.failRemoves = [store.path + "-wal"]

        let outcome = try StoreQuarantine.moveAside(storeURL: store, ops: fs.ops)
        XCTAssertEqual(outcome.strandedCompanions, ["-wal"])
    }

    /// #4: retrying recovery within the same second must not collide. A timestamp alone did, and the
    /// same second is exactly when a user retries.
    func testTwoRecoveriesInTheSameSecondDoNotCollide() throws {
        let instant = Date(timeIntervalSince1970: 1_760_000_000)
        let first = try StoreQuarantine.moveAside(
            storeURL: store, ops: FakeFS(present: [store.path]).ops, timestamp: instant
        )
        let second = try StoreQuarantine.moveAside(
            storeURL: store, ops: FakeFS(present: [store.path]).ops, timestamp: instant
        )
        XCTAssertNotEqual(first.movedAside, second.movedAside)
    }

    /// Nothing to preserve is not a failure: starting fresh is what was asked for.
    func testAMissingStoreIsNotAnError() throws {
        let fs = FakeFS(present: [])
        let outcome = try StoreQuarantine.moveAside(storeURL: store, ops: fs.ops)
        XCTAssertTrue(fs.moves.isEmpty)
        XCTAssertTrue(outcome.strandedCompanions.isEmpty)
    }
}
