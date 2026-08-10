import Foundation

/// Which windows get a minimum size, and what it is (TASK-557).
///
/// The decision lives in Core, away from AppKit, for one practical reason: the app target has no
/// unit-test target (only XCUITest, which needs a graphical session), so a rule written against
/// `NSWindow` can't be tested at all. Expressed as plain inputs, it can.
///
/// `app/Platform/WindowPolicy.swift` is the adapter: it reads the flags off each `NSWindow` and
/// applies the answer.
public enum WindowSizePolicy {
    /// Below this the sidebar and detail panes overlap into unusability.
    public static let minimumWidth: Double = 900
    public static let minimumHeight: Double = 600

    /// Whether this window should get the floor.
    ///
    /// A floor, never a resize: a user's restored larger window is left exactly as they left it.
    /// Panels, sheets and the Settings scene are excluded — they size themselves from their content,
    /// and forcing 900×600 on the Settings window would make it enormous.
    public static func shouldConstrain(
        isTitled: Bool,
        isResizable: Bool,
        isPanel: Bool,
        identifier: String?
    ) -> Bool {
        guard isTitled, isResizable, !isPanel else { return false }
        return identifier != settingsWindowIdentifier
    }

    /// SwiftUI's Settings scene window. Matched by identifier because there's no public type to
    /// check against.
    public static let settingsWindowIdentifier = "com_apple_SwiftUI_Settings_window"
}
