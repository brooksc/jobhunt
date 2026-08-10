import AppKit
import JobhuntCore

/// Applies the app's window-level policy — currently just a minimum size (TASK-557).
///
/// The floor used to be set once, inside `PlatformIntegration.start`, from `NSApp.mainWindow`. At
/// launch that is frequently `nil`: the SwiftUI scene hasn't produced a window yet, and `mainWindow`
/// is only non-nil once one has become key. So the policy applied or didn't depending on startup
/// timing, and when it didn't, nothing retried — the window could be dragged down to nothing.
///
/// Watching `didBecomeKey` instead makes it timing-independent: whichever window appears gets the
/// floor when it appears, including a window opened later.
///
/// Separate from `PlatformIntegration` on purpose. That type is the queue/notification adapter, and
/// window lifecycle has nothing to do with either; folding them together is what let a nil check in
/// a notification-setup path silently drop a UI guarantee.
@MainActor
public final class WindowPolicy {
    /// The numbers and the "which windows" rule live in Core (`WindowSizePolicy`) so they're
    /// testable — the app target has only XCUITest, which needs a graphical session.
    public static let minimumSize = NSSize(
        width: WindowSizePolicy.minimumWidth, height: WindowSizePolicy.minimumHeight
    )

    private var observer: (any NSObjectProtocol)?

    public init() {}

    /// Applies the floor to every current window and to each one as it becomes key.
    public func start(center: NotificationCenter = .default) {
        guard observer == nil else { return } // idempotent, like PlatformIntegration.start
        applyToExistingWindows()
        observer = center.addObserver(
            forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main
        ) { notification in
            guard let window = notification.object as? NSWindow else { return }
            MainActor.assumeIsolated { Self.apply(to: window) }
        }
    }

    public func stop(center: NotificationCenter = .default) {
        if let observer { center.removeObserver(observer) }
        observer = nil
    }

    // No `deinit` teardown on purpose. Reaching a non-Sendable observer token from a nonisolated
    // deinit is a strict-concurrency error in Swift 6, and it buys nothing here: the observer block
    // captures no `self`, so an un-removed one holds nothing alive and does nothing. `stop()` is the
    // real teardown, called from `PlatformIntegration.stop()`.

    private func applyToExistingWindows() {
        for window in NSApp.windows {
            Self.apply(to: window)
        }
    }

    static func apply(to window: NSWindow) {
        guard shouldConstrain(window) else { return }
        window.minSize = minimumSize
        // TASK-508 #3: frame restoration, made deterministic. SwiftUI restores a window's frame only
        // when the system's "Close windows when quitting an app" is off — a setting we don't control
        // and shouldn't fight. An autosave name persists size and position through AppKit either way.
        // Set once: assigning it repeatedly is harmless, but AppKit reads the saved frame on the
        // first assignment only.
        if window.frameAutosaveName.isEmpty {
            window.setFrameAutosaveName("jobhunt.main")
        }
    }

    /// Reads the flags off the window and asks Core. This adapter is the only AppKit-aware part.
    private static func shouldConstrain(_ window: NSWindow) -> Bool {
        WindowSizePolicy.shouldConstrain(
            isTitled: window.styleMask.contains(.titled),
            isResizable: window.styleMask.contains(.resizable),
            isPanel: window is NSPanel,
            identifier: window.identifier?.rawValue
        )
    }
}
