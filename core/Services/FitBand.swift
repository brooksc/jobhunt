import Foundation

/// The qualitative band a fit score falls into (TASK-506).
///
/// One definition, because the colour and the spoken label have to agree. They were duplicated
/// across the fit ring and the fit pill — three copies of the same thresholds, so a sighted user
/// could see "green" while VoiceOver said "partial fit" as soon as one copy moved. (The pill has
/// since gone; the reason for keeping one definition hasn't.)
public enum FitBand: String, CaseIterable, Sendable {
    case strong
    case good
    case partial
    case low

    public static func band(for score: Int) -> FitBand {
        switch score {
        case 85...: .strong
        case 70 ..< 85: .good
        case 55 ..< 70: .partial
        default: .low
        }
    }

    /// The words a sighted user reads on the pill, and the ones VoiceOver speaks.
    public var label: String {
        switch self {
        case .strong: "Strong fit"
        case .good: "Good fit"
        case .partial: "Partial fit"
        case .low: "Low fit"
        }
    }

    /// What a fit ring or pill should announce: the number *and* the band.
    ///
    /// Both, not either. The number alone means nothing without knowing the scale, and the band
    /// alone loses the distinction between a 55 and a 69.
    public static func accessibilityLabel(score: Int) -> String {
        "Fit score \(score) out of 100, \(band(for: score).label)"
    }

    /// A ring with no score is a real state — the job hasn't been scored yet — and must not read as
    /// zero.
    public static let unscoredAccessibilityLabel = "Not yet scored for fit"
}

/// A requirement's verdict, for display (TASK-506 #3).
///
/// Colour alone carried this: green tick, orange, red. `RequirementVerdictDisplay` adds a distinct
/// symbol and a spoken label so the state survives both colour-blindness and VoiceOver.
public enum RequirementVerdictDisplay: String, CaseIterable, Sendable {
    case met
    case partial
    case missing

    public init?(status: String) {
        switch status.lowercased() {
        case "met": self = .met
        case "partial": self = .partial
        case "missing": self = .missing
        default: return nil
        }
    }

    /// Distinct *shapes*, not just distinct colours — a tick, a half-circle and a cross are
    /// tellable apart in greyscale.
    public var systemImage: String {
        switch self {
        case .met: "checkmark.circle.fill"
        case .partial: "circle.lefthalf.filled"
        case .missing: "xmark.circle"
        }
    }

    public var label: String {
        switch self {
        case .met: "Met"
        case .partial: "Partially met"
        case .missing: "Not met"
        }
    }

    public func accessibilityLabel(requirement: String) -> String {
        "\(label): \(requirement)"
    }
}
