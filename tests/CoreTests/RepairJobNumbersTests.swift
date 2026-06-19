import SQLite3
import XCTest
@testable import JobhuntCore

/// TASK-372: file-backed coverage for the duplicate-jobNumber repair the migrator runs before a
/// constrained store can be opened by SwiftData.
final class RepairJobNumbersTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("repair-jobnum-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    /// Build a minimal ZJOB table (no unique index, mirroring a pre-constraint/legacy store) with
    /// the given (Z_PK, jobNumber) rows.
    private func makeStore(_ rows: [(pk: Int, num: Int?)]) throws -> String {
        let path = dir.appendingPathComponent("test.store").path
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(path, &db), SQLITE_OK)
        defer { sqlite3_close(db) }
        XCTAssertEqual(
            sqlite3_exec(db, "CREATE TABLE ZJOB (Z_PK INTEGER PRIMARY KEY, ZJOBNUMBER INTEGER)", nil, nil, nil),
            SQLITE_OK
        )
        for row in rows {
            let value = row.num.map(String.init) ?? "NULL"
            XCTAssertEqual(
                sqlite3_exec(db, "INSERT INTO ZJOB (Z_PK, ZJOBNUMBER) VALUES (\(row.pk), \(value))", nil, nil, nil),
                SQLITE_OK
            )
        }
        return path
    }

    private func jobNumbers(_ path: String) -> [Int: Int] { // Z_PK -> jobNumber
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(path, &db), SQLITE_OK)
        defer { sqlite3_close(db) }
        var stmt: OpaquePointer?
        XCTAssertEqual(
            sqlite3_prepare_v2(db, "SELECT Z_PK, ZJOBNUMBER FROM ZJOB WHERE ZJOBNUMBER IS NOT NULL", -1, &stmt, nil),
            SQLITE_OK
        )
        defer { sqlite3_finalize(stmt) }
        var result: [Int: Int] = [:]
        while sqlite3_step(stmt) == SQLITE_ROW {
            result[Int(sqlite3_column_int(stmt, 0))] = Int(sqlite3_column_int(stmt, 1))
        }
        return result
    }

    func testRenumbersDuplicatesKeepingOldest() throws {
        // jobNumber 2 collides across PKs 2, 3, 5.
        let path = try makeStore([(1, 1), (2, 2), (3, 2), (4, 3), (5, 2)])

        let result = repairDuplicateJobNumbers(at: path)
        XCTAssertEqual(result, JobNumberRepairResult(duplicatesFound: 2, renumbered: 2))

        let numbers = jobNumbers(path)
        XCTAssertEqual(numbers[1], 1)
        XCTAssertEqual(numbers[2], 2, "oldest (smallest Z_PK) of the colliding rows keeps its number")
        XCTAssertEqual(numbers[4], 3, "unaffected row keeps its number")
        // The two later collisions are renumbered to fresh max+1 values.
        XCTAssertEqual(Set(numbers.values).count, 5, "all job numbers are now unique")
        XCTAssertEqual(numbers.count, 5, "no rows dropped — non-destructive")
        XCTAssertEqual(Set(numbers.values), Set([1, 2, 3, 4, 5]))
    }

    func testNoDuplicates_isNoOp() throws {
        let path = try makeStore([(1, 1), (2, 2), (3, 3)])
        XCTAssertEqual(repairDuplicateJobNumbers(at: path), JobNumberRepairResult(duplicatesFound: 0, renumbered: 0))
        XCTAssertEqual(Set(jobNumbers(path).values), Set([1, 2, 3]))
    }

    func testNullJobNumbersIgnored() throws {
        // Rows with NULL jobNumber (e.g. not-yet-numbered) don't count as collisions.
        let path = try makeStore([(1, nil), (2, nil), (3, 5)])
        XCTAssertEqual(repairDuplicateJobNumbers(at: path), JobNumberRepairResult(duplicatesFound: 0, renumbered: 0))
    }

    func testIdempotent_secondRunFindsNothing() throws {
        let path = try makeStore([(1, 1), (2, 1), (3, 1)])
        let first = repairDuplicateJobNumbers(at: path)
        XCTAssertEqual(first?.renumbered, 2)
        let second = repairDuplicateJobNumbers(at: path)
        XCTAssertEqual(second, JobNumberRepairResult(duplicatesFound: 0, renumbered: 0))
        XCTAssertEqual(Set(jobNumbers(path).values).count, 3)
    }
}
