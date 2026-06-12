import AppKit
import JobhuntCore
import SwiftUI
import UniformTypeIdentifiers

/// Shown instead of the main window when the SwiftData store fails to open (e.g. corrupt store).
/// Gives the user a path to recover without a crash.
struct StoreRecoveryView: View {
    let failure: JobhuntApp.StoreFailure

    @State private var restoreError: String?
    @State private var showRestoreError = false
    @State private var showStartFreshConfirmation = false

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.orange)

            Text("Could not open database")
                .font(.title2.weight(.semibold))

            Text(failure.message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("Store location:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(failure.storeURL.path)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))

            Text("The database file may be corrupt. Restore it from a backup, or delete it and relaunch to start fresh.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)

            VStack(spacing: 8) {
                HStack(spacing: 12) {
                    Button("Restore from Backup…") {
                        restoreFromBackup()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Start Fresh") {
                        showStartFreshConfirmation = true
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }

                HStack(spacing: 12) {
                    Button("Open Data Folder") {
                        NSWorkspace.shared.open(failure.storeURL.deletingLastPathComponent())
                    }
                    .buttonStyle(.bordered)

                    Button("Quit") {
                        NSApp.terminate(nil)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(40)
        .frame(width: 520, height: 460)
        .alert("Restore Failed", isPresented: $showRestoreError, actions: {
            Button("OK") {}
        }, message: {
            Text(restoreError ?? "Unknown error")
        })
        .confirmationDialog(
            "Start Fresh?",
            isPresented: $showStartFreshConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete All Data and Relaunch", role: .destructive) {
                startFresh()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will delete all current data. The corrupt store will be moved aside (not permanently deleted) before the app relaunches.")
        }
    }

    // MARK: - Actions

    private func restoreFromBackup() {
        let panel = NSOpenPanel()
        panel.title = "Choose a Backup File"
        panel.message = "Select a Jobhunt SQLite backup (.store or .sqlite)"
        panel.allowedContentTypes = [
            UTType(filenameExtension: "store") ?? .data,
            UTType(filenameExtension: "sqlite") ?? .database,
        ]
        panel.allowsOtherFileTypes = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let backupURL = panel.url else { return }

        // Validate SQLite magic header
        guard BackupService.isValidSQLite(at: backupURL) else {
            restoreError = "The selected file does not appear to be a valid SQLite database."
            showRestoreError = true
            return
        }

        // Best-effort: rename the corrupt store aside before overwriting
        let storeURL = failure.storeURL
        let timestamp = Int(Date().timeIntervalSince1970)
        let corruptURL = storeURL.deletingLastPathComponent()
            .appendingPathComponent("jobhunt.store.corrupt-\(timestamp)")
        try? FileManager.default.moveItem(at: storeURL, to: corruptURL)

        do {
            try BackupService.restore(from: backupURL, to: storeURL)
        } catch {
            restoreError = error.localizedDescription
            showRestoreError = true
            return
        }

        let alert = NSAlert()
        alert.messageText = "Restore Successful"
        alert.informativeText = "The backup has been restored. The app will now quit — please relaunch it."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Quit")
        alert.runModal()
        NSApp.terminate(nil)
    }

    private func startFresh() {
        let storeURL = failure.storeURL
        let timestamp = Int(Date().timeIntervalSince1970)
        let corruptURL = storeURL.deletingLastPathComponent()
            .appendingPathComponent("jobhunt.store.corrupt-\(timestamp)")
        // Move (not delete) so the user can recover manually if needed
        try? FileManager.default.moveItem(at: storeURL, to: corruptURL)
        // Also move companion WAL/SHM files (hyphen-separated, as SQLite actually creates them)
        let walFile = storeURL.deletingLastPathComponent()
            .appendingPathComponent(storeURL.lastPathComponent + "-wal")
        let shmFile = storeURL.deletingLastPathComponent()
            .appendingPathComponent(storeURL.lastPathComponent + "-shm")
        let corruptWal = corruptURL.deletingLastPathComponent()
            .appendingPathComponent(corruptURL.lastPathComponent + "-wal")
        let corruptShm = corruptURL.deletingLastPathComponent()
            .appendingPathComponent(corruptURL.lastPathComponent + "-shm")
        try? FileManager.default.moveItem(at: walFile, to: corruptWal)
        try? FileManager.default.moveItem(at: shmFile, to: corruptShm)
        NSApp.terminate(nil)
    }
}
