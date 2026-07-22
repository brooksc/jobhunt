import AppKit
import SwiftUI

/// Recomputes the dock badge whenever unread job count changes.
/// Intended to be @Query-driven from the App: pass unread count as a binding.
@MainActor
struct DockBadgeUpdater: View {
    let unreadCount: Int

    private static func badgeLabel(for count: Int) -> String {
        count > 0 ? "\(count)" : ""
    }

    var body: some View {
        Color.clear
            // Set the badge on first appearance too (TASK-544) — otherwise launching with existing
            // unread jobs left the Dock badge blank until the count next changed that session.
            .onAppear { NSApp.dockTile.badgeLabel = Self.badgeLabel(for: unreadCount) }
            .onChange(of: unreadCount) { _, newVal in
                NSApp.dockTile.badgeLabel = Self.badgeLabel(for: newVal)
            }
    }
}
