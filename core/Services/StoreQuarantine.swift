import Foundation

/// Moves a corrupt SwiftData store aside so the app can start fresh without destroying the user's
/// data.
///
/// The previous implementation did all four moves with `try?` and then terminated regardless. If the
/// main store couldn't be moved — permissions, a locked file, a name collision — the app quit anyway
/// and relaunched straight back into the same corrupt store, with nothing said. A recovery action
/// that silently fails turns into a loop, and this one is also making a promise to the user: the
/// dialog says the store will be *moved aside, not permanently deleted*.
public enum StoreQuarantine {
    /// Injectable file operations, so the failure paths can be tested without arranging a locked file
    /// or an unwritable directory on a real disk.
    public struct FileOps: Sendable {
        public var exists: @Sendable (URL) -> Bool
        public var move: @Sendable (URL, URL) throws -> Void
        public var remove: @Sendable (URL) throws -> Void

        public init(
            exists: @escaping @Sendable (URL) -> Bool,
            move: @escaping @Sendable (URL, URL) throws -> Void,
            remove: @escaping @Sendable (URL) throws -> Void
        ) {
            self.exists = exists
            self.move = move
            self.remove = remove
        }

        public static let live = FileOps(
            exists: { FileManager.default.fileExists(atPath: $0.path) },
            move: { try FileManager.default.moveItem(at: $0, to: $1) },
            remove: { try FileManager.default.removeItem(at: $0) }
        )
    }

    public struct Outcome: Equatable {
        /// Where the corrupt store now lives, so the UI can tell the user where to find it.
        public let movedAside: URL
        /// Companions that could be neither moved nor deleted. Non-empty means a stale `-wal`/`-shm`
        /// may still sit beside the new store, which SQLite could try to replay into it.
        public let strandedCompanions: [String]
    }

    public enum QuarantineError: LocalizedError, Equatable {
        case mainStoreMoveFailed(reason: String)

        public var errorDescription: String? {
            switch self {
            case let .mainStoreMoveFailed(reason):
                "Couldn't move the damaged database aside, so nothing was changed: \(reason)"
            }
        }
    }

    /// Move `storeURL` and its SQLite companions to a uniquely-named sibling.
    ///
    /// Throws if the main store exists and cannot be moved — the caller must then stay in recovery
    /// rather than restarting into the same failure. A missing main store is not an error: there is
    /// nothing to preserve, and starting fresh is exactly what the user asked for.
    @discardableResult
    public static func moveAside(
        storeURL: URL,
        ops: FileOps = .live,
        timestamp: Date = Date(),
        token: String = UUID().uuidString
    ) throws -> Outcome {
        let directory = storeURL.deletingLastPathComponent()
        // Second-resolution alone collides when recovery is retried inside the same second, which is
        // exactly when it is most likely to be retried. The short token makes that impossible.
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        formatter.timeZone = TimeZone(identifier: "UTC")
        let suffix = "corrupt-\(formatter.string(from: timestamp))-\(token.prefix(8))"
        let asideURL = directory.appendingPathComponent("\(storeURL.lastPathComponent).\(suffix)")

        if ops.exists(storeURL) {
            do {
                try ops.move(storeURL, asideURL)
            } catch {
                throw QuarantineError.mainStoreMoveFailed(reason: error.localizedDescription)
            }
        }

        // Companions are best-effort to MOVE but must not be left behind: a `-wal` beside a brand-new
        // store is not inert, SQLite may try to replay it. If the move fails, delete instead — the
        // data it belongs to has already gone with the main file, so there is nothing left to lose.
        var stranded: [String] = []
        for suffix in ["-wal", "-shm"] {
            let companion = directory.appendingPathComponent(storeURL.lastPathComponent + suffix)
            guard ops.exists(companion) else { continue }
            let destination = directory.appendingPathComponent(asideURL.lastPathComponent + suffix)
            do {
                try ops.move(companion, destination)
            } catch {
                do {
                    try ops.remove(companion)
                } catch {
                    stranded.append(suffix)
                }
            }
        }

        return Outcome(movedAside: asideURL, strandedCompanions: stranded)
    }
}
