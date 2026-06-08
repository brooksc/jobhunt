import SwiftUI
import AppKit

// Recomputes the dock badge whenever unread job count changes.
// Intended to be @Query-driven from the App: pass unread count as a binding.
@MainActor
struct DockBadgeUpdater: View {
    let unreadCount: Int

    var body: some View {
        Color.clear
            .onChange(of: unreadCount) { _, newVal in
                NSApp.dockTile.badgeLabel = newVal > 0 ? "\(newVal)" : ""
            }
    }
}
