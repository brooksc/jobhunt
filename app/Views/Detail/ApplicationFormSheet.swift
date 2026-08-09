import JobhuntCore
import SwiftUI

/// What the application will ask for, before the user commits to starting it (TASK-635).
///
/// Effort is invisible from a job posting: two roles that read identically can be a two-minute
/// upload and forty minutes of essays. Read-only — this never submits anything.
struct ApplicationFormSheet: View {
    let jobID: String

    @Environment(AppServices.self) private var appServices
    @Environment(\.dismiss) private var dismiss

    @State private var preview: ApplicationFormPreview?
    @State private var isLoading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Application form").font(.headline)

            if isLoading {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Reading the employer's form…").foregroundStyle(.secondary)
                }
            } else if let preview {
                content(preview)
            } else {
                // #4: a board that doesn't publish the form is not a form with no questions.
                Text("This employer's job board doesn't publish its application form.")
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 520)
        .task { await load() }
    }

    @ViewBuilder
    private func content(_ preview: ApplicationFormPreview) -> some View {
        if let summary = preview.summary {
            Text(summary).font(.callout)
        }
        Text("\(preview.requiredCount) required · \(preview.optionalCount) optional")
            .font(.caption)
            .foregroundStyle(.secondary)

        List(preview.questions) { question in
            HStack(alignment: .top, spacing: 8) {
                // #2: required vs optional, and the heavy items called out — those are what make
                // one application take ten times as long as another.
                Image(systemName: question.required ? "asterisk" : "circle.dotted")
                    .font(.caption2)
                    .foregroundStyle(question.required ? Color.orange : .secondary)
                Text(question.label)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                if question.isEffortful {
                    Text("written answer")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 2)
        }
        .listStyle(.inset)
        .frame(minHeight: 280)
    }

    private func load() async {
        let result = await appServices.jobService.applicationFormPreview(jobID: jobID)
        await MainActor.run {
            preview = result
            isLoading = false
        }
    }
}
