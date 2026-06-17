import SwiftData
import XCTest
@testable import JobhuntCore

/// TASK-424: UI-test / fixture temp-store cleanup must fail closed, not silently open stale data.
final class FreshTestStoreTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("fresh-store-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func testStoreAndSidecars_usesHyphenSuffixes() {
        let url = dir.appendingPathComponent("jobhunt-ui-test.store")
        let names = ModelContainerFactory.storeAndSidecars(of: url).map(\.lastPathComponent)
        XCTAssertEqual(names, [
            "jobhunt-ui-test.store",
            "jobhunt-ui-test.store-wal",   // CoreData/SQLite sidecar form, NOT .wal
            "jobhunt-ui-test.store-shm",
        ])
    }

    func testFreshTestStore_doesNotCarryOverPreviousRunData() throws {
        let url = dir.appendingPathComponent("jobhunt-ui-test.store")
        // First run: write a job into a store at this path.
        let first = try ModelContainerFactory.freshTestStore(at: url)
        let ctx = ModelContext(first)
        ctx.insert(Job(jobNumber: 99, title: "Stale"))
        try ctx.save()

        // Second run at the same path must start clean (the prior store + sidecars removed).
        let second = try ModelContainerFactory.freshTestStore(at: url)
        let jobs = try ModelContext(second).fetch(FetchDescriptor<Job>())
        XCTAssertTrue(jobs.isEmpty, "a fresh test store must not carry over the previous run's data")
    }

    func testFreshTestStore_failsClosedWhenParentCannotBeCreated() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        // A FILE on an intermediate path component → createDirectory(withIntermediateDirectories:)
        // must throw (can't make `blocker` into a directory).
        let blocker = dir.appendingPathComponent("blocker")
        try Data("x".utf8).write(to: blocker)
        let url = blocker.appendingPathComponent("sub/jobhunt-ui-test.store")
        XCTAssertThrowsError(try ModelContainerFactory.freshTestStore(at: url),
                             "cleanup that can't create the directory must fail closed")
    }

    func testFreshTestStore_succeedsOnCleanSlate() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("jobhunt-ui-test.store")
        XCTAssertNoThrow(try ModelContainerFactory.freshTestStore(at: url))
    }
}
