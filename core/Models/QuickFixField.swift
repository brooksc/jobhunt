import Foundation

/// The fields a data-quality issue can be fixed by simply typing the value in (TASK-503 #2).
///
/// The screen's only remedy used to be re-extraction, which re-fails identically on a posting whose
/// source URL has gone — leaving Mark Reviewed, which hides the row rather than fixing anything. For
/// a missing company or title the user is usually looking at the answer.
///
/// Only fields where free text IS the value. Work mode and salary are deliberately excluded: those
/// are a picker and a structured range, and a text box that silently accepts "120k-ish" would make
/// the data worse than the gap it filled.
public enum QuickFixField: String, CaseIterable, Sendable {
    case company
    case title
    case location

    public var label: String {
        switch self {
        case .company: "Company"
        case .title: "Title"
        case .location: "Location"
        }
    }

    /// The issue this field answers.
    public var kind: QualityIssueKind {
        switch self {
        case .company: .missingCompany
        case .title: .missingTitle
        case .location: .missingLocation
        }
    }

    /// Which fields are worth offering for a job carrying `kinds`, in a stable order.
    ///
    /// Empty when nothing here applies — a job whose only problem is a short capture or a stale
    /// extraction has nothing to type, and offering an empty form would be worse than offering
    /// nothing at all.
    public static func fields(for kinds: [QualityIssueKind]) -> [QuickFixField] {
        let present = Set(kinds)
        return allCases.filter { present.contains($0.kind) }
    }
}
