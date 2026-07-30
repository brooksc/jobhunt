import JobhuntCore
import SwiftUI

// MARK: - Keyboard shortcut catalog (TASK-499)

/// Single source of truth for the app's keyboard shortcuts. The menu `.keyboardShortcut(...)`
/// modifiers and the in-app Keyboard Shortcuts overlay are both driven from this catalog, so the
/// displayed help can't silently drift from the actual bindings (AC#12).
///
/// Note: a handful of shortcuts are handled outside SwiftUI's menu system — bare `?` (opens this
/// overlay) and ⌃Tab / ⌃⇧Tab (cycles job-detail tabs) go through an `NSEvent` monitor — but they are
/// still listed here so the overlay documents them. Their `key`/`modifiers` are informational for
/// those rows (see `isMenuCommand`).
enum ShortcutSection: String, CaseIterable, Identifiable {
    case navigation = "Navigation"
    case changeStatus = "Change Status"
    case jobActions = "Job Actions"
    case searchData = "Search & Data"
    case system = "System"

    var id: String {
        rawValue
    }
}

struct AppShortcut: Identifiable {
    let id: String
    let title: String
    let key: KeyEquivalent
    let modifiers: EventModifiers
    let section: ShortcutSection
    /// False for shortcuts driven by the NSEvent monitor rather than a menu command — the overlay
    /// still lists them, but they carry no `.keyboardShortcut` on a menu item.
    var isMenuCommand: Bool = true
    /// Pre-rendered glyph string for rows whose key can't be expressed as a single `KeyEquivalent`
    /// (e.g. "1–6", "Tab"). When nil the glyph is derived from `modifiers` + `key`.
    var glyphOverride: String?

    /// Human-readable key-combo glyph, e.g. "⌘⇧E", built from the same modifiers/key the menu uses.
    var glyph: String {
        var out = ""
        if modifiers.contains(.control) { out += "⌃" }
        if modifiers.contains(.option) { out += "⌥" }
        if modifiers.contains(.shift) { out += "⇧" }
        if modifiers.contains(.command) { out += "⌘" }
        out += glyphOverride ?? Self.keyGlyph(key)
        return out
    }

    private static func keyGlyph(_ key: KeyEquivalent) -> String {
        // KeyEquivalent is a struct (not an enum), so match on its Character.
        switch key.character {
        case "\u{7F}", "\u{08}": "⌫"
        case "\u{1B}": "⎋"
        case "\r": "↩"
        case "\t": "⇥"
        case " ": "Space"
        default: String(key.character).uppercased()
        }
    }
}

/// The status a ⌥-number "change status" shortcut applies, in shortcut order (⌥1…⌥6).
/// "Interested" is the user-facing name for `.pursuing`.
let statusShortcutOrder: [(key: KeyEquivalent, status: JobStatus, title: String)] = [
    ("1", .new, "New"),
    ("2", .pursuing, "Interested"),
    ("3", .applied, "Applied"),
    ("4", .interview, "Interview"),
    ("5", .offer, "Offer"),
    ("6", .rejected, "Rejected")
]

/// The Jobs-list filter a ⌘-number shortcut applies, in shortcut order (⌘1…⌘6).
/// `nil` status = All Jobs.
let filterShortcutOrder: [(key: KeyEquivalent, status: JobStatus?, title: String)] = [
    ("1", nil, "All Jobs"),
    ("2", .new, "New"),
    ("3", .pursuing, "Interested"),
    ("4", .applied, "Applied"),
    ("5", .interview, "Interview"),
    ("6", .offer, "Offer")
]

enum KeyboardShortcutCatalog {
    /// Every app-specific shortcut, grouped for the overlay. Order within a section is display order.
    static let all: [AppShortcut] = navigation + changeStatus + jobActions + searchData + system

    static let navigation: [AppShortcut] = [
        AppShortcut(
            id: "nav.jobsFilters", title: "All Jobs · New · Interested · Applied · Interview · Offer",
            key: "1", modifiers: .command, section: .navigation, glyphOverride: "1–6"
        ),
        AppShortcut(
            id: "nav.section",
            title: "Go to section (Dashboard, Jobs, Sites, …)",
            key: "1",
            modifiers: [.command, .control],
            section: .navigation,
            glyphOverride: "1–8"
        )
    ]

    static let changeStatus: [AppShortcut] = [
        AppShortcut(
            id: "status.set", title: "Set status: New · Interested · Applied · Interview · Offer · Rejected",
            key: "1", modifiers: .option, section: .changeStatus, glyphOverride: "1–6"
        ),
        AppShortcut(
            id: "status.interested",
            title: "Mark Interested",
            key: "i",
            modifiers: [.command, .control],
            section: .changeStatus
        ),
        AppShortcut(
            id: "status.archive",
            title: "Archive",
            key: "a",
            modifiers: [.command, .control],
            section: .changeStatus
        )
    ]

    static let jobActions: [AppShortcut] = [
        AppShortcut(id: "job.open", title: "Open Posting", key: "o", modifiers: .command, section: .jobActions),
        AppShortcut(
            id: "job.reextract",
            title: "Re-run Extraction",
            key: "r",
            modifiers: [.command, .control],
            section: .jobActions
        ),
        AppShortcut(
            id: "job.delete",
            title: "Delete",
            key: .delete,
            modifiers: .command,
            section: .jobActions,
            glyphOverride: "⌫"
        ),
        AppShortcut(
            id: "job.detailTabs",
            title: "Cycle detail tabs (forward / back)",
            key: .tab,
            modifiers: .control,
            section: .jobActions,
            isMenuCommand: false,
            glyphOverride: "⇥ / ⇧⇥"
        )
    ]

    static let searchData: [AppShortcut] = [
        AppShortcut(id: "data.add", title: "Add Job", key: "n", modifiers: .command, section: .searchData),
        AppShortcut(id: "data.find", title: "Find / Search Jobs", key: "f", modifiers: .command, section: .searchData),
        AppShortcut(
            id: "data.export",
            title: "Export Current List",
            key: "e",
            modifiers: [.command, .shift],
            section: .searchData
        )
    ]

    static let system: [AppShortcut] = [
        AppShortcut(
            id: "sys.shortcuts",
            title: "Keyboard Shortcuts",
            key: "?",
            modifiers: [],
            section: .system,
            isMenuCommand: false,
            glyphOverride: "?"
        ),
        AppShortcut(id: "sys.settings", title: "Settings", key: ",", modifiers: .command, section: .system)
    ]
}
