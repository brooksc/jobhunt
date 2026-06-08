import JobhuntCore
import SwiftUI

@Observable
public final class Theme {
    public var colorSchemePreference: ColorSchemePreference = .auto

    public enum ColorSchemePreference: String, CaseIterable {
        case light, dark, auto

        var label: String {
            switch self {
            case .light: "Light"
            case .dark: "Dark"
            case .auto: "System"
            }
        }

        var systemImage: String {
            switch self {
            case .light: "sun.max"
            case .dark: "moon"
            case .auto: "circle.lefthalf.filled"
            }
        }
    }

    public init() {}

    /// Design tokens matching styles.css
    public static let accent = Color(red: 0x5E / 255, green: 0x6A / 255, blue: 0xD2 / 255)

    /// Status colors matching styles.css status palette
    public static func statusColor(_ status: JobStatus) -> Color {
        switch status {
        case .saved: Color(red: 0x6B / 255, green: 0x72 / 255, blue: 0x80 / 255)
        case .applied: Color(red: 0x3B / 255, green: 0x82 / 255, blue: 0xF6 / 255)
        case .interview: Color(red: 0x8B / 255, green: 0x5C / 255, blue: 0xF6 / 255)
        case .offer: Color(red: 0x10 / 255, green: 0xB9 / 255, blue: 0x81 / 255)
        case .rejected: Color(red: 0xEF / 255, green: 0x44 / 255, blue: 0x44 / 255)
        case .archived: Color(red: 0x37 / 255, green: 0x41 / 255, blue: 0x51 / 255)
        case .notAvailable: Color(red: 0xF5 / 255, green: 0x9E / 255, blue: 0x0B / 255)
        case .duplicate: Color(red: 0xF5 / 255, green: 0xDD / 255, blue: 0x0B / 255)
        }
    }

    public static func statusSymbol(_ status: JobStatus) -> String {
        switch status {
        case .saved: "bookmark"
        case .applied: "paperplane"
        case .interview: "person.2"
        case .offer: "star.fill"
        case .rejected: "xmark.circle"
        case .archived: "archivebox"
        case .notAvailable: "exclamationmark.triangle"
        case .duplicate: "doc.on.doc"
        }
    }

    public static func extractionColor(_ status: ExtractionStatus) -> Color {
        switch status {
        case .pending: Color(red: 0x6B / 255, green: 0x72 / 255, blue: 0x80 / 255)
        case .running: Color(red: 0x3B / 255, green: 0x82 / 255, blue: 0xF6 / 255)
        case .succeeded: Color(red: 0x10 / 255, green: 0xB9 / 255, blue: 0x81 / 255)
        case .failed: Color(red: 0xEF / 255, green: 0x44 / 255, blue: 0x44 / 255)
        case .skipped: Color(red: 0xF5 / 255, green: 0x9E / 255, blue: 0x0B / 255)
        }
    }
}
