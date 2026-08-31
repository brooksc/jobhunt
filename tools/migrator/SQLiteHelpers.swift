import Foundation
import SQLite3

// Raw-SQLite helpers for repairs that must run BEFORE the store is opened via SwiftData —
// today only `RepairJobNumbers.swift` (a store with duplicate `jobNumber`s can't be opened at all).

// MARK: - Types

typealias DBHandle = OpaquePointer

// MARK: - DB Access

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
