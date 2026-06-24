import JobhuntCore
import SwiftData
import SwiftUI

/// First-run setup checklist (TASK-498). A user can skip every onboarding step and land in an app
/// that can't extract (no AI provider), score (no résumé), or capture (no extension) — with nothing
/// telling them they're not set up. This card surfaces the three gates with deep links and
/// disappears on its own once an AI provider *and* a résumé are configured, so a fully-set-up user
/// never sees it. Dismissible for the current session (see `Router.setupChecklistDismissed`).
struct SetupChecklistCard: View {
    let settings: SettingsStore
    @Environment(Router.self) private var router
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openURL) private var openURL

    @Query private var resumes: [Resume]
    /// Captures only exist once the browser extension has successfully reached the app, so their
    /// presence is a reliable proxy for "extension connected" (no dedicated signal exists).
    @Query private var captures: [Capture]

    private var aiConfigured: Bool {
        AIConfig.isConfigured(settings)
    }

    private var hasResume: Bool {
        !resumes.isEmpty
    }

    private var hasExtension: Bool {
        !captures.isEmpty
    }

    /// Show until the two essential gates (AI + résumé) are met. The extension is listed for guidance
    /// but doesn't keep the card alive on its own — a manual tracker without the extension is valid.
    private var shouldShow: Bool {
        (!aiConfigured || !hasResume) && !router.setupChecklistDismissed
    }

    var body: some View {
        if shouldShow {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "checklist")
                        .foregroundStyle(Color.accentColor)
                    Text("Finish setting up JobHunt")
                        .font(.callout.weight(.semibold))
                    Spacer()
                    Button {
                        router.setupChecklistDismissed = true
                    } label: {
                        Image(systemName: "xmark").font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Dismiss for now — returns next launch until you're set up")
                }

                row(
                    done: aiConfigured,
                    label: "Add an AI provider",
                    hint: "Enables automatic job extraction and résumé fit scoring",
                    actionLabel: "Set Up"
                ) {
                    router.settingsTab = .llm
                    openSettings()
                }
                row(
                    done: hasResume,
                    label: "Add a résumé",
                    hint: "Used to score how well each job fits your background",
                    actionLabel: "Add"
                ) {
                    router.selectedSection = .resumes
                }
                row(
                    done: hasExtension,
                    label: "Install the browser extension",
                    hint: "Capture job postings from any site with one click",
                    actionLabel: "How"
                ) {
                    if let url = URL(string: "https://jobhunt-app.com/help") {
                        openURL(url)
                    }
                }
            }
            .padding(12)
            .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.secondary.opacity(0.18)))
        }
    }

    private func row(
        done: Bool,
        label: String,
        hint: String,
        actionLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(done ? .green : .secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.callout.weight(.medium))
                    .strikethrough(done, color: .secondary)
                    .foregroundStyle(done ? .secondary : .primary)
                if !done {
                    Text(hint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            if !done {
                Button(actionLabel, action: action)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
    }
}
