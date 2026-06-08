import Foundation
import JobhuntCore

/// Sort logic ported from sort.js.
/// Empty/nil values always sort to the bottom, regardless of ascending/descending direction.
enum JobsSortLogic {
    static func sorted(_ jobs: [Job], key: JobsSortKey, ascending: Bool) -> [Job] {
        jobs.sorted { a, b in
            let comparison = compare(a, b, key: key)
            switch comparison {
            case .orderedSame: return false
            case .orderedAscending: return ascending
            case .orderedDescending: return !ascending
            }
        }
    }

    // swiftlint:disable:next cyclomatic_complexity
    private static func compare(_ a: Job, _ b: Job, key: JobsSortKey) -> ComparisonResult {
        switch key {
        case .jobNumber:
            return compareOptionalInt(a.jobNumber, b.jobNumber)
        case .company:
            return compareOptionalString(a.company, b.company)
        case .title:
            return compareOptionalString(a.title, b.title)
        case .status:
            return compareString(a.status.rawValue, b.status.rawValue)
        case .fitScore:
            return compareOptionalInt(a.fitScore, b.fitScore)
        case .rating:
            return compareOptionalInt(a.rating, b.rating)
        case .capturedAt:
            return compareDate(a.createdAt, b.createdAt)
        case .extractedAt:
            return compareOptionalDate(a.extractedAt, b.extractedAt)
        }
    }

    // MARK: - Helpers

    /// Numeric: nil → bottom.
    private static func compareOptionalInt(_ a: Int?, _ b: Int?) -> ComparisonResult {
        switch (a, b) {
        case (nil, nil): return .orderedSame
        case (nil, _): return .orderedDescending   // a nil → a sorts after b (bottom)
        case (_, nil): return .orderedAscending    // b nil → b sorts after a (bottom)
        case let (av, bv):
            let av = av!, bv = bv!
            if av < bv { return .orderedAscending }
            if av > bv { return .orderedDescending }
            return .orderedSame
        }
    }

    /// Date: nil → bottom.
    private static func compareOptionalDate(_ a: Date?, _ b: Date?) -> ComparisonResult {
        switch (a, b) {
        case (nil, nil): return .orderedSame
        case (nil, _): return .orderedDescending
        case (_, nil): return .orderedAscending
        case let (av, bv):
            return av!.compare(bv!)
        }
    }

    /// Non-optional date comparison.
    private static func compareDate(_ a: Date, _ b: Date) -> ComparisonResult {
        a.compare(b)
    }

    /// String: empty → bottom; locale-aware.
    private static func compareOptionalString(_ a: String?, _ b: String?) -> ComparisonResult {
        let av = a?.trimmingCharacters(in: .whitespaces) ?? ""
        let bv = b?.trimmingCharacters(in: .whitespaces) ?? ""
        let aEmpty = av.isEmpty
        let bEmpty = bv.isEmpty
        if aEmpty && bEmpty { return .orderedSame }
        if aEmpty { return .orderedDescending }
        if bEmpty { return .orderedAscending }
        return av.compare(bv, options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    private static func compareString(_ a: String, _ b: String) -> ComparisonResult {
        a.compare(b, options: [.caseInsensitive], locale: .current)
    }
}
