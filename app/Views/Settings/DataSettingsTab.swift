import AppKit
import JobhuntCore
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Data tab (backup & restore)

struct DataSettingsTab: View {
    @State private var showingRestoreConfirmation = false
    @State private var pendingRestoreURL: URL?

    @Environment(AppServices.self) private var appServices

    var body: some View {
        Form {
            dataSection
        }
        .formStyle(.grouped)
        .confirmationDialog(
            "Replace Current Data?",
            isPresented: $showingRestoreConfirmation,
            titleVisibility: .visible
        ) {
            Button("Restore and Relaunch", role: .destructive) {
                if let url = pendingRestoreURL { performRestore(from: url) }
            }
            Button("Cancel", role: .cancel) { pendingRestoreURL = nil }
        } message: {
            Text(
                "All current jobs, captures, settings, and resumes will be replaced with the backup. " +
                    "A pre-restore backup will be saved automatically. " +
                    "API keys are not part of the backup (they live in the Keychain) — you may need to " +
                    "re-enter them in AI Provider settings afterward. " +
                    "The app must relaunch to apply the restored data."
            )
        }
    }

    private var dataSection: some View {
        Section("Data") {
            HStack {
                Button {
                    backUpData()
                } label: {
                    Label("Back Up Data…", systemImage: "externaldrive.badge.checkmark")
                }

                Spacer()

                Button(role: .destructive) {
                    chooseRestoreFile()
                } label: {
                    Label("Restore from Backup…", systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                }
            }
            // TASK-378: the backup is the SQLite store only. API keys live in the macOS Keychain,
            // not the store, so they're never in the backup file — set this expectation up front.
            Text("Backups include all jobs, captures, resumes, and settings — but not your AI "
                + "provider API keys, which are stored separately in the macOS Keychain. After "
                + "restoring on a new Mac (or if the Keychain items are missing), re-enter them in "
                + "AI Provider settings.")
                .font(.caption)
                .foregroundStyle(.secondary)

            // TASK-590 #4. Scoped to this app's Spotlight domain, never a global index wipe.
            HStack {
                Button {
                    SpotlightIndexer.clearAll { error in
                        Task { @MainActor in
                            appServices.toastStore.show(
                                error == nil
                                    ? "Spotlight index cleared — it rebuilds on the next launch"
                                    : "Couldn't clear the Spotlight index",
                                isError: error != nil
                            )
                        }
                    }
                } label: {
                    Label("Clear Spotlight Index", systemImage: "magnifyingglass")
                }
                Spacer()
            }
            Text("JobHunt publishes your jobs to Spotlight so you can find them from anywhere on "
                + "the Mac. Clearing removes them; they are re-added the next time the app starts.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Helpers

    private func backUpData() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "sqlite") ?? .data]
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        panel.nameFieldStringValue = "jobhunt-backup-\(formatter.string(from: Date())).sqlite"
        panel.title = "Save JobHunt Backup"
        panel.message = "Choose where to save the backup file."
        guard panel.runModal() == .OK, let dest = panel.url else { return }
        let storeURL = ModelContainerFactory.productionStoreURL()
        do {
            try BackupService.backup(storeURL: storeURL, to: dest)
            appServices.toastStore.show("Backup saved to \(dest.lastPathComponent)")
        } catch {
            appServices.toastStore.show("Backup failed: \(error.localizedDescription)", isError: true)
        }
    }

    private func chooseRestoreFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "sqlite") ?? .data]
        panel.title = "Select Backup to Restore"
        panel.message = "Choose a .sqlite backup file created by JobHunt."
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }

        guard BackupService.isValidSQLite(at: url) else {
            appServices.toastStore.show(
                "The selected file is not a valid SQLite backup.", isError: true
            )
            return
        }

        pendingRestoreURL = url
        showingRestoreConfirmation = true
    }

    private func performRestore(from backupURL: URL) {
        let storeURL = ModelContainerFactory.productionStoreURL()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let safetyBackupURL = storeURL.deletingLastPathComponent()
            .appendingPathComponent("pre-restore-\(formatter.string(from: Date())).sqlite")
        pendingRestoreURL = nil

        // Restore is async because it must QUIESCE runtime writers before swapping the single-writer
        // store (TASK-546): RestoreCoordinator stops the LLM queue / availability loop / local server
        // via appServices.shutdown(), then safety-backs-up, then replaces the store. On success or any
        // failure the app quits so the next launch opens a known store with a clean runtime — never
        // left half-restored with a partially-quiesced runtime.
        Task { @MainActor in
            do {
                try await RestoreCoordinator.perform(
                    backupURL: backupURL,
                    storeURL: storeURL,
                    safetyBackupURL: safetyBackupURL,
                    quiesceRuntime: { await appServices.shutdown() }
                )
            } catch let err as RestoreCoordinator.StageError {
                presentRestoreFailureThenQuit(stage: err.stage, error: err.underlying)
                return
            } catch {
                presentRestoreFailureThenQuit(stage: .restore, error: error)
                return
            }

            // Restore is on disk; the live container still sees old data. Quit so the next launch
            // opens the restored store cleanly (runtime is already quiesced).
            let alert = NSAlert()
            alert.messageText = "Restore Complete"
            alert.informativeText =
                "Your data has been restored from \(backupURL.lastPathComponent). " +
                "If your AI provider API keys are missing after relaunch, re-enter them in " +
                "AI Provider settings — they're kept in the Keychain, not the backup. " +
                "The app will now quit and must be relaunched to load the restored data."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "Quit Now")
            alert.runModal()
            NSApp.terminate(nil)
        }
    }

    /// Report a restore-stage failure and quit. Runtime is already quiesced, so relaunching restores
    /// normal operation against a known store (unchanged on a safety-backup failure; the safety backup
    /// is on disk if the swap itself failed).
    private func presentRestoreFailureThenQuit(stage: RestoreCoordinator.Stage, error: Error) {
        let alert = NSAlert()
        switch stage {
        case .safetyBackup:
            alert.messageText = "Safety Backup Failed"
            alert.informativeText =
                "Could not create a pre-restore safety backup, so the restore was aborted and your data " +
                "is unchanged. Free up disk space and try again. The app will now quit; relaunch to " +
                "resume.\n\nError: \(error.localizedDescription)"
        case .restore:
            alert.messageText = "Restore Failed"
            alert.informativeText =
                "The restore did not complete. A pre-restore safety backup was saved, so your original " +
                "data should be intact. The app will now quit; relaunch to resume.\n\nError: " +
                "\(error.localizedDescription)"
        }
        alert.alertStyle = .critical
        alert.addButton(withTitle: "Quit Now")
        alert.runModal()
        NSApp.terminate(nil)
    }
}
