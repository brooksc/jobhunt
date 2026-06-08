import SwiftUI
import JobhuntCore

@Observable
public final class Theme {
    public var colorSchemePreference: ColorSchemePreference = .auto

    public enum ColorSchemePreference: String, CaseIterable {
        case light, dark, auto

        var label: String {
            switch self {
            case .light: return "Light"
            case .dark: return "Dark"
            case .auto: return "System"
            }
        }

        var systemImage: String {
            switch self {
            case .light: return "sun.max"
            case .dark: return "moon"
            case .auto: return "circle.lefthalf.filled"
            }
        }
    }

    public init() {}

    // Design tokens matching styles.css
    public static let accent = Color(red: 0x5E / 255, green: 0x6A / 255, blue: 0xD2 / 255)

    // Status colors matching styles.css status palette
    public static func statusColor(_ status: JobStatus) -> Color {
        switch status {
        case .saved: return Color(red: 0x6B / 255, green: 0x72 / 255, blue: 0x80 / 255)
        case .applied: return Color(red: 0x3B / 255, green: 0x82 / 255, blue: 0xF6 / 255)
        case .interview: return Color(red: 0x8B / 255, green: 0x5C / 255, blue: 0xF6 / 255)
        case .offer: return Color(red: 0x10 / 255, green: 0xB9 / 255, blue: 0x81 / 255)
        case .rejected: return Color(red: 0xEF / 255, green: 0x44 / 255, blue: 0x44 / 255)
        case .archived: return Color(red: 0x37 / 255, green: 0x41 / 255, blue: 0x51 / 255)
        case .notAvailable: return Color(red: 0xF5 / 255, green: 0x9E / 255, blue: 0x0B / 255)
        case .duplicate: return Color(red: 0xF5 / 255, green: 0xDD / 255, blue: 0x0B / 255)
        }
    }

    public static func statusSymbol(_ status: JobStatus) -> String {
        switch status {
        case .saved: return "bookmark"
        case .applied: return "paperplane"
        case .interview: return "person.2"
        case .offer: return "star.fill"
        case .rejected: return "xmark.circle"
        case .archived: return "archivebox"
        case .notAvailable: return "exclamationmark.triangle"
        case .duplicate: return "doc.on.doc"
        }
    }

    public static func extractionColor(_ status: ExtractionStatus) -> Color {
        switch status {
        case .pending: return Color(red: 0x6B / 255, green: 0x72 / 255, blue: 0x80 / 255)
        case .running: return Color(red: 0x3B / 255, green: 0x82 / 255, blue: 0xF6 / 255)
        case .succeeded: return Color(red: 0x10 / 255, green: 0xB9 / 255, blue: 0x81 / 255)
        case .failed: return Color(red: 0xEF / 255, green: 0x44 / 255, blue: 0x44 / 255)
        case .skipped: return Color(red: 0xF5 / 255, green: 0x9E / 255, blue: 0x0B / 255)
        }
    }
}
