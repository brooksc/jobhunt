import JobhuntCore
import PDFKit
import SwiftData
import SwiftUI

struct ResumesTab: View {
    let settings: SettingsStore

    @Query(sort: \Resume.sortOrder) private var resumes: [Resume]
    @Environment(\.modelContext) private var modelContext

    @State private var showingAddSheet = false
    @State private var editingResume: Resume?
    @State private var deleteCandidate: Resume?
    @State private var showingDeleteAlert = false

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

            if resumes.isEmpty {
                ContentUnavailableView(
                    "No Resumes",
                    systemImage: "doc.text",
                    description: Text("Add a resume to score job fit.")
                )
            } else {
                List {
                    ForEach(resumes) { resume in
                        ResumeRow(resume: resume)
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
                addResume(name: name, text: text)
            })
        }
        .sheet(item: $editingResume) { resume in
            ResumeEditSheet(resume: resume, onSave: { name, text in
                resume.name = name
                resume.text = text
                resume.charCount = text.count
                resume.updatedAt = Date()
                try? modelContext.save()
            })
        }
        .alert("Delete Resume?", isPresented: $showingDeleteAlert, presenting: deleteCandidate) { resume in
            Button("Delete", role: .destructive) {
                let wasActive = resume.active
                modelContext.delete(resume)
                if wasActive {
                    let remaining = resumes.filter { $0.id != resume.id }
                    if let next = remaining.first(where: { !$0.active }) ?? remaining.first {
                        next.active = true
                    }
                }
                try? modelContext.save()
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

    private func addResume(name: String, text: String) {
        let isFirst = resumes.isEmpty
        let resume = Resume(
            name: name,
            text: text,
            charCount: text.count,
            active: isFirst,
            sortOrder: resumes.count
        )
        modelContext.insert(resume)
        try? modelContext.save()
    }
}

// MARK: - ResumeRow

private struct ResumeRow: View {
    let resume: Resume
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Resume.sortOrder) private var allResumes: [Resume]

    var body: some View {
        HStack(spacing: 12) {
            Button {
                setActive(resume)
            } label: {
                Image(systemName: resume.active ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(resume.active ? .green : .secondary)
                    .font(.title3)
            }
            .buttonStyle(.plain)

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

    private func setActive(_ target: Resume) {
        for r in allResumes {
            r.active = (r.id == target.id)
        }
        try? modelContext.save()
    }
}

// MARK: - ResumeEditSheet

private struct ResumeEditSheet: View {
    let resume: Resume?
    let onSave: (String, String) -> Void

    @State private var name: String
    @State private var text: String
    @Environment(\.dismiss) private var dismiss

    init(resume: Resume?, onSave: @escaping (String, String) -> Void) {
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
                    onSave(name, text)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty || text.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 600, height: 520)
    }

    private func importPDF() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let extracted = extractPDFText(from: url)
        if !extracted.isEmpty {
            text = extracted
            if name.isEmpty {
                name = url.deletingPathExtension().lastPathComponent
            }
        }
    }

    private func extractPDFText(from url: URL) -> String {
        guard let doc = PDFDocument(url: url) else { return "" }
        return (0 ..< doc.pageCount).compactMap { doc.page(at: $0)?.string }.joined(separator: "\n")
    }
}
