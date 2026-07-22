import AppKit
import JobhuntCore
import SwiftData
import SwiftUI

/// "Prompt AI" menu for the displayed job (TASK-606): builds a deterministic, self-contained prompt
/// (resume tailoring, interview prep, cover letter, fit assessment, outreach) from the job + best
/// resume + fit analysis, and copies it or opens it in ChatGPT/Claude. Never calls the app's own AI.
struct JobPromptMenu: View {
    let job: Job

    @Environment(AppServices.self) private var appServices
    @Query(
        filter: #Predicate<Resume> { $0.active == true },
        sort: \Resume.sortOrder
    ) private var activeResumes: [Resume]

    /// A queued external open awaiting the one-time privacy acknowledgement.
    @State private var pendingOpen: PendingOpen?
    /// Presents the one-time heads-up before the first auto-apply copy that embeds personal details.
    @State private var showAutoApplyPrivacyPrompt = false

    private struct PendingOpen: Identifiable {
        let id = UUID()
        let kind: JobPromptKind
        let provider: AIChatProvider
    }

    private var hasDescription: Bool {
        !(job.capture?.cleanedDescription ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var usableResume: Resume? {
        guard !activeResumes.isEmpty else { return nil }
        // Prefer the active resume with the highest completed fit score for this job.
        let best = job.fitScores
            .filter { ($0.resume?.active ?? false) && $0.fitScore != nil }
            .max { ($0.fitScore ?? -1) < ($1.fitScore ?? -1) }?
            .resume
        // Else the sole/first active resume (sorted by sortOrder).
        return best ?? activeResumes.first
    }

    private var isUsable: Bool {
        guard let resume = usableResume else { return false }
        return hasDescription && !resume.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var disabledHelp: String {
        if activeResumes.isEmpty { return "Add and activate a résumé in Resumes to use AI prompts" }
        if !hasDescription { return "This job has no captured description text to build a prompt from" }
        return "The active résumé has no text to build a prompt from"
    }

    var body: some View {
        Menu {
            // Chat prompts embed the job + résumé; disabled (with a reason) when either is missing.
            if !isUsable {
                Text(disabledHelp)
            }
            ForEach(JobPromptKind.chatKinds, id: \.self) { kind in
                Menu(kind.title) {
                    Button("Copy Prompt") { copy(kind) }
                    Button("Open in ChatGPT") { requestOpen(kind, .chatGPT) }
                    Button("Open in Claude") { requestOpen(kind, .claude) }
                }
                .disabled(!isUsable)
            }
            Divider()
            // Codex auto-apply agent prompt — uses local files + the browser, so it's always available
            // (independent of the app's résumé) and copy-only (meant to paste into a Codex session).
            Button("Copy Auto-Apply Prompt (Codex)") { requestCopyAutoApply() }
        } label: {
            Label("Prompt AI", systemImage: "sparkles")
                .font(.caption2.weight(.semibold))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Generate an AI prompt from this job (résumé prompts need an active résumé)")
        .confirmationDialog(
            "Open in \(pendingOpen?.provider.displayName ?? "the AI chat")?",
            isPresented: Binding(get: { pendingOpen != nil }, set: { if !$0 { pendingOpen = nil } }),
            presenting: pendingOpen
        ) { open in
            Button("Copy & Open \(open.provider.displayName)") { acknowledgeAndOpen(open) }
            Button("Cancel", role: .cancel) { pendingOpen = nil }
        } message: { open in
            Text("Your full résumé and the job description will be placed in a \(open.provider.displayName) "
                + "URL, which may be retained in browser history, sync, or logs. The prompt is also copied "
                + "to your clipboard.")
        }
        .confirmationDialog(
            "This prompt includes your Application Details",
            isPresented: $showAutoApplyPrivacyPrompt
        ) {
            Button("Copy Prompt") { acknowledgeAndCopyAutoApply() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The Auto-Apply prompt embeds the personal details you entered in Settings — including "
                + "contact info, address, work authorization, and any EEO answers — so Codex can fill "
                + "applications. It's copied to your clipboard to paste into Codex. (Shown once.)")
        }
    }

    // MARK: - Actions

    private func buildPrompt(_ kind: JobPromptKind, resume: Resume) -> String {
        JobPromptBuilder.build(kind: kind, input: promptInput(resume: resume))
    }

    private func copy(_ kind: JobPromptKind) {
        guard let resume = usableResume, isUsable else {
            appServices.toastStore.show(disabledHelp, isError: true)
            return
        }
        setClipboard(buildPrompt(kind, resume: resume))
        appServices.toastStore.show("\(kind.title) prompt copied (using \(resume.name))")
    }

    /// Gate the first auto-apply copy on a one-time heads-up when it will embed personal details; if the
    /// Application Details field is empty (nothing sensitive) or already acknowledged, copy directly.
    private func requestCopyAutoApply() {
        let hasPersonalInfo = !appServices.settings.string(forKey: SettingsKey.applicationPersonalInfo)
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let acknowledged = appServices.settings.bool(forKey: SettingsKey.autoApplyPersonalInfoAcknowledged)
        if hasPersonalInfo, !acknowledged {
            showAutoApplyPrivacyPrompt = true
        } else {
            copyAutoApply()
        }
    }

    private func acknowledgeAndCopyAutoApply() {
        appServices.settings.setBool(true, forKey: SettingsKey.autoApplyPersonalInfoAcknowledged)
        copyAutoApply()
    }

    /// The Codex auto-apply prompt needs only the job URL (it uses local résumé files + the browser),
    /// so it works regardless of the app's résumé/description state.
    private func copyAutoApply() {
        let url = JobURLPolicy.sourceURL(job: job) ?? ""
        let prompt = JobPromptBuilder.build(
            kind: .autoApply,
            input: JobPromptInput(
                role: "", company: "", location: "", sourceURL: url,
                jobDescription: "", resumeName: "", resumeText: "", fit: nil,
                personalInfo: appServices.settings.string(forKey: SettingsKey.applicationPersonalInfo)
            )
        )
        setClipboard(prompt)
        appServices.toastStore.show(
            url.isEmpty
                ? "Auto-Apply (Codex) prompt copied — add the job URL where marked, then paste into Codex"
                : "Auto-Apply (Codex) prompt copied — paste into Codex"
        )
    }

    /// Gate the first external open on the privacy acknowledgement; thereafter open directly.
    private func requestOpen(_ kind: JobPromptKind, _ provider: AIChatProvider) {
        guard usableResume != nil, isUsable else {
            appServices.toastStore.show(disabledHelp, isError: true)
            return
        }
        if appServices.settings.bool(forKey: SettingsKey.aiPromptExternalOpenAcknowledged) {
            performOpen(kind, provider)
        } else {
            pendingOpen = PendingOpen(kind: kind, provider: provider)
        }
    }

    private func acknowledgeAndOpen(_ open: PendingOpen) {
        appServices.settings.setBool(true, forKey: SettingsKey.aiPromptExternalOpenAcknowledged)
        pendingOpen = nil
        performOpen(open.kind, open.provider)
    }

    private func performOpen(_ kind: JobPromptKind, _ provider: AIChatProvider) {
        guard let resume = usableResume else { return }
        let prompt = buildPrompt(kind, resume: resume)
        // Always copy first, so a failed/blank prefill still leaves the user the full prompt to paste.
        setClipboard(prompt)
        if let url = provider.prefillURL(prompt: prompt) {
            NSWorkspace.shared.open(url)
            appServices.toastStore
                .show("Opened \(provider.displayName) — prompt copied & prefilled (using \(resume.name))")
        } else {
            NSWorkspace.shared.open(provider.blankChatURL)
            appServices.toastStore.show(
                "Opened \(provider.displayName) — prompt is too long to prefill, so it's on your clipboard to paste"
            )
        }
    }

    private func setClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func promptInput(resume: Resume) -> JobPromptInput {
        JobPromptInput(
            role: job.title ?? "",
            company: job.company ?? "",
            location: job.location ?? "",
            sourceURL: JobURLPolicy.sourceURL(job: job) ?? "",
            jobDescription: job.capture?.cleanedDescription ?? "",
            resumeName: resume.name,
            resumeText: resume.text,
            fit: fitSummary(for: resume)
        )
    }

    private func fitSummary(for resume: Resume) -> JobPromptInput.FitSummary? {
        guard let fs = job.fitScores.first(where: { $0.resume?.id == resume.id && $0.fitScore != nil }) else {
            return nil
        }
        let proj = FitScoreProjection(fitScore: fs)
        let gaps = proj.requirementAssessments
            .filter { !$0.isMet }
            .map { "\($0.requirement) (\($0.kind), \($0.status))" }
        let notes = proj.dimensions.compactMap { dim in
            dim.rationale.map { "\(dim.name) (\(dim.score)): \($0)" }
        }
        return JobPromptInput.FitSummary(
            overall: fs.fitScore ?? 0,
            requirementsMet: proj.requirementsMet,
            requirementGaps: gaps.isEmpty ? proj.requirementsNotMet : gaps,
            dimensionNotes: notes
        )
    }
}
