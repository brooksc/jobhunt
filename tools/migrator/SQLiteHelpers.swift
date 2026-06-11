import Foundation
import SQLite3

// MARK: - Types

typealias DBHandle = OpaquePointer

// MARK: - DB Access

func openReadOnly(_ path: String) -> DBHandle? {
    var db: DBHandle?
    let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
    let rc = sqlite3_open_v2(path, &db, flags, nil)
    if rc != SQLITE_OK {
        let msg = db.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
        fputs("Error: cannot open '\(path)': \(msg)\n", stderr)
        sqlite3_close(db)
        return nil
    }
    return db
}

func tableExists(_ db: DBHandle, _ table: String) -> Bool {
    let sql = "SELECT 1 FROM sqlite_master WHERE type='table' AND name=?"
    var stmt: OpaquePointer?
    guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return false }
    defer { sqlite3_finalize(stmt) }
    sqlite3_bind_text(stmt, 1, table, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
    return sqlite3_step(stmt) == SQLITE_ROW
}

func columnNames(_ db: DBHandle, _ table: String) -> Set<String> {
    var cols = Set<String>()
    var stmt: OpaquePointer?
    let sql = "PRAGMA table_info(\(table))"
    guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return cols }
    defer { sqlite3_finalize(stmt) }
    while sqlite3_step(stmt) == SQLITE_ROW {
        if let name = sqlite3_column_text(stmt, 1) {
            cols.insert(String(cString: name))
        }
    }
    return cols
}

func queryRows(_ db: DBHandle, _ sql: String) -> [[String: String?]] {
    var stmt: OpaquePointer?
    guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
    defer { sqlite3_finalize(stmt) }
    var rows: [[String: String?]] = []
    while sqlite3_step(stmt) == SQLITE_ROW {
        var row: [String: String?] = [:]
        let count = sqlite3_column_count(stmt)
        for col in 0 ..< count {
            let name = String(cString: sqlite3_column_name(stmt, col))
            if sqlite3_column_type(stmt, col) == SQLITE_NULL {
                row[name] = .some(nil)
            } else if let text = sqlite3_column_text(stmt, col) {
                row[name] = String(cString: text)
            } else {
                row[name] = .some(nil)
            }
        }
        rows.append(row)
    }
    return rows
}

// MARK: - Date Parsing

let isoFrac: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
}()

let isoBasic: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    return f
}()

func parseDate(_ s: String?) -> Date? {
    guard let s else { return nil }
    return isoFrac.date(from: s) ?? isoBasic.date(from: s)
}

func parseDateOrNow(_ s: String?) -> Date {
    parseDate(s) ?? Date()
}

// MARK: - Row Field Helpers

extension [String: String?] {
    /// Returns the value, flattening the double-optional from subscripting [Key: Value?]
    func str(_ key: String) -> String? {
        guard let outer = self[key] else { return nil }
        return outer
    }

    func req(_ key: String, fallback: String = "") -> String {
        str(key) ?? fallback
    }

    func int(_ key: String) -> Int? {
        str(key).flatMap(Int.init)
    }

    func dbl(_ key: String) -> Double? {
        str(key).flatMap(Double.init)
    }

    func bool(_ key: String) -> Bool {
        str(key).flatMap(Int.init).map { $0 != 0 } ?? false
    }

    func date(_ key: String) -> Date? {
        parseDate(str(key))
    }

    func dateOrNow(_ key: String) -> Date {
        parseDateOrNow(str(key))
    }
}
