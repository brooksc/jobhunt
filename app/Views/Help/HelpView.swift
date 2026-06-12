import SwiftUI

struct HelpView: View {
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                gettingStartedSection
                howItWorksSection
                extractionScoringSection
                sitesSection
                duplicatesSection
                troubleshootingSection
                settingsReferenceSection
                keyboardShortcutsSection
                aboutSection
            }
            .padding(24)
        }
        .navigationTitle("Help")
    }

    // MARK: - Sections

    private var gettingStartedSection: some View {
        HelpSection(title: "Getting Started", systemImage: "star") {
            HelpMarkdown("""
            **Jobhunt** is a local-first job tracker. The Chrome extension captures job pages, \
            the local service stores them in SQLite, and the native app helps you extract \
            structured fields, track follow-ups, review data quality, and manage your pipeline.

            **Typical workflow:**
            1. Install the Chrome extension (see instructions in the extension's popup).
            2. Open a job posting and click the Jobhunt extension button to capture it.
            3. Open the app — the captured job appears in **Jobs**.
            4. Run AI extraction to fill in structured fields and a fit score.
            5. Use **Data Quality** to find gaps, **Needs Action** for follow-ups.
            """)
        }
    }

    private var howItWorksSection: some View {
        HelpSection(title: "How It Works", systemImage: "cpu") {
            HelpMarkdown("""
            **Capture** → The Chrome extension sends the page HTML and selected text to the \
            local service running on your machine.

            **Extraction** → An AI model (local via LM Studio/Ollama, or a cloud API) reads \
            the captured text and fills structured fields: title, company, location, salary, \
            work arrangement, and more.

            **Fit Scoring** → The model rates each job 0–100 against your resume and breaks \
            the score down by dimension (skills, seniority, location, work arrangement).

            **Local-first** → All data is stored in a local SQLite database. Nothing is sent \
            to any remote server unless you configure a cloud AI provider, in which case only \
            job text goes to that API.
            """)
        }
    }

    private var extractionScoringSection: some View {
        HelpSection(title: "Extraction & Scoring", systemImage: "sparkles") {
            HelpMarkdown("""
            **Extracted fields** include: job title, company name, location, remote/hybrid/onsite \
            arrangement, salary range, required skills, seniority level, application deadline, \
            and a plain-text summary.

            **Fit dimensions** scored 0–100:
            - **Skills match** — overlap between required skills and your resume
            - **Seniority** — how well the level matches your experience
            - **Location** — proximity or remote preference match
            - **Work arrangement** — remote vs. onsite vs. hybrid preference

            Use **Full extraction** for new jobs, **Missing fields only** for cleanup, and \
            **Fit score only** after updating your resume without needing to re-extract.
            """)
        }
    }

    private var sitesSection: some View {
        HelpSection(title: "Sites & Availability", systemImage: "globe") {
            HelpMarkdown("""
            **Sites** tracks company or job-board pages you want to review periodically — \
            even when no specific posting is captured.

            Add a site URL from the **Sites** screen. New sites inherit the review interval \
            from Settings.

            Reviewing a site updates its *last-reviewed* and *next-review* dates so recurring \
            prospecting stays in your workflow.

            The app periodically checks whether captured job postings are still live and marks \
            unavailable postings as **Not Available** automatically.
            """)
        }
    }

    private var duplicatesSection: some View {
        HelpSection(title: "Duplicates", systemImage: "doc.on.doc") {
            HelpMarkdown("""
            Jobhunt detects duplicate captures by comparing title, company, and URL similarity. \
            Likely duplicates are grouped in the **Duplicates** screen.

            Compare a group to decide which record to keep, merge, archive, or ignore. \
            Use duplicate review after large capture sessions or after retry queues flush \
            several saved postings at once.

            A job marked **Duplicate** is hidden from default views but preserved in history.
            """)
        }
    }

    private var troubleshootingSection: some View {
        HelpSection(title: "Troubleshooting", systemImage: "wrench.and.screwdriver") {
            HelpMarkdown("""
            **LM Studio not running** — Make sure LM Studio is open and a model is loaded \
            before queuing extraction. Use **Test connection** in Settings → LLM to verify.

            **Extension not connecting** — The local service must be running (the app must be \
            open). Check that the port in Settings matches the extension configuration. \
            Restart the app if the service stopped unexpectedly.

            **Extraction fails silently** — Check the LLM Queue for error details and attempt history.

            **Captures not appearing** — The extension queues captures if the service is \
            unavailable and retries. Reopen the extension popup to see the queue state.

            **Fit scores missing** — Add your resume in Settings → Resume and re-run \
            **Fit score only** mode for existing jobs.
            """)
        }
    }

    private var settingsReferenceSection: some View {
        HelpSection(title: "Settings Reference", systemImage: "gear") {
            VStack(alignment: .leading, spacing: 10) {
                SettingsRow(
                    name: "LLM Provider",
                    // swiftlint:disable:next line_length
                    description: "AI backend: LM Studio, Ollama, OpenAI, Anthropic, Google, or any OpenAI-compatible endpoint."
                )
                SettingsRow(
                    name: "Model",
                    // swiftlint:disable:next line_length
                    description: "The model used for extraction and fit scoring. Gemini Flash is a good cost/quality default."
                )
                SettingsRow(
                    name: "Resume",
                    description: "Plain text of your resume, used to compute fit scores."
                )
                SettingsRow(
                    name: "Preferred Locations",
                    description: "Your preferred work locations, used in fit scoring."
                )
                SettingsRow(
                    name: "Work Arrangement",
                    description: "Remote, hybrid, or onsite preference for fit scoring."
                )
                SettingsRow(
                    name: "Follow-up Interval",
                    description: "Default number of days used to pre-fill a follow-up reminder when you apply. You are offered (not automatically scheduled) a follow-up when you mark a job applied."
                )
                SettingsRow(name: "Review Interval", description: "Default interval (days) for site review reminders.")
            }
        }
    }

    private var keyboardShortcutsSection: some View {
        HelpSection(title: "Keyboard Shortcuts", systemImage: "keyboard") {
            KeyboardShortcutsTable()
        }
    }

    private var aboutSection: some View {
        HelpSection(title: "About", systemImage: "info.circle") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("Jobhunt")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text(appVersion)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Text("Local-first job tracker — all data stored locally on your machine.")
                    .font(.body)
                    .foregroundStyle(.secondary)

                Divider()

                HelpMarkdown("""
                **Privacy** — All data is stored in a local SQLite database. Nothing is sent \
                to any remote server. When using a cloud AI provider, only job posting text is \
                sent to that provider's API for extraction. When using LM Studio or Ollama, all \
                AI processing stays on-device.

                The Chrome extension only communicates with the local Jobhunt service running \
                on your machine (localhost).
                """)

                HStack(spacing: 12) {
                    Link("jobhunt-app.com", destination: URL(string: "https://jobhunt-app.com")!)
                        .font(.callout)
                    Link("github.com/brooksc/jobhunt", destination: URL(string: "https://github.com/brooksc/jobhunt")!)
                        .font(.callout)
                }
            }
        }
    }

    // MARK: - Helpers

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }
}

// MARK: - Supporting Views

private struct HelpSection<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.title3)
                .fontWeight(.semibold)

            content()
                .padding(.leading, 4)

            Divider()
        }
    }
}

private struct HelpMarkdown: View {
    private let attributed: AttributedString

    init(_ markdown: String) {
        // Collapse line continuations so paragraphs render as single lines.
        let collapsed = markdown
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: "\n")
        if let parsed = try? AttributedString(markdown: collapsed) {
            attributed = parsed
        } else {
            attributed = AttributedString(markdown)
        }
    }

    var body: some View {
        Text(attributed)
            .font(.body)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct SettingsRow: View {
    let name: String
    let description: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name)
                .font(.subheadline)
                .fontWeight(.medium)
            Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    NavigationSplitView {
        Text("Sidebar")
    } content: {
        HelpView()
    } detail: {
        Text("Detail")
    }
    .frame(width: 900, height: 700)
}
