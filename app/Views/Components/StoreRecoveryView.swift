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

            Text(
                "The database file may be corrupt. Restore it from a backup, or delete it and relaunch to start fresh."
            )
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
            Text(
                "This will delete all current data. The corrupt store will be moved aside " +
                    "(not permanently deleted) before the app relaunches."
            )
        }
    }

    // MARK: - Actions

    private func restoreFromBackup() {
        let panel = NSOpenPanel()
        panel.title = "Choose a Backup File"
        panel.message = "Select a JobHunt SQLite backup (.store or .sqlite)"
        panel.allowedContentTypes = [
            UTType(filenameExtension: "store") ?? .data,
            UTType(filenameExtension: "sqlite") ?? .database
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

        // TASK-375: do NOT move the failed store aside before restoring. BackupService.restore
        // stages the backup, deep-validates it against the current schema/migration plan, and only
        // then moves the live store aside with rollback — so a rejected backup leaves the original
        // store untouched at storeURL. Moving it aside first defeats that: a failed restore would
        // leave the expected path empty. Instead, *copy* the corrupt store aside for manual recovery
        // while leaving the original in place for restore's rollback to protect.
        let storeURL = failure.storeURL
        let timestamp = Int(Date().timeIntervalSince1970)
        let corruptURL = storeURL.deletingLastPathComponent()
            .appendingPathComponent("jobhunt.store.corrupt-\(timestamp)")
        let fm = FileManager.default
        try? fm.copyItem(at: storeURL, to: corruptURL)
        // Copy companions too so the preserved snapshot is faithful (WAL may hold recent pages).
        for suffix in ["-wal", "-shm"] {
            let live = storeURL.deletingLastPathComponent()
                .appendingPathComponent(storeURL.lastPathComponent + suffix)
            let aside = corruptURL.deletingLastPathComponent()
                .appendingPathComponent(corruptURL.lastPathComponent + suffix)
            try? fm.copyItem(at: live, to: aside)
        }

        do {
            try BackupService.restore(from: backupURL, to: storeURL)
        } catch {
            // Restore rolled the original back to storeURL, so the corrupt-* copy is redundant — drop it.
            try? fm.removeItem(at: corruptURL)
            for suffix in ["-wal", "-shm"] {
                try? fm.removeItem(at: corruptURL.deletingLastPathComponent()
                    .appendingPathComponent(corruptURL.lastPathComponent + suffix))
            }
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
        do {
            let outcome = try StoreQuarantine.moveAside(storeURL: failure.storeURL)
            if !outcome.strandedCompanions.isEmpty {
                // Neither moved nor deleted: a stale -wal beside the new store is not inert, so say so
                // rather than restarting into a database SQLite may try to replay into.
                restoreError = "The damaged database was moved aside, but leftover "
                    + outcome.strandedCompanions.joined(separator: " and ")
                    + " files could not be removed. Delete them from "
                    + failure.storeURL.deletingLastPathComponent().path
                    + " before relaunching."
                showRestoreError = true
                return
            }
            NSApp.terminate(nil)
        } catch {
            // Do NOT terminate. Quitting here relaunched straight back into the same corrupt store
            // with no explanation — the recovery action became a loop.
            restoreError = error.localizedDescription
            showRestoreError = true
        }
    }
}
