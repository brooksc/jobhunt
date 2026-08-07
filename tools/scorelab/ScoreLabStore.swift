import Foundation
import SQLite3

/// Reads stored fit analyses straight out of the SwiftData SQLite file, **read-only**.
///
/// Deliberately not via SwiftData: the store is single-writer, and the whole point of this tool is
/// that it can be run while the app is open. `SQLITE_OPEN_READONLY` guarantees it can't disturb the
/// user's data no matter what it does.
enum ScoreLabStore {
    static func load(storePath: String, status: String?) throws -> [Row] {
        var db: OpaquePointer?
        guard sqlite3_open_v2(storePath, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK,
              let db
        else {
            throw NSError(domain: "scorelab", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "cannot open \(storePath) read-only"
            ])
        }
        defer { sqlite3_close(db) }

        var sql = """
        SELECT j.ZJOBNUMBER, COALESCE(j.ZCOMPANY,''), COALESCE(j.ZTITLE,''), COALESCE(j.ZSTATUS,''),
               f.ZFITSCOREJSON
        FROM ZJOBFITSCORE f JOIN ZJOB j ON j.Z_PK = f.ZJOB
        WHERE f.ZFITSTATUS = 'succeeded' AND f.ZFITSCOREJSON IS NOT NULL
        """
        if status != nil { sql += " AND j.ZSTATUS = ?" }
        sql += " ORDER BY f.ZSCOREDAT DESC"

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw NSError(domain: "scorelab", code: 2, userInfo: [
                NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(db))
            ])
        }
        defer { sqlite3_finalize(stmt) }
        if let status {
            sqlite3_bind_text(stmt, 1, status, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        }

        var rows: [Row] = []
        var seen = Set<Int>()
        while sqlite3_step(stmt) == SQLITE_ROW {
            let number = Int(sqlite3_column_int(stmt, 0))
            // Newest score per job wins; a job scored against several résumés would otherwise be
            // counted repeatedly and skew every distribution statistic.
            guard seen.insert(number).inserted else { continue }
            func text(_ i: Int32) -> String {
                sqlite3_column_text(stmt, i).map { String(cString: $0) } ?? ""
            }
            guard let data = text(4).data(using: .utf8),
                  let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let assessments = raw["requirement_assessments"] as? [[String: Any]],
                  !assessments.isEmpty
            else { continue }

            var dimensions: [String: Double] = [:]
            for entry in (raw["dimensions"] as? [[String: Any]]) ?? [] {
                guard let name = entry["name"] as? String else { continue }
                if let v = entry["score"] as? Double { dimensions[name] = v }
                else if let v = entry["score"] as? Int { dimensions[name] = Double(v) }
            }
            rows.append(Row(
                jobNumber: number, company: text(1), title: text(2), status: text(3),
                dimensions: dimensions, assessments: assessments
            ))
        }
        return rows
    }
}
