import AppKit
import JobhuntCore
import SwiftUI

/// Settings → Jobs → Custom AI Prompts (TASK-627).
///
/// The list; the editor is `PromptTemplateEditor`.
extension JobsSettingsTab {
    var customPromptsSection: some View {
        Section("Custom AI Prompts") {
            let templates = settings.customPromptTemplates
            if templates.isEmpty {
                Text(
                    "Prompts you write yourself, using your job and résumé data. They appear in a "
                        + "job's Prompt AI menu and copy to the clipboard — JobHunt never sends them "
                        + "to an AI provider."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(templates) { template in
                    promptRow(
                        template,
                        isFirst: template.id == templates.first?.id,
                        isLast: template.id == templates.last?.id
                    )
                }
            }

            Button {
                // #5: a new prompt starts from the safe example rather than a blank box, so the
                // delimiting and the "treat this as reference data" instruction are there by default.
                editingPrompt = PromptTemplate(
                    name: "My prompt", body: PromptTemplateRenderer.starterTemplate
                )
            } label: {
                Label("New Prompt…", systemImage: "plus")
            }
        }
        .sheet(item: $editingPrompt) { template in
            PromptTemplateEditor(template: template) { saved in
                settings.upsertPromptTemplate(saved)
                editingPrompt = nil
            }
        }
    }

    private func promptRow(_ template: PromptTemplate, isFirst: Bool, isLast: Bool) -> some View {
        HStack(spacing: 8) {
            Toggle("", isOn: Binding(
                get: { template.isEnabled },
                set: { enabled in
                    var updated = template
                    updated.isEnabled = enabled
                    settings.upsertPromptTemplate(updated)
                }
            ))
            .labelsHidden()
            .help(template.isEnabled ? "Shown in the Prompt AI menu" : "Hidden from the menu")

            VStack(alignment: .leading, spacing: 1) {
                Text(template.name).font(.callout)
                Text(variableSummary(template))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Button { settings.movePromptTemplate(id: template.id, up: true) } label: {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.borderless)
            .disabled(isFirst)
            .help("Move up in the menu")

            Button { settings.movePromptTemplate(id: template.id, up: false) } label: {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.borderless)
            .disabled(isLast)
            .help("Move down in the menu")

            Button { editingPrompt = template } label: { Image(systemName: "pencil") }
                .buttonStyle(.borderless)
                .help("Edit this prompt")

            Button {
                var copy = template
                copy = PromptTemplate(name: "\(template.name) copy", body: template.body)
                settings.upsertPromptTemplate(copy)
            } label: { Image(systemName: "doc.on.doc") }
                .buttonStyle(.borderless)
                .help("Duplicate this prompt")

            Button { settings.removePromptTemplate(id: template.id) } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Delete this prompt")
        }
    }

    /// Which variables the prompt pulls in — the thing you actually want to know at a glance when
    /// deciding whether a prompt is the one you meant.
    private func variableSummary(_ template: PromptTemplate) -> String {
        let used = PromptTemplateRenderer.variablesUsed(in: template.body)
        guard !used.isEmpty else { return "No variables" }
        return "Uses " + used.map(\.label).joined(separator: ", ")
    }
}

/// Writes one prompt: name, body, an insertion menu, live validation and a preview (TASK-627).
struct PromptTemplateEditor: View {
    let template: PromptTemplate
    let onSave: (PromptTemplate) -> Void

    @State private var name: String
    /// Not `body`: that name is taken by `View`.
    @State private var templateBody: String
    @State private var showPreview = false
    @Environment(\.dismiss) private var dismiss

    init(template: PromptTemplate, onSave: @escaping (PromptTemplate) -> Void) {
        self.template = template
        self.onSave = onSave
        _name = State(initialValue: template.name)
        _templateBody = State(initialValue: template.body)
    }

    private var errors: [PromptTemplateRenderer.ValidationError] {
        PromptTemplateRenderer.validate(name: name, body: templateBody)
    }

    private var preview: String {
        PromptTemplateRenderer.render(templateBody, values: PromptTemplateRenderer.sampleValues).text
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Edit Prompt").font(.headline)

            TextField("Name", text: $name)

            HStack {
                // #4: nobody should have to memorise token syntax.
                Menu {
                    ForEach(PromptVariable.allCases, id: \.self) { variable in
                        Button {
                            templateBody += variable.token
                        } label: {
                            Text("\(variable.label) — \(variable.detail)")
                        }
                    }
                } label: {
                    Label("Insert Variable", systemImage: "curlybraces")
                }
                .fixedSize()

                Spacer()

                Toggle("Preview", isOn: $showPreview)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .help("Show the prompt with sample values filled in")
            }

            if showPreview {
                // #7: obviously fake values. Real job data in a settings preview is a privacy leak
                // waiting to happen, and an 8 KB description makes the sample unreadable anyway.
                ScrollView {
                    Text(preview)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 260)
                .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
            } else {
                TextEditor(text: $templateBody)
                    .font(.system(.caption, design: .monospaced))
                    .frame(height: 260)
                    .border(Color.secondary.opacity(0.2))
            }

            // #6: every problem at once. Fixing one error per save is a miserable way to write.
            ForEach(errors, id: \.message) { error in
                Label(error.message, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") {
                    var saved = template
                    saved.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    saved.body = templateBody
                    onSave(saved)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!errors.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 620)
    }
}
