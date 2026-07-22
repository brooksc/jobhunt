import AppKit
import SwiftUI

// MARK: - Keyboard shortcut monitor (TASK-499)

/// Installs an app-local `NSEvent` key-down monitor for the two shortcuts that can't be plain menu
/// key-equivalents:
///   • bare `?` opens the Keyboard Shortcuts overlay — but only when the user isn't typing in a text
///     field, so `?` still inserts normally in search/notes (AC#9).
///   • ⌃Tab / ⌃⇧Tab cycles the visible job-detail tabs, and passes the event through when no detail
///     is on screen (AC#8).
struct KeyboardShortcutMonitor: ViewModifier {
    let router: Router
    @State private var monitor: Any?

    func body(content: Content) -> some View {
        content
            .onAppear(perform: install)
            .onDisappear(perform: remove)
    }

    private func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            MainActor.assumeIsolated {
                handle(event) ? nil : event
            }
        }
    }

    private func remove() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    /// Returns true when the event is consumed (should not propagate).
    @MainActor
    private func handle(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let tabKeyCode: UInt16 = 48

        // ⌃Tab / ⌃⇧Tab — cycle detail tabs when a job-detail view is visible.
        if event.keyCode == tabKeyCode,
           flags.contains(.control), !flags.contains(.command), !flags.contains(.option) {
            guard let cycler = router.detailTabCycler else { return false }
            cycler.cycle(!flags.contains(.shift))
            return true
        }

        // Bare `?` (Shift-/) with no ⌘/⌃/⌥ — open the overlay unless a text field is being edited.
        if event.characters == "?",
           !flags.contains(.command), !flags.contains(.control), !flags.contains(.option) {
            if isEditingText { return false }
            if router.showKeyboardShortcuts { return true } // already open — swallow the repeat
            router.showKeyboardShortcuts = true
            return true
        }
        return false
    }

    /// True when the key window's first responder is an editable text control (a focused `TextField`
    /// is backed by the window field editor, an `NSTextView`), so `?` should insert rather than open
    /// the overlay.
    @MainActor
    private var isEditingText: Bool {
        guard let responder = NSApp.keyWindow?.firstResponder else { return false }
        if let textView = responder as? NSTextView { return textView.isEditable }
        return responder is NSText
    }
}
