import CryptoKit
import Foundation

/// The order a market pass walks the directory in (TASK-701).
///
/// Two problems solved by one thing.
///
/// **Relevance.** The directory is alphabetical by vendor, so an unordered pass spends its first
/// hours on `0x`, `100x`, `103644278`. With a daily ingest cap metering the results, the user would
/// wait days for anything they recognise. Companies they already have jobs from go first.
///
/// **Cursor integrity.** The sweep's checkpoint is an *index*, so the list it indexes into must be
/// identical on resume or the cursor silently points at a different board — skipping some and
/// re-reading others, with no error anywhere. That rules out ordering by anything that changes
/// while the sweep runs, and the user's library grows as the sweep ingests. So the priority set is
/// captured once when a pass starts, persisted, and replayed on every resume; `revision` then
/// fingerprints the finished order so a mismatch is detectable rather than silent.
public enum MarketBoardOrder {
    /// Where a board sits in the walk. Lower goes first.
    ///
    /// Vendor speed is the tiebreaker rather than a goal in itself: Greenhouse, Lever and Ashby
    /// answer in ~70 ms and Workday in ~800 ms, so putting the fast ones first means far more of
    /// the market is covered in the early hours of a pass — which matters precisely because a pass
    /// may be interrupted.
    static func tier(_ board: MarketBoard, priority: Set<String>) -> Int {
        let isPriority = priority.contains(priorityKey(board))
        let isFast = board.kind != "workday"
        switch (isPriority, isFast) {
        case (true, true): return 0
        case (true, false): return 1
        case (false, true): return 2
        case (false, false): return 3
        }
    }

    /// How a board is matched against the user's companies. Workday boards are URLs, so the tenant
    /// is the closest thing to a company name they carry.
    public static func priorityKey(_ board: MarketBoard) -> String {
        if board.kind == "workday", let url = URL(string: board.slug), let host = url.host {
            return CompanyNameKey.normalize(host.split(separator: ".").first.map(String.init) ?? "")
        }
        return CompanyNameKey.normalize(board.slug)
    }

    /// A stable order. Pure: the same inputs always produce the same list, which is what lets a
    /// persisted index mean the same thing tomorrow.
    public static func ordered(_ boards: [MarketBoard], priority: Set<String>) -> [MarketBoard] {
        boards.sorted { lhs, rhs in
            let (left, right) = (tier(lhs, priority: priority), tier(rhs, priority: priority))
            if left != right {
                return left < right
            }
            if lhs.kind != rhs.kind {
                return lhs.kind < rhs.kind
            }
            return lhs.slug < rhs.slug
        }
    }

    /// Fingerprint of an ordered list.
    ///
    /// Compared on resume: if it differs, the persisted cursor indexes into a list that no longer
    /// exists and cannot be trusted. Covers order as well as membership, since a reordered list of
    /// the same boards breaks a positional cursor just as thoroughly as a resized one.
    public static func revision(_ boards: [MarketBoard]) -> String {
        var hasher = SHA256()
        for board in boards {
            hasher.update(data: Data("\(board.kind)\u{1F}\(board.slug)\u{1E}".utf8))
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
