import Foundation
import JobhuntCore

/// Sort logic ported from sort.js.
/// Empty/nil values always sort to the bottom, regardless of ascending/descending direction.
enum JobsSortLogic {
    static func sorted(_ jobs: [Job], key: JobsSortKey, ascending: Bool) -> [Job] {
        jobs.sorted { a, b in
            // Missing-ness is decided BEFORE direction, or the guarantee above is a lie in one of the
            // two directions. The comparators encode "nil sorts after", and flipping the whole result
            // for descending flipped that too: sorting by fit score, high to low, put every UNSCORED
            // job above the best match. Caught in the demo, where an accidentally-captured news
            // article outranked an 86.
            let aEmpty = isMissing(a, key: key)
            let bEmpty = isMissing(b, key: key)
            if aEmpty != bEmpty { return bEmpty }

            switch compare(a, b, key: key) {
            case .orderedSame: return false
            case .orderedAscending: return ascending
            case .orderedDescending: return !ascending
            }
        }
    }

    /// Has this job no value at all for the sort key? Mirrors what the comparators treat as empty —
    /// including the display fallbacks, so an un-extracted job that still shows a page title is not
    /// counted as missing a title.
    private static func isMissing(_ job: Job, key: JobsSortKey) -> Bool {
        func blank(_ s: String?) -> Bool {
            (s ?? "").trimmingCharacters(in: .whitespaces).isEmpty
        }
        switch key {
        case .jobNumber: return job.jobNumber == nil
        case .company: return blank(job.displayCompany)
        case .title: return blank(job.displayTitle)
        case .fitScore: return job.fitScore == nil
        case .rating: return job.rating == nil
        case .salaryMin: return job.salaryMin == nil
        case .salaryMax: return job.salaryMax == nil
        case .location: return blank(job.location)
        case .extractedAt: return job.extractedAt == nil
        case .lastOpenedAt: return job.lastOpenedAt == nil
        // Always present: status is non-optional and capturedAt falls back to createdAt.
        case .status, .capturedAt: return false
        }
    }

    private static func compare(_ a: Job, _ b: Job, key: JobsSortKey) -> ComparisonResult {
        switch key {
        case .jobNumber:
            compareOptionalInt(a.jobNumber, b.jobNumber)
        case .company:
            // Fall back to the capture host so un-extracted jobs sort by a real value (TASK-525).
            compareOptionalString(a.displayCompany, b.displayCompany)
        case .title:
            // Fall back to the captured page title rather than collapsing every un-extracted job to
            // the bottom (TASK-525).
            compareOptionalString(a.displayTitle, b.displayTitle)
        case .status:
            compareString(a.status.rawValue, b.status.rawValue)
        case .fitScore:
            compareOptionalInt(a.fitScore, b.fitScore)
        case .rating:
            compareOptionalInt(a.rating, b.rating)
        case .salaryMin:
            compareOptionalInt(a.salaryMin, b.salaryMin)
        case .salaryMax:
            compareOptionalInt(a.salaryMax, b.salaryMax)
        case .location:
            compareOptionalString(a.location, b.location)
        case .capturedAt:
            compareDate(a.capturedAtDenormalized ?? a.createdAt, b.capturedAtDenormalized ?? b.createdAt)
        case .extractedAt:
            compareOptionalDate(a.extractedAt, b.extractedAt)
        case .lastOpenedAt:
            compareOptionalDate(a.lastOpenedAt, b.lastOpenedAt)
        }
    }

    // MARK: - Helpers

    /// Numeric: nil → bottom.
    private static func compareOptionalInt(_ a: Int?, _ b: Int?) -> ComparisonResult {
        switch (a, b) {
        case (nil, nil): return .orderedSame
        case (nil, _): return .orderedDescending // a nil → a sorts after b (bottom)
        case (_, nil): return .orderedAscending // b nil → b sorts after a (bottom)
        case let (av?, bv?):
            if av < bv { return .orderedAscending }
            if av > bv { return .orderedDescending }
            return .orderedSame
        }
    }

    /// Date: nil → bottom.
    private static func compareOptionalDate(_ a: Date?, _ b: Date?) -> ComparisonResult {
        switch (a, b) {
        case (nil, nil): .orderedSame
        case (nil, _): .orderedDescending
        case (_, nil): .orderedAscending
        case let (av?, bv?):
            av.compare(bv)
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
