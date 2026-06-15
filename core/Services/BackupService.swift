import Foundation
import SQLite3
import SwiftData

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
        case incompatibleStore(String)

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
            case .incompatibleStore:
                return "This backup isn't compatible with this version of Jobhunt and can't be restored. "
                    + "It may have been created by a newer version or be corrupted."
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

    /// Companion file alongside `storeURL`, e.g. `companion(of: store, suffix: "-wal")`.
    private static func companion(of storeURL: URL, suffix: String) -> URL {
        storeURL.deletingLastPathComponent()
            .appendingPathComponent(storeURL.lastPathComponent + suffix)
    }

    /// Opens `url` with the current `Schema` + `JobhuntMigrationPlan` to prove the app can
    /// actually load it after a restore. `isValidSQLite` only checks the SQLite magic header and
    /// table names; a backup from an incompatible or future schema passes that check but would
    /// then fail at the next app launch — *after* it had already replaced the live store.
    ///
    /// The probe runs on a throwaway copy so that opening it (which may run a migration and write
    /// a `-wal`) never dirties the staged file we're about to move into place.
    private static func validateOpensWithMigrationPlan(at url: URL) throws {
        let fm = FileManager.default
        let probeDir = fm.temporaryDirectory
            .appendingPathComponent("jobhunt-restore-probe-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: probeDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: probeDir) }

        let probeURL = probeDir.appendingPathComponent("probe.store")
        try fm.copyItem(at: url, to: probeURL)

        do {
            let schema = Schema(SchemaV1.models)
            let config = ModelConfiguration(schema: schema, url: probeURL, cloudKitDatabase: .none)
            _ = try ModelContainer(for: schema, migrationPlan: JobhuntMigrationPlan.self, configurations: config)
        } catch {
            throw BackupError.incompatibleStore(error.localizedDescription)
        }
    }

    /// Replaces the store files at `storeURL` with `backupURL`.
    ///
    /// Companion `-shm` and `-wal` files are removed so SwiftData starts from a clean checkpoint.
    /// The caller is responsible for creating an auto-backup before calling this, and for
    /// terminating the app after the restore since the in-memory container still points at the
    /// old store.
    ///
    /// Safety: the restore never destroys the live store before the replacement is in place.
    ///  1. The backup is copied to a staged `.incoming` file.
    ///  2. The staged copy is opened with the current schema + migration plan; an incompatible or
    ///     future-version backup is rejected here, before anything live is touched (TASK-373).
    ///  3. The live store and its `-wal`/`-shm` companions are moved *aside* (not deleted), the
    ///     staged copy is moved into place, and only on full success are the set-aside originals
    ///     discarded. Any failure rolls the originals back, so a mid-restore error can never leave
    ///     the user without a store (TASK-374).
    ///
    /// - Parameters:
    ///   - backupURL: Path to a valid backup produced by `backup(storeURL:to:)`.
    ///   - storeURL: Destination — the live production store to overwrite.
    public static func restore(from backupURL: URL, to storeURL: URL) throws {
        guard isValidSQLite(at: backupURL) else {
            throw BackupError.notValidSQLite(backupURL)
        }

        let fm = FileManager.default

        // Stage 1: stage the backup next to the live store. Nothing live is touched yet.
        let incomingURL = companion(of: storeURL, suffix: ".incoming")
        try? fm.removeItem(at: incomingURL)
        try fm.copyItem(at: backupURL, to: incomingURL)

        // Stage 2: prove the staged copy opens under the current schema + migration plan, so a
        // schema-incompatible/future/corrupt backup is rejected before the live store is replaced.
        do {
            try validateOpensWithMigrationPlan(at: incomingURL)
        } catch {
            try? fm.removeItem(at: incomingURL)
            throw error
        }

        // Stage 3: move the live store + WAL/SHM companions ASIDE (don't delete yet) so any
        // failure below can roll them back. Companions are hyphen-suffixed, as SQLite creates them
        // ("jobhunt.store-wal", not "jobhunt.store.wal").
        let walURL = companion(of: storeURL, suffix: "-wal")
        let shmURL = companion(of: storeURL, suffix: "-shm")
        let storeAside = companion(of: storeURL, suffix: ".old")
        let walAside = companion(of: storeURL, suffix: ".old-wal")
        let shmAside = companion(of: storeURL, suffix: ".old-shm")
        // Clear any leftovers from a previously interrupted restore.
        for url in [storeAside, walAside, shmAside] { try? fm.removeItem(at: url) }

        var undo: [(restoreTo: URL, from: URL)] = []
        func moveAside(_ from: URL, to aside: URL) throws {
            guard fm.fileExists(atPath: from.path) else { return }
            try fm.moveItem(at: from, to: aside)
            undo.append((restoreTo: from, from: aside))
        }

        do {
            try moveAside(storeURL, to: storeAside)
            try moveAside(walURL, to: walAside)
            try moveAside(shmURL, to: shmAside)
            // Stage 4: move the staged replacement into place.
            try fm.moveItem(at: incomingURL, to: storeURL)
        } catch {
            // Roll back: put the originals back where they were, drop the staged copy.
            for step in undo.reversed() {
                try? fm.removeItem(at: step.restoreTo) // remove any partial new file
                try? fm.moveItem(at: step.from, to: step.restoreTo)
            }
            try? fm.removeItem(at: incomingURL)
            throw error
        }

        // Stage 5: success — discard the set-aside originals. The restored store is a self-contained
        // VACUUM INTO file, so it has no companions (clean checkpoint).
        for url in [storeAside, walAside, shmAside] { try? fm.removeItem(at: url) }
    }
}
