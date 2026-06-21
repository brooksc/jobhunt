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
            **Jobhunt** is a local-first job tracker. The Chrome extension captures job pages and \
            sends them to the native macOS app over a local connection; the app stores them and \
            helps you extract structured fields, track follow-ups, review data quality, and manage \
            your pipeline.

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
            **Capture** → The Chrome extension sends the page text and any selected text to the \
            Jobhunt app over a local connection (localhost) on your machine.

            **Extraction** → An AI model (local via LM Studio/Ollama, or a cloud API) reads \
            the captured text and fills structured fields: title, company, location, salary, \
            work arrangement, and more.

            **Fit Scoring** → The model rates each job 0–100 against your resume and breaks \
            the score down by dimension (skills, seniority, location, work arrangement).

            **Local-first** → All data is stored locally on your Mac by the app. When you use a \
            local model (LM Studio, Ollama, or a custom endpoint on localhost), all AI \
            processing stays on-device and nothing leaves your machine. When you use a cloud \
            provider — or a custom endpoint that isn't local — job description text is sent for \
            extraction and, for fit scoring, your resume text is sent along with the job text. \
            These remote providers require your consent before any data is sent.
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

            New captures are extracted automatically. To re-process a job, use **Re-run AI** \
            (on a job's detail pane, or on a selection in **Jobs** / **Data Quality**). To \
            recompute fit after updating your resume without re-extracting, use **Score against \
            resume** on the job's **Fit** tab.
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

            **Extension not connecting** — The Jobhunt app must be open — it runs the local \
            connection (localhost) the extension talks to. Restart the app if the extension can't \
            reach it.

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
                    description: "Default number of days used to pre-fill a follow-up reminder when you apply. " +
                        "You are offered (not automatically scheduled) a follow-up when you mark a job applied."
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
                    Text("JobHunt")
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
                **Privacy** — All data is stored locally on your Mac by the app. When you use a \
                local model (LM Studio, Ollama, or a custom endpoint on localhost), all AI \
                processing stays on-device and nothing leaves your machine. When you use a \
                cloud provider — or a custom endpoint that isn't local — job description text \
                is sent for extraction and, for fit scoring, your resume text is sent along \
                with the job text. These remote providers require your consent before any \
                data is sent.

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
