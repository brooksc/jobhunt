import SwiftUI

// MARK: - Keyboard Shortcuts overlay (TASK-499)

/// In-app keyboard-shortcuts reference, grouped by section and driven entirely by
/// `KeyboardShortcutCatalog` so it can't drift from the real bindings (AC#10/#12). Presented as a
/// sheet; dismisses via Escape or the close button.
struct KeyboardShortcutsView: View {
    let dismiss: () -> Void

    private let columns = [
        GridItem(.flexible(), alignment: .topLeading),
        GridItem(.flexible(), alignment: .topLeading)
    ]

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                    ForEach(ShortcutSection.allCases) { section in
                        sectionColumn(section)
                    }
                }
                .padding(20)
            }
        }
        .frame(width: 640, height: 520)
        .background(.background)
        .accessibilityIdentifier("overlay.keyboardShortcuts")
        // Escape closes the overlay (AC#10). A hidden default button gives ⎋ a target without a
        // visible control.
        .overlay {
            Button("", action: dismiss).keyboardShortcut(.cancelAction).hidden()
        }
    }

    private var header: some View {
        HStack {
            Label("Keyboard Shortcuts", systemImage: "keyboard")
                .font(.title3.weight(.semibold))
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
        .padding(16)
    }

    private func sectionColumn(_ section: ShortcutSection) -> some View {
        let rows = KeyboardShortcutCatalog.all.filter { $0.section == section }
        return VStack(alignment: .leading, spacing: 8) {
            Text(section.rawValue)
                .font(.headline)
                .foregroundStyle(.secondary)
            ForEach(rows) { shortcut in
                HStack(alignment: .top, spacing: 10) {
                    Text(shortcut.glyph)
                        .font(.system(.body, design: .rounded).weight(.medium))
                        .frame(minWidth: 64, alignment: .leading)
                    Text(shortcut.title)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(shortcut.title), \(shortcut.glyph)")
            }
        }
    }
}
