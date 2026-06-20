import JobhuntCore
import PDFKit
import SwiftData
import SwiftUI

struct ResumesTab: View {
    let settings: SettingsStore

    @Query(sort: \Resume.sortOrder) private var resumes: [Resume]
    @Environment(AppServices.self) private var appServices

    @State private var showingAddSheet = false
    @State private var editingResume: Resume?
    @State private var deleteCandidate: Resume?
    @State private var showingDeleteAlert = false
    @State private var saveError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Resumes")
                    .font(.headline)
                Spacer()
                Button {
                    showingAddSheet = true
                } label: {
                    Label("Add Resume", systemImage: "plus")
                }
                .buttonStyle(.bordered)
            }
            .padding(.bottom, 8)

            if !resumes.isEmpty {
                Text(
                    "Active resumes (✓) are auto-scored against new jobs; " +
                        "a job's fit shows the best match across resumes."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.bottom, 8)
            }

            if resumes.isEmpty {
                ContentUnavailableView(
                    "No Resumes",
                    systemImage: "doc.text",
                    description: Text("Add a resume to score job fit.")
                )
            } else {
                List {
                    ForEach(resumes) { resume in
                        ResumeRow(resume: resume, resumeService: appServices.resumeService)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                editingResume = resume
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    deleteCandidate = resume
                                    showingDeleteAlert = true
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                }
                .listStyle(.inset)
            }
        }
        .padding()
        .sheet(isPresented: $showingAddSheet) {
            ResumeEditSheet(resume: nil, onSave: { name, text in
                try await appServices.resumeService.addResume(name: name, text: text)
            })
        }
        .sheet(item: $editingResume) { resume in
            ResumeEditSheet(resume: resume, onSave: { name, text in
                let id = resume.id
                // Editing the text invalidates this résumé's fit scores — tell the user instead of
                // letting them silently vanish.
                let cleared = try await appServices.resumeService.updateResume(id: id, name: name, text: text)
                if cleared > 0 {
                    appServices.toastStore.show(
                        "Résumé updated — cleared \(cleared) fit score\(cleared == 1 ? "" : "s"). " +
                            "Re-score jobs to update."
                    )
                }
            })
        }
        .alert("Delete Resume?", isPresented: $showingDeleteAlert, presenting: deleteCandidate) { resume in
            Button("Delete", role: .destructive) {
                let id = resume.id
                Task {
                    do {
                        try await appServices.resumeService.deleteResume(id: id)
                    } catch {
                        appServices.toastStore.show("Delete failed: \(error.localizedDescription)", isError: true)
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { resume in
            if resume.active {
                let hasOther = resumes.contains { $0.id != resume.id }
                if hasOther {
                    Text("\"\(resume.name)\" is your active resume. The next resume will be promoted to active.")
                } else {
                    Text("\"\(resume.name)\" is your only resume. Deleting it will leave no active resume.")
                }
            } else {
                Text("Are you sure you want to delete \"\(resume.name)\"?")
            }
        }
    }
}

// MARK: - ResumeRow

private struct ResumeRow: View {
    let resume: Resume
    let resumeService: ResumeService
    @Environment(AppServices.self) private var appServices

    var body: some View {
        HStack(spacing: 12) {
            Button {
                let id = resume.id
                let newActive = !resume.active
                // The checkmark reflects resume.active (store-backed), so a failed write leaves the
                // displayed state correct; just surface the error rather than swallow it.
                Task {
                    do { try await resumeService.setResumeActive(id: id, active: newActive) } catch {
                        appServices.toastStore.show(
                            "Couldn't change active resume: \(error.localizedDescription)",
                            isError: true
                        )
                    }
                }
            } label: {
                Image(systemName: resume.active ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(resume.active ? .green : .secondary)
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .help(resume
                .active ? "Active — auto-scored against new jobs. Click to deactivate." :
                "Inactive. Click to activate (auto-scored against new jobs).")

            VStack(alignment: .leading, spacing: 2) {
                Text(resume.name)
                    .fontWeight(resume.active ? .semibold : .regular)
                HStack(spacing: 8) {
                    Text("\(resume.charCount) chars")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(resume.createdAt.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if resume.active {
                Text("Active")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.green.opacity(0.12))
                    .foregroundStyle(.green)
                    .clipShape(Capsule())
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - ResumeEditSheet

private struct ResumeEditSheet: View {
    let resume: Resume?
    let onSave: (String, String) async throws -> Void

    @State private var name: String
    @State private var text: String
    @State private var importError: String?
    @State private var saveError: String?
    @State private var isSaving = false
    @Environment(\.dismiss) private var dismiss

    init(resume: Resume?, onSave: @escaping (String, String) async throws -> Void) {
        self.resume = resume
        self.onSave = onSave
        _name = State(initialValue: resume?.name ?? "")
        _text = State(initialValue: resume?.text ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(resume == nil ? "Add Resume" : "Edit Resume")
                .font(.title2)
                .fontWeight(.semibold)

            TextField("Name (e.g. Software Engineer Resume)", text: $name)

            TextEditor(text: $text)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 240)
                .border(.separator)

            HStack {
                Button("Import PDF…") {
                    importPDF()
                }

                Spacer()

                Text("\(text.count) chars")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }

            Divider()

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save") {
                    isSaving = true
                    Task {
                        defer { isSaving = false }
                        do {
                            try await onSave(name, text)
                            dismiss()
                        } catch {
                            saveError = error.localizedDescription
                        }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty || text.isEmpty || isSaving)
            }
        }
        .padding(24)
        .frame(width: 600, height: 520)
        .alert("Import Failed", isPresented: Binding(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )) {
            Button("OK", role: .cancel) { importError = nil }
        } message: {
            Text(importError ?? "")
        }
        .alert("Save Failed", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("OK", role: .cancel) { saveError = nil }
        } message: {
            Text(saveError ?? "")
        }
    }

    private func importPDF() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        // Consistent with onboarding import: acquire security-scoped access before reading
        // user-selected files under MAS sandboxing.
        guard url.startAccessingSecurityScopedResource() else {
            importError = "Could not access the selected file"
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }
        do {
            let extracted = try extractPDFText(from: url)
            text = extracted
            if name.isEmpty {
                name = url.deletingPathExtension().lastPathComponent
            }
        } catch {
            importError = error.localizedDescription
        }
    }

    private func extractPDFText(from url: URL) throws -> String {
        guard let doc = PDFDocument(url: url) else {
            throw PDFImportError.unreadable
        }
        let text = (0 ..< doc.pageCount).compactMap { doc.page(at: $0)?.string }.joined(separator: "\n")
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PDFImportError.emptyText
        }
        return text
    }

    private enum PDFImportError: LocalizedError {
        case unreadable
        case emptyText

        var errorDescription: String? {
            switch self {
            case .unreadable: "The file could not be read as a PDF"
            case .emptyText: "No text could be read from this PDF"
            }
        }
    }
}
