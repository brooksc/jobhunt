import Foundation
import SQLite3

/// Full-fidelity backup and restore for the SwiftData store.
///
/// CSV export covers a subset of jobs; this service copies the underlying SQLite store so that
/// ALL user data (captures, jobs, related records, resumes, sites, settings, LLM history) can
/// be restored from the backup file.
///
/// Usage:
///   let storeURL = container.configurations.first!.url
///   try BackupService.backup(storeURL: storeURL, to: destinationURL)
public enum BackupService {
    public enum BackupError: LocalizedError {
        case storeNotFound(URL)
        case sqliteOpenFailed(Int32)
        case vacuumFailed(String)
        case notValidSQLite(URL)

        public var errorDescription: String? {
            switch self {
            case .storeNotFound(let url):
                return "Store not found at \(url.path)"
            case .sqliteOpenFailed(let code):
                return "Could not open store database (SQLite error \(code))"
            case .vacuumFailed(let msg):
                return "Backup failed: \(msg)"
            case .notValidSQLite(let url):
                return "Not a valid SQLite database: \(url.lastPathComponent)"
            }
        }
    }

    /// Creates a full-fidelity backup of the SwiftData store at `storeURL` to `destinationURL`.
    ///
    /// Uses `VACUUM INTO` which creates a self-contained, defragmented copy of the database.
    /// WAL files are checkpointed internally — the result is a single portable file that can
    /// be opened as a valid SQLite database without any companion `-shm`/`-wal` files.
    ///
    /// - Parameters:
    ///   - storeURL: URL of the production SwiftData store (e.g. from `container.configurations.first?.url`).
    ///   - destinationURL: Where to write the backup. The file must not already exist.
    public static func backup(storeURL: URL, to destinationURL: URL) throws {
        guard FileManager.default.fileExists(atPath: storeURL.path) else {
            throw BackupError.storeNotFound(storeURL)
        }

        // Ensure destination directory exists
        try FileManager.default.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        // Open source read-only so we never modify the live store
        var db: OpaquePointer?
        let openRC = sqlite3_open_v2(storeURL.path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil)
        guard openRC == SQLITE_OK, let db else {
            throw BackupError.sqliteOpenFailed(openRC)
        }
        defer { sqlite3_close(db) }

        // VACUUM INTO checkpoints WAL and writes a complete, self-contained copy
        let escaped = destinationURL.path.replacingOccurrences(of: "'", with: "''")
        let sql = "VACUUM INTO '\(escaped)'"
        var errMsg: UnsafeMutablePointer<CChar>?
        let vacRC = sqlite3_exec(db, sql, nil, nil, &errMsg)
        if vacRC != SQLITE_OK {
            let msg = errMsg.map { String(cString: $0) } ?? "SQLite error \(vacRC)"
            sqlite3_free(errMsg)
            throw BackupError.vacuumFailed(msg)
        }
        sqlite3_free(errMsg)
    }

    /// Returns true if `url` points to a file that begins with the SQLite magic header AND
    /// contains at least one expected Jobhunt table (ZJOB, ZRESUME, or ZCAPTURE).
    ///
    /// The table check guards against restoring an arbitrary SQLite database that has no
    /// Jobhunt schema — the SQLite magic header alone is insufficient.
    public static func isValidSQLite(at url: URL) -> Bool {
        // Step 1: Check SQLite magic header (first 16 bytes)
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        let magic = "SQLite format 3\0".utf8.prefix(16)
        guard let data = try? handle.read(upToCount: 16), data.count == 16 else { return false }
        guard data.elementsEqual(magic) else { return false }

        // Step 2: Check for at least one expected Jobhunt table
        var db: OpaquePointer?
        let openRC = sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil)
        guard openRC == SQLITE_OK, let db else { return false }
        defer { sqlite3_close(db) }

        let sql = "SELECT count(*) FROM sqlite_master WHERE type='table' AND name IN ('ZJOB','ZRESUME','ZCAPTURE')"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { return false }
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_step(stmt) == SQLITE_ROW else { return false }
        return sqlite3_column_int(stmt, 0) > 0
    }

    /// Replaces the store files at `storeURL` with `backupURL`.
    ///
    /// Companion `-shm` and `-wal` files are removed so SwiftData starts from a clean checkpoint.
    /// The caller is responsible for creating an auto-backup before calling this, and for
    /// terminating the app after the restore since the in-memory container still points at the
    /// old store.
    ///
    /// Safety: the backup is copied to a temp file first. The original store and its companions
    /// are only removed after the copy succeeds. This prevents data loss if the copy fails
    /// mid-operation.
    ///
    /// - Parameters:
    ///   - backupURL: Path to a valid backup produced by `backup(storeURL:to:)`.
    ///   - storeURL: Destination — the live production store to overwrite.
    public static func restore(from backupURL: URL, to storeURL: URL) throws {
        guard isValidSQLite(at: backupURL) else {
            throw BackupError.notValidSQLite(backupURL)
        }

        let fm = FileManager.default

        // Stage 1: Copy backup to a temp file in the same directory as the store.
        // This ensures we have a valid replacement before touching the live store.
        let incomingURL = URL(fileURLWithPath: storeURL.path + ".incoming")
        if fm.fileExists(atPath: incomingURL.path) {
            try fm.removeItem(at: incomingURL)
        }
        try fm.copyItem(at: backupURL, to: incomingURL)

        // Stage 2: Remove WAL/SHM companions (hyphen-separated, as SQLite actually creates them:
        // e.g. "jobhunt.store-wal" and "jobhunt.store-shm", not "jobhunt.store.wal")
        let walFile = storeURL.deletingLastPathComponent()
            .appendingPathComponent(storeURL.lastPathComponent + "-wal")
        let shmFile = storeURL.deletingLastPathComponent()
            .appendingPathComponent(storeURL.lastPathComponent + "-shm")
        for companion in [walFile, shmFile] {
            if fm.fileExists(atPath: companion.path) {
                try fm.removeItem(at: companion)
            }
        }

        // Stage 3: Remove the old store and move the staged replacement into place
        if fm.fileExists(atPath: storeURL.path) {
            try fm.removeItem(at: storeURL)
        }
        try fm.moveItem(at: incomingURL, to: storeURL)
    }
}
