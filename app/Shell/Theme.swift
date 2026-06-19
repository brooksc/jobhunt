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

    /// Use the system accent color for UI highlights (adapts to user's accent preference).
    public static let accent: Color = .accentColor

    /// Adaptive status colors — light/dark variants for WCAG contrast compliance.
    public static func statusColor(_ status: JobStatus) -> Color {
        switch status {
        case .new: adaptive(light: 0x6B7280, dark: 0x9CA3AF)
        case .pursuing: adaptive(light: 0x0369A1, dark: 0x38BDF8)
        case .applied: adaptive(light: 0x2563EB, dark: 0x60A5FA)
        case .interview: adaptive(light: 0x7C3AED, dark: 0xA78BFA)
        case .offer: adaptive(light: 0x059669, dark: 0x34D399)
        case .rejected: adaptive(light: 0xDC2626, dark: 0xF87171)
        case .passed: adaptive(light: 0x6B7280, dark: 0x9CA3AF)
        case .archived: adaptive(light: 0x6B7280, dark: 0x9CA3AF)
        case .closed: adaptive(light: 0xD97706, dark: 0xFCD34D)
        case .duplicate: adaptive(light: 0xB45309, dark: 0xFDE68A)
        case .expired: adaptive(light: 0x9CA3AF, dark: 0x6B7280)
        }
    }

    public static func statusSymbol(_ status: JobStatus) -> String {
        switch status {
        case .new: "sparkle"
        case .pursuing: "bookmark"
        case .applied: "paperplane"
        case .interview: "person.2"
        case .offer: "star.fill"
        case .rejected: "xmark.circle"
        case .passed: "hand.raised"
        case .archived: "archivebox"
        case .closed: "exclamationmark.triangle"
        case .duplicate: "doc.on.doc"
        case .expired: "clock.badge.xmark"
        }
    }

    public static func extractionColor(_ status: ExtractionStatus) -> Color {
        switch status {
        case .pending: adaptive(light: 0x6B7280, dark: 0x9CA3AF)
        case .running: adaptive(light: 0x2563EB, dark: 0x60A5FA)
        case .succeeded: adaptive(light: 0x059669, dark: 0x34D399)
        case .failed: adaptive(light: 0xDC2626, dark: 0xF87171)
        case .skipped: adaptive(light: 0xD97706, dark: 0xFCD34D)
        }
    }

    // MARK: - Private helpers

    /// Build an adaptive Color from 0xRRGGBB integer literals.
    private static func adaptive(light: Int, dark: Int) -> Color {
        Color(nsColor: NSColor(
            name: nil,
            dynamicProvider: { appearance in
                let useDark = appearance.bestMatch(from: [.darkAqua, .vibrantDark]) != nil
                let hex = useDark ? dark : light
                return NSColor(
                    red: CGFloat((hex >> 16) & 0xFF) / 255,
                    green: CGFloat((hex >> 8) & 0xFF) / 255,
                    blue: CGFloat(hex & 0xFF) / 255,
                    alpha: 1
                )
            }
        ))
    }
}
