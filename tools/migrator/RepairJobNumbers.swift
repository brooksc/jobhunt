import Foundation
import SQLite3

/// Outcome of a duplicate-`jobNumber` repair pass.
struct JobNumberRepairResult: Equatable {
    /// Rows that collided with an already-seen job number.
    let duplicatesFound: Int
    /// Rows actually renumbered (== duplicatesFound on success).
    let renumbered: Int
}

/// Renumber duplicate `ZJOBNUMBER` rows in a Jobhunt store so the unique constraint can hold
/// (TASK-372). Non-destructive: the lowest `Z_PK` (oldest) row keeps its number; each colliding row
/// is reassigned to a fresh `MAX(jobNumber) + 1, +2, …`.
///
/// This operates on raw SQLite, not SwiftData, on purpose: a store that already contains duplicate
/// job numbers can't be opened by SwiftData at all — creating the unique index fails — so the repair
/// has to run on the file before the app (or any `ModelContainer`) opens it. Run it deliberately,
/// out-of-band, with the app quit (single-writer store).
func repairDuplicateJobNumbers(at path: String) -> JobNumberRepairResult? {
    var db: DBHandle?
    guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK,
          let db else {
        fputs("Error: cannot open store for writing at '\(path)'\n", stderr)
        sqlite3_close(db)
        return nil
    }
    defer { sqlite3_close(db) }

    guard tableExists(db, "ZJOB") else {
        fputs("Error: no ZJOB table in '\(path)'\n", stderr)
        return nil
    }
    let cols = columnNames(db, "ZJOB")
    // Core Data names the column ZJOBNUMBER; discover it defensively rather than hardcoding.
    guard let numCol = cols.first(where: { $0.uppercased() == "ZJOBNUMBER" })
        ?? cols.first(where: { $0.uppercased().hasSuffix("JOBNUMBER") }) else {
        fputs("Error: no job-number column found in ZJOB\n", stderr)
        return nil
    }
    guard cols.contains("Z_PK") else {
        fputs("Error: ZJOB has no Z_PK column\n", stderr)
        return nil
    }

    // Oldest row (smallest Z_PK) for each number keeps it; later collisions are the duplicates.
    let rows = queryRows(db, "SELECT Z_PK, \(numCol) AS num FROM ZJOB WHERE \(numCol) IS NOT NULL ORDER BY num, Z_PK")
    var seenNumbers = Set<Int>()
    var maxNumber = 0
    var duplicatePKs: [Int] = []
    for row in rows {
        guard let pkStr = row["Z_PK"] ?? nil, let pk = Int(pkStr),
              let numStr = row["num"] ?? nil, let number = Int(numStr) else { continue }
        maxNumber = max(maxNumber, number)
        if seenNumbers.contains(number) {
            duplicatePKs.append(pk)
        } else {
            seenNumbers.insert(number)
        }
    }
    guard !duplicatePKs.isEmpty else {
        return JobNumberRepairResult(duplicatesFound: 0, renumbered: 0)
    }

    var nextNumber = maxNumber + 1
    var renumbered = 0
    for pk in duplicatePKs {
        // numCol comes from the DB schema and pk/nextNumber are integers — no injection surface.
        let sql = "UPDATE ZJOB SET \(numCol) = \(nextNumber) WHERE Z_PK = \(pk)"
        if sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK {
            renumbered += 1
            nextNumber += 1
        } else {
            fputs("Error: failed to renumber Z_PK \(pk): \(String(cString: sqlite3_errmsg(db)))\n", stderr)
        }
    }
    return JobNumberRepairResult(duplicatesFound: duplicatePKs.count, renumbered: renumbered)
}
