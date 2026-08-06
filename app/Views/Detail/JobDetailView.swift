import JobhuntCore
import SwiftData

// swiftlint:disable file_length
import SwiftUI

// MARK: - JobDetailView

struct JobDetailView: View {
    let job: Job
    var onNavigatePrev: () -> Void = {}
    var onNavigateNext: () -> Void = {}
    var onClose: () -> Void = {}

    @Environment(Router.self) private var router
    @Environment(AppServices.self) private var appServices
    @Environment(\.jobService) private var jobService
    @Environment(\.queueActor) private var queueActor
    @Environment(\.modelContext) private var modelContext

    @State private var selectedTab: DetailTab = .overview
    /// Identifies this detail instance's ⌃Tab cycling hook so a per-job re-mount doesn't clear the
    /// incoming instance's registration (TASK-499).
    @State private var cycleToken = UUID()

    enum DetailTab: String, CaseIterable {
        case overview = "Overview"
        case fit = "Fit"
        case timeline = "Timeline"
        case description = "Description"
        case raw = "Raw"
        case compare = "Compare"
    }

    private var visibleTabs: [DetailTab] {
        var tabs: [DetailTab] = [.overview, .fit, .timeline, .description, .raw]
        if job.duplicateOfJobID != nil { tabs.append(.compare) }
        return tabs
    }

    private var timelineCount: Int {
        job.events.count + job.actions.count
    }

    var body: some View {
        VStack(spacing: 0) {
            DetailHeader(
                job: job,
                selectedTab: $selectedTab,
                onNavigatePrev: onNavigatePrev,
                onNavigateNext: onNavigateNext,
                onClose: onClose
            )
            Divider()
            // HIG-5: system segmented Picker replaces hand-rolled tab bar
            Picker("Tab", selection: stickyTabSelection) {
                ForEach(visibleTabs, id: \.self) { tab in
                    Text(tab == .timeline && timelineCount > 0
                        ? "\(tab.rawValue) (\(timelineCount))"
                        : tab.rawValue)
                        .tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            Divider()
            tabBody
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if selectedTab == .overview {
                Divider()
                DetailFooter(job: job)
            }
        }
        .onKeyPress(.escape) { onClose(); return .handled }
        // "Add Note" from the Jobs row context menu selects the job and asks us to open its
        // Timeline tab for note entry. The view re-mounts per job (.id(job.id)), so onAppear
        // covers a fresh selection and onChange covers re-triggering on the same job.
        // Restore the sticky tab FIRST so a pending note request still wins for this open.
        .onAppear {
            restoreStickyTab()
            consumeComposeNoteRequest()
            // TASK-499: let the ⌃Tab / ⌃⇧Tab key monitor cycle this detail's tabs while it's visible.
            router.detailTabCycler = Router.DetailTabCycler(token: cycleToken) { forward in
                cycleTab(forward: forward)
            }
        }
        .onDisappear {
            // Only clear our own hook — during a per-job re-mount the incoming detail may already have
            // installed its own before this outgoing one disappears.
            if router.detailTabCycler?.token == cycleToken { router.detailTabCycler = nil }
        }
        .onChange(of: router.composeNoteJobID) { _, _ in consumeComposeNoteRequest() }
    }

    /// Cycle to the next/previous visible tab with wraparound (⌃Tab / ⌃⇧Tab). Persists like a
    /// deliberate pick so the sticky default follows the user's last tab (TASK-499).
    private func cycleTab(forward: Bool) {
        let tabs = visibleTabs
        let current = tabs.firstIndex(of: selectedTab) ?? 0
        let nextIndex = TabCycling.next(count: tabs.count, from: current, forward: forward)
        stickyTabSelection.wrappedValue = tabs[nextIndex]
    }

    /// Picker binding that persists the choice — but ONLY deliberate segmented-control picks. The
    /// imperative jumps to `.timeline` (Add Note / overdue badge / header Note button) and the
    /// Overview "see Fit" button assign `selectedTab` directly and bypass this, so a one-off jump
    /// doesn't become the sticky default.
    private var stickyTabSelection: Binding<DetailTab> {
        Binding(
            get: { selectedTab },
            set: { newValue in
                selectedTab = newValue
                appServices.settings.detailLastTab = newValue.rawValue
            }
        )
    }

    /// Seed the tab from the last deliberately-chosen one (sticky across jobs + relaunch). Falls back
    /// to the default `.overview`, and ignores a saved tab that isn't visible for this job (e.g.
    /// `.compare` on a non-duplicate).
    private func restoreStickyTab() {
        if let saved = DetailTab(rawValue: appServices.settings.detailLastTab),
           visibleTabs.contains(saved) {
            selectedTab = saved
        }
    }

    private func consumeComposeNoteRequest() {
        if router.composeNoteJobID == job.id {
            selectedTab = .timeline
            router.composeNoteJobID = nil
        }
    }

    @ViewBuilder
    private var tabBody: some View {
        switch selectedTab {
        case .overview: OverviewTabView(job: job, goFit: { selectedTab = .fit })
        case .fit: FitTabView(job: job)
        case .timeline: TimelineTabView(job: job)
        case .description: DescriptionTabView(job: job)
        case .raw: RawTabView(job: job, onClose: onClose)
        case .compare: CompareTabView(job: job)
        }
    }
}

// MARK: - Header

private struct DetailHeader: View {
    let job: Job
    @Binding var selectedTab: JobDetailView.DetailTab
    let onNavigatePrev: () -> Void
    let onNavigateNext: () -> Void
    let onClose: () -> Void
    @Environment(\.jobService) private var jobService
    @Environment(AppServices.self) private var appServices
    @State private var showNoteSheet = false
    @State private var quickNoteText = ""
    @State private var showApplyConfirmation = false
    @State private var isEnqueuing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Row 1: company mark + company name + domain
            HStack(spacing: 10) {
                CompanyMarkView(name: job.company, size: 28)
                HStack(spacing: 6) {
                    if let company = job.company {
                        Text(company)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.primary)
                    }
                    if let domain = captureDomain {
                        Text(domain)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.08))
                            .clipShape(Capsule())
                    }
                }
                Spacer()
                // Report a data problem with this job as a prefilled GitHub issue (TASK-638).
                JobIssueButton(job: job)
                // AI prompt menu (TASK-606) — build a resume/interview/cover-letter/etc. prompt.
                JobPromptMenu(job: job)
                // Prev/Next placeholders for keyboard nav
                HStack(spacing: 4) {
                    Button { onNavigatePrev() } label: {
                        Image(systemName: "chevron.up").font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    Button { onNavigateNext() } label: {
                        Image(systemName: "chevron.down").font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    Button { onClose() } label: {
                        Image(systemName: "xmark").font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Close")
                    .accessibilityLabel("Close")
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 11)
            .padding(.bottom, 4)

            // Row 2: job number + title
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if let num = job.jobNumber {
                    Text("#\(num)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
                Text(job.displayTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Spacer(minLength: 8)

                // Overdue follow-up surfaced on the header (otherwise only visible in Needs Action /
                // the Timeline tab) — click to jump to the timeline where it lives.
                if overdueActionCount > 0 {
                    Button {
                        selectedTab = .timeline
                    } label: {
                        Label("\(overdueActionCount) overdue", systemImage: "clock.badge.exclamationmark")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                    .help("Overdue follow-up — open the Timeline")
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 4)

            // Row 3: meta chips
            HStack(spacing: 6) {
                if let loc = job.location { metaChip(loc) }
                if let remote = job.remoteType, remote != .unknown { metaChip(remote.displayName) }
                if let sal = salaryText { metaChip(sal).font(.caption.monospacedDigit()) }
                if let emp = job.employmentType { metaChip(emp) }
                // TASK-464: location/remote criteria pass/fail (only when computed).
                // Same three-bucket vocabulary as the Jobs filter, so a posting that merely never
                // stated its arrangement doesn't read as a rejection here while the filter files it
                // under "Not stated".
                if let verdict = JobRequirements.evaluate(
                    meetsCriteria: job.meetsCriteria,
                    remoteType: job.remoteType,
                    salaryMin: job.salaryMin,
                    salaryMax: job.salaryMax,
                    salaryCurrency: job.salaryCurrency,
                    fitScore: job.fitScore,
                    thresholds: JobRequirements.Thresholds(
                        minSalary: appServices.settings.minSalary,
                        minFitScore: appServices.settings.minFitScore
                    )
                ) {
                    let bucket = verdict.bucket
                    // The reason rides ON the badge, not only in the tooltip: "Outside criteria"
                    // alone gives no way to tell a salary miss from a location one, and a verdict
                    // you have to hover to understand isn't usable while triaging (job #612 read as
                    // outside criteria purely because its fit was 44 against a floor of 50).
                    Label(
                        verdict.badgeText(bucket.label),
                        systemImage: bucket == .meets ? "checkmark.circle"
                            : bucket == .notStated ? "questionmark.circle" : "xmark.circle"
                    )
                    .foregroundStyle(bucket == .meets ? Color.green
                        : bucket == .notStated ? Color.secondary : Color.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .help(verdict.summary)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.bottom, 8)

            // Row 4: action bar
            HStack(spacing: 6) {
                StatusPickerButton(job: job)
                    .layoutPriority(1)

                Divider().frame(height: 16).padding(.horizontal, 2)

                if let urlStr = JobURLPolicy.displayURL(job: job), let url = URL(string: urlStr) {
                    Link(destination: url) {
                        Label("Open Posting", systemImage: "arrow.up.right.square")
                    }
                    .buttonStyle(.bordered)
                    .tint(.accentColor)
                    .help("Open the original job posting in your browser")
                }

                // Outbound research: a referral and the official posting are the two biggest boosts to
                // getting an application seen (TASK-604).
                if let referralURL = JobSearchLinks.linkedInConnectionsURL(company: job.company) {
                    let referralHelp = "Search LinkedIn for connections at "
                        + "\(job.company ?? "this company") who could refer you"
                    Button {
                        NSWorkspace.shared.open(referralURL)
                    } label: {
                        Label("Find a referral", systemImage: "person.2.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(referralHelp)
                }

                if let siteSearchURL = JobSearchLinks.companySiteSearchURL(company: job.company, title: job.title) {
                    let alreadyDirect = JobSearchLinks.postingIsOnCompanySite(
                        company: job.company,
                        postingURL: JobURLPolicy.displayURL(job: job)
                    )
                    let siteHelp = alreadyDirect
                        ? "This posting already looks like it's on \(job.company ?? "the company")'s own site"
                        : "Search Google for the official posting on the company's own site"
                    Button {
                        NSWorkspace.shared.open(siteSearchURL)
                    } label: {
                        Label("Find on company site", systemImage: "magnifyingglass")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(alreadyDirect)
                    .help(siteHelp)
                }

                Button {
                    guard !isEnqueuing else { return }
                    isEnqueuing = true
                    Task {
                        do { try await jobService?.resetExtraction(jobID: job.id) } catch { appServices.toastStore.show(
                            "Couldn't re-run AI: \(error.localizedDescription)",
                            isError: true
                        ) }
                        try? await Task.sleep(nanoseconds: 800_000_000)
                        isEnqueuing = false
                    }
                } label: {
                    if isEnqueuing {
                        HStack(spacing: 4) {
                            ProgressView().scaleEffect(0.5).frame(width: 10, height: 10)
                            Text("Queued").font(.caption)
                        }
                        .foregroundStyle(Color.accentColor)
                    } else {
                        Label(
                            job.extractionStatus == .pending ? "Run AI" : "Re-run",
                            systemImage: "arrow.clockwise"
                        )
                        .font(.caption)
                        .foregroundStyle(job.extractionStatus == .pending ? Color.accentColor : .secondary)
                    }
                }
                .buttonStyle(.plain)
                .disabled(isEnqueuing || job.extractionStatus == .running)
                .help(job.extractionStatus == .pending ? "Run AI extraction" : "Re-run AI extraction")

                Button {
                    selectedTab = .timeline
                } label: {
                    Label("Note", systemImage: "note.text.badge.plus")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Add a note to the timeline")

                Spacer()

                ExtractionChip(status: job.extractionStatus)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 10)

            // Surface WHY extraction failed, with a one-click re-run — otherwise the only place the
            // reason appears is the LLM Queue's error column, and the job just shows a red chip.
            if job.extractionStatus == .failed, let err = job.extractionError,
               !err.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    Spacer(minLength: 8)
                    Button("Re-run") {
                        guard !isEnqueuing else { return }
                        isEnqueuing = true
                        Task {
                            do { try await jobService?.resetExtraction(jobID: job.id) } catch {
                                appServices.toastStore.show(
                                    "Couldn't re-run AI: \(error.localizedDescription)",
                                    isError: true
                                )
                            }
                            try? await Task.sleep(nanoseconds: 800_000_000)
                            isEnqueuing = false
                        }
                    }
                    .font(.caption)
                    .disabled(isEnqueuing)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
            }
        }
    }

    @Environment(Router.self) private var router

    private var overdueActionCount: Int {
        let now = Date()
        return job.actions.count(where: { $0.completedAt == nil && $0.dueDate < now })
    }

    private var captureDomain: String? {
        guard let urlStr = JobURLPolicy.displayURL(job: job),
              let url = URL(string: urlStr),
              let host = url.host else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    private var salaryText: String? {
        SalaryDisplay.text(min: job.salaryMin, max: job.salaryMax, currency: job.salaryCurrency)
    }

    private func metaChip(_ text: String) -> some View {
        Text(text).foregroundStyle(.secondary)
    }
}

// MARK: - Navigation notifications

extension Notification.Name {
    static let navigatePreviousJob = Notification.Name("JobDetail.navigatePreviousJob")
    static let navigateNextJob = Notification.Name("JobDetail.navigateNextJob")
}

// MARK: - Status picker button

private struct StatusPickerButton: View {
    @Environment(AppServices.self) private var appServices
    let job: Job
    @Environment(\.jobService) private var jobService
    @State private var showPicker = false

    var body: some View {
        Button { showPicker.toggle() } label: {
            HStack(spacing: 4) {
                Circle()
                    .fill(Theme.statusColor(job.status))
                    .frame(width: 7, height: 7)
                Text(job.status.displayName)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
                    // The chip is a fixed-size control in a horizontally-compressed strip; without
                    // this the longest label ("Interested") wraps mid-word to "Interest-ed".
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.secondary.opacity(0.08))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showPicker) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(JobStatus.allCases, id: \.self) { s in
                    Button {
                        let old = job.status
                        Task {
                            do {
                                try await jobService?.setStatus(s, for: job.id)
                                if s != old {
                                    appServices.toastStore.show("Status set to \(s.displayName)", actionLabel: "Undo") {
                                        Task {
                                            do { try await jobService?.setStatus(old, for: job.id) } catch {
                                                appServices.toastStore.show(
                                                    "Couldn't undo: \(error.localizedDescription)", isError: true
                                                )
                                            }
                                        }
                                    }
                                }
                            } catch { appServices.toastStore.show(
                                "Couldn't change status: \(error.localizedDescription)",
                                isError: true
                            ) }
                        }
                        showPicker = false
                    } label: {
                        HStack {
                            Circle().fill(Theme.statusColor(s)).frame(width: 7, height: 7)
                            Text(s.displayName).font(.caption)
                            Spacer()
                            if s == job.status {
                                Image(systemName: "checkmark").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 12).padding(.vertical, 5).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 6).frame(minWidth: 140)
        }
    }
}

// MARK: - Footer

private struct DetailFooter: View {
    let job: Job
    @Environment(\.jobService) private var jobService
    @Environment(Router.self) private var router
    @Environment(AppServices.self) private var appServices
    @State private var showApplyConfirmation = false

    private var pendingAction: JobAction? {
        let now = Date()
        return job.actions
            .filter { FollowUpVisibility.isActionable($0, now: now) }
            .sorted { $0.dueDate < $1.dueDate }
            .first
    }

    private func completeWithUndo(actionID: String) {
        completeFollowUpWithUndo(actionID: actionID, jobService: jobService, toastStore: appServices.toastStore)
    }

    var body: some View {
        HStack(spacing: 10) {
            // Capture date note
            if let cap = job.capture?.capturedAt {
                Text("\(job.status.displayName) · captured \(relativeCaptured(cap))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            // TASK-504: surface the application date once the job has been applied to.
            if let appliedAt = job.appliedAt {
                Label(
                    "Applied \(appliedAt.formatted(date: .abbreviated, time: .omitted))",
                    systemImage: "paperplane.fill"
                )
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)
            }
            Spacer()
            if let action = pendingAction {
                HStack(spacing: 6) {
                    Image(systemName: "flag.fill").font(.caption2).foregroundStyle(.orange)
                    Text(action.note).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    Button {
                        completeWithUndo(actionID: action.id)
                    } label: { Image(systemName: "checkmark").font(.caption2) }
                        .buttonStyle(.bordered).controlSize(.mini)
                }
            }
            if job.status == .pursuing || job.status == .new,
               let urlStr = JobURLPolicy.applicationURL(job: job),
               let url = URL(string: urlStr) {
                Button("Apply") { showApplyConfirmation = true }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .font(.caption.weight(.semibold))
                    .confirmationDialog("Mark as applied?", isPresented: $showApplyConfirmation) {
                        Button("Mark as Applied") {
                            NSWorkspace.shared.open(url)
                            Task {
                                do {
                                    try await jobService?.setStatus(.applied, for: job.id)
                                    let days = appServices.settings.followupDefaultDays
                                    let due = Calendar.current.date(byAdding: .day, value: days, to: Date()) ?? Date()
                                    let who = [job.company, job.title].compactMap(\.self).joined(separator: " — ")
                                    let followText = who.isEmpty ? "Follow up on application" : "Follow up on \(who)"
                                    try await jobService?.createAction(jobID: job.id, text: followText, dueAt: due)
                                } catch {
                                    appServices.toastStore.show(
                                        "Couldn't mark as applied: \(error.localizedDescription)",
                                        isError: true
                                    )
                                }
                            }
                        }
                        Button("Just Open URL") { NSWorkspace.shared.open(url) }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text(
                            "Opening the application. Would you like to mark this job as applied " +
                                "and schedule a follow-up?"
                        )
                    }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    private func relativeCaptured(_ date: Date) -> String {
        let days = Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 0
        if days == 0 { return "today" }
        if days == 1 { return "yesterday" }
        return "\(days)d ago"
    }
}

// MARK: - Overview Tab

/// Split out of `OverviewTabView`'s body to stay within the type-length limit. Same file because the
/// stored properties it reads (`job`, `allJobs`) are private to it.
extension OverviewTabView {
    /// One line naming the other job and why they matched, with a route into the review screen.
    /// Deliberately informational — TASK-624 established that suspected duplicates are never acted on
    /// automatically, only confirmed by the user.
    @ViewBuilder
    func duplicateNotice(_ pair: DuplicatePair) -> some View {
        let other = pair.candidate.id == job.id ? pair.original : pair.candidate
        HStack(spacing: 6) {
            Image(systemName: "doc.on.doc")
            Text(duplicateNoticeText(other: other, pair: pair))
            Button("Review") { router.navigateToSection(.duplicates) }
                .buttonStyle(.link)
            Spacer()
        }
        .font(.caption)
        .foregroundStyle(.orange)
        .help("\(pair.reason). Nothing is changed until you resolve it in the Duplicates screen.")
    }

    func duplicateNoticeText(other: JobSnapshot, pair: DuplicatePair) -> String {
        let who = other.company ?? other.title ?? "another job"
        let number = other.jobNumber.map { "#\($0) " } ?? ""
        let percent = Int((pair.confidence * 100).rounded())
        return "Possible duplicate of \(number)\(who) — \(percent)% match"
    }

    /// Recompute the suspected-duplicate pair for this job. Runs off the render path (see the
    /// property's note) and only for jobs that are themselves reviewable.
    func refreshSuspectedDuplicate() {
        let corpus = DuplicateDetector.reviewSnapshots(jobs: allJobs)
        guard let candidate = corpus.first(where: { $0.id == job.id }) else {
            suspectedDuplicate = nil // terminal/marked jobs aren't reviewable
            return
        }
        let resolved = Set(duplicateDecisions.map(\.cleanedHash))
        suspectedDuplicate = DuplicateDetector()
            .duplicatePairForCandidate(candidate, among: corpus, resolvedHashes: resolved)
    }

    /// Other still-open roles at this company (+ any past rejection), ranked by fit so the reader can
    /// tell which of a company's postings is the better bet before applying.
    private var companyContext: CompanyContext.Result {
        func role(_ j: Job) -> CompanyContext.Role {
            CompanyContext.Role(
                jobID: j.id, jobNumber: j.jobNumber, title: j.displayTitle,
                status: j.status, fitScore: j.fitScore
            )
        }
        return CompanyContext.build(
            viewed: role(job),
            company: job.company,
            among: allJobs.map { (role($0), $0.company) }
        )
    }

    /// Prior applications at the same company — only surfaced while the job is Interested (TASK-615).
    private var priorApplicationMatches: [PriorApplications.Match] {
        guard job.status == .pursuing else { return [] }
        let viewed = PriorApplications.JobInput(
            jobID: job.id, jobNumber: job.jobNumber, company: job.company, title: job.title,
            currentStatus: job.status.rawValue, appliedAt: job.appliedAt
        )
        let others = allJobs.map {
            PriorApplications.JobInput(
                jobID: $0.id, jobNumber: $0.jobNumber, company: $0.company, title: $0.title,
                currentStatus: $0.status.rawValue, appliedAt: $0.appliedAt
            )
        }
        return PriorApplications.priorApplications(for: viewed, among: others)
    }
}

struct OverviewTabView: View {
    @Environment(AppServices.self) private var appServices
    let job: Job
    let goFit: () -> Void

    @Environment(\.jobService) private var jobService
    @Environment(Router.self) private var router

    @Query private var resumes: [Resume]
    /// All jobs — for the prior-application safeguard (TASK-615).
    @Query private var allJobs: [Job]
    /// Resolved duplicate decisions, so an already-reviewed pair stops being flagged.
    @Query private var duplicateDecisions: [DuplicateDecision]

    /// The unresolved duplicate pair this job belongs to, if any.
    ///
    /// Computed in `.task`, never in `body`: building snapshots touches every job's Capture, which is
    /// exactly the per-render faulting cost TASK-610 removed from search and TASK-364 moved off the
    /// sidebar's render path. Recomputed when the selected job changes.
    @State private var suspectedDuplicate: DuplicatePair?

    @State private var skills: [String] = []
    @State private var newSkillText = ""
    @State private var showAddSkill = false
    @State private var showDeleteConfirm = false
    @State private var errorMessage: String?
    @State private var editingField: String?
    @State private var editText: String = ""
    @FocusState private var editFocused: Bool
    // TASK-469: the original value + commit closure of the field currently being edited, so a
    // pencil tap on another row commits the in-progress edit to the RIGHT field before switching.
    @State private var activeCurrent: String = ""
    @State private var activeCommit: ((String) -> Void)?
    /// Cached AI-configured check. `AIConfig.isConfigured` reads the Keychain (a syscall), so it must
    /// not run in `body`; computed once per job in `.onAppear`. Defaults to `true` so neither the
    /// manual-entry hint nor a neutralized fit ring flashes before the check resolves.
    @State private var aiConfigured = true

    /// Cached projection (TASK-611). JobDetailProjection.init runs JSONSerialization on job.extractedJSON
    /// AND job.manualOverridesJSON; it was rebuilt 3× per render (summary/requirements/niceToHaves), and
    /// body re-renders per keystroke while inline-editing. Recompute only when those blobs change.
    @State private var projection: JobDetailProjection?

    private var summary: String? {
        projection?.summary
    }

    private var requirements: [String] {
        projection?.requirements ?? []
    }

    private var niceToHaves: [String] {
        projection?.niceToHaves ?? []
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Decision strip
                decisionStrip
                Divider()

                // Already applied to this company? (Interested jobs only — TASK-615)
                if !priorApplicationMatches.isEmpty {
                    PriorApplicationsWarning(
                        company: job.company ?? "this company",
                        matches: priorApplicationMatches,
                        onOpen: { id in router.selectJob(id: id) }
                    )
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                }

                // Referral outreach — only renders for applied/interview/offer jobs or ones with
                // recorded attempts (TASK-630).
                ReferralSection(job: job)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)

                // Interviews + offer — only renders at Interview/Offer or when records exist (TASK-501).
                MilestoneSection(job: job)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)

                // Suspected duplicate — a job in an unresolved review pair otherwise looks completely
                // ordinary here; the only hint lived on the Duplicates screen.
                if let pair = suspectedDuplicate {
                    duplicateNotice(pair)
                        .padding(.horizontal, 14)
                        .padding(.bottom, 4)
                }

                // Company context — one subtle line, directly above the pay range so it's read before
                // the decision to apply. Renders nothing when the company appears only once.
                CompanyContextLine(
                    company: job.displayCompany ?? "this company",
                    context: companyContext,
                    onOpen: { id in router.selectJob(id: id) }
                )
                .padding(.horizontal, 14)

                // Compensation block
                if job.salaryMin != nil || job.salaryMax != nil || job.salaryNote != nil {
                    compensationBlock
                    Divider()
                }

                VStack(alignment: .leading, spacing: 18) {
                    // Summary
                    if let text = summary, !text.isEmpty {
                        sectionBlock("Summary") {
                            Text(text).font(.caption).lineSpacing(4).textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    // Requirements
                    if !requirements.isEmpty {
                        sectionBlock("Requirements") { reqList(requirements) }
                    }

                    // Nice to have
                    if !niceToHaves.isEmpty {
                        sectionBlock("Bonus / Nice to Have") { reqList(niceToHaves) }
                    }

                    // Skills (editable)
                    skillsSection

                    // Details
                    detailsSection

                    if let err = errorMessage {
                        Text(err).font(.caption).foregroundStyle(.red)
                    }
                }
                .padding(14)
            }
        }
        .onAppear {
            loadSkills()
            aiConfigured = AIConfig.isConfigured(appServices.settings)
            projection = JobDetailProjection(job: job)
        }
        // Rebuild only when the parsed source changes — e.g. after an inline edit commits (TASK-611).
        .onChange(of: job.extractedJSON) { _, _ in projection = JobDetailProjection(job: job) }
        .onChange(of: job.manualOverridesJSON) { _, _ in projection = JobDetailProjection(job: job) }
        // Keyed on the job so it recomputes per selection, and runs off the render path.
        .task(id: job.id) { refreshSuspectedDuplicate() }
    }

    // MARK: Decision strip

    /// A fit score can only exist if an AI provider is configured and a résumé is active. When not,
    /// the fit indicator is neutralized rather than implying a forever-pending score (TASK-525).
    private var fitScoringAvailable: Bool {
        aiConfigured && resumes.contains(where: \.active)
    }

    /// Show the "add details manually" hint only when extraction won't fill the job in for them —
    /// no AI provider configured — and the job is still empty. Disappears once either changes.
    private var manualEntryHintVisible: Bool {
        !aiConfigured && job.company == nil && job.title == nil
    }

    private var decisionStrip: some View {
        HStack(spacing: 16) {
            // Fit ring + quality
            Button(action: goFit) {
                HStack(spacing: 12) {
                    if let score = job.fitScore {
                        FitRingView(score: score, size: 48)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(fitWord(score))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(fitColor(score))
                            HStack(spacing: 4) {
                                Text("\(job.fitScores.count) resume\(job.fitScores.count == 1 ? "" : "s") scored")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    } else if fitScoringAvailable {
                        Image(systemName: "sparkle")
                            .font(.title2)
                            .foregroundStyle(.quaternary)
                            .frame(width: 48, height: 48)
                        Text("Not scored")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    } else {
                        Image(systemName: "target")
                            .font(.title2)
                            .foregroundStyle(.quaternary)
                            .frame(width: 48, height: 48)
                        Text("Fit unavailable")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .buttonStyle(.plain)

            Spacer()

            // Rating + status indicator
            VStack(alignment: .trailing, spacing: 6) {
                InteractiveStarRating(rating: job.rating ?? 0) { newVal in
                    Task {
                        do { try await jobService?.setRating(newVal == 0 ? nil : newVal, for: job.id) } catch {
                            appServices.toastStore.show(
                                "Couldn't update rating: \(error.localizedDescription)",
                                isError: true
                            )
                        }
                    }
                }
                if job.status == .passed {
                    Label("Passed", systemImage: "hand.raised")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else if job.status == .applied {
                    Label("Applied", systemImage: "paperplane.fill")
                        .font(.caption2)
                        .foregroundStyle(.green)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    // MARK: Compensation

    private var compensationBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "dollarsign.circle")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
                Text(salaryText)
                    .font(.system(size: 18, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.primary)
                if let cur = job.salaryCurrency {
                    Text("\(cur) / yr")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                if let conf = job.extractionConfidence, conf < 0.85 {
                    HStack(spacing: 3) {
                        Image(systemName: "sparkle")
                            .font(.caption2)
                        Text("inferred")
                            .font(.caption2)
                    }
                    .foregroundStyle(.orange)
                }
            }
            if let note = job.salaryNote, !note.isEmpty {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
                    .textSelection(.enabled)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: Skills section

    private var skillsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Skills")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.4)
                Text("· \(skills.count)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
            }

            if skills.isEmpty {
                Text("No skills extracted")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                FlowLayout(spacing: 5) {
                    ForEach(skills, id: \.self) { skill in
                        HStack(spacing: 4) {
                            Text(skill)
                                .font(.caption)
                            Button {
                                if let idx = skills.firstIndex(of: skill) { skills.remove(at: idx) }
                                saveSkills()
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 8, weight: .bold))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                        }
                        .padding(.leading, 8)
                        .padding(.trailing, 6)
                        .padding(.vertical, 3)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(Capsule())
                    }
                    // Add button
                    if showAddSkill {
                        HStack(spacing: 4) {
                            TextField("skill", text: $newSkillText)
                                .font(.caption)
                                .frame(minWidth: 60, maxWidth: 120)
                                .textFieldStyle(.roundedBorder)
                                .controlSize(.mini)
                                .onSubmit { commitNewSkill() }
                            Button { commitNewSkill() } label: {
                                Image(systemName: "checkmark").font(.caption2)
                            }
                            .buttonStyle(.plain)
                            Button { showAddSkill = false; newSkillText = "" } label: {
                                Image(systemName: "xmark").font(.caption2)
                            }
                            .buttonStyle(.plain)
                        }
                    } else {
                        Button { showAddSkill = true } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "plus").font(.system(size: 9, weight: .bold))
                                Text("add")
                            }
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.secondary.opacity(0.07))
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: Details section

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Details")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.4)
                .padding(.bottom, 8)

            // No AI configured and nothing filled in yet — point the user at manual entry so the job
            // doesn't look broken. Non-nagging: disappears once a provider is set up or a field is
            // filled (TASK-525).
            if manualEntryHintVisible {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.pencil")
                        .foregroundStyle(.secondary)
                    Text("No AI provider configured — add details manually below, or set up AI extraction.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    SettingsLink { Text("Set Up AI").font(.caption) }
                }
                .padding(8)
                .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                .padding(.bottom, 8)
            }

            VStack(alignment: .leading, spacing: 0) {
                editableRow("Company", job.company ?? "", placeholder: "Add company") { v in
                    Task {
                        do { try await jobService?.updateJobFields(jobID: job.id, company: .some(v.isEmpty ? nil : v))
                        } catch { appServices.toastStore.show(
                            "Couldn't save company: \(error.localizedDescription)",
                            isError: true
                        ) }
                    }
                }
                Divider()
                editableRow("Title", job.title ?? "", placeholder: "Add title") { v in
                    Task {
                        do { try await jobService?.updateJobFields(jobID: job.id, title: .some(v.isEmpty ? nil : v))
                        } catch { appServices.toastStore.show(
                            "Couldn't save title: \(error.localizedDescription)",
                            isError: true
                        ) }
                    }
                }
                Divider()
                editableRow("Location", job.location ?? "", placeholder: "Add location") { v in
                    Task {
                        do { try await jobService?.updateJobFields(jobID: job.id, location: .some(v.isEmpty ? nil : v))
                        } catch { appServices.toastStore.show(
                            "Couldn't save location: \(error.localizedDescription)",
                            isError: true
                        ) }
                    }
                }
                Divider()
                editableRow("Application URL", job.applicationURL ?? "", placeholder: "Add application link") { v in
                    Task {
                        do { try await jobService?.updateJobFields(
                            jobID: job.id,
                            applicationURL: .some(v.isEmpty ? nil : v)
                        ) } catch { appServices.toastStore.show(
                            "Couldn't save URL: \(error.localizedDescription)",
                            isError: true
                        ) }
                    }
                }
                Divider()
                if let seniority = job.seniority {
                    detailRow("Seniority", value: seniority)
                    Divider()
                }
                if let emp = job.employmentType {
                    detailRow("Role type", value: emp)
                    Divider()
                }
                if let num = job.jobNumber {
                    detailRow("Job number", value: "#\(num)")
                    Divider()
                }
                if let model = job.extractionModel {
                    detailRow("Extracted by", value: model)
                    Divider()
                }
                if let conf = job.extractionConfidence {
                    detailRow("Confidence", value: "\(Int(conf * 100))%")
                    Divider()
                }
                if let domain = captureDomain {
                    detailRow("Source", value: domain)
                }
            }
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.secondary.opacity(0.12), lineWidth: 0.5))
        }
    }

    private func detailRow(_ label: String, value: String) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 90, alignment: .leading)
            Text(value)
                .font(.caption)
                .foregroundStyle(.primary)
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }

    /// A detail row that becomes an inline text field when its pencil is tapped. Committing an
    /// edit records a manual override so re-extraction won't clobber the value.
    private func editableRow(
        _ label: String,
        _ value: String,
        placeholder: String,
        commit: @escaping (String) -> Void
    ) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.caption).foregroundStyle(.secondary)
                .frame(width: 90, alignment: .leading)
            if editingField == label {
                TextField(placeholder, text: $editText)
                    .textFieldStyle(.roundedBorder).font(.caption)
                    .focused($editFocused)
                    .onSubmit { commitEdit(current: value, commit: commit) }
                    .onChange(of: editFocused) { _, focused in
                        if !focused { commitEdit(current: value, commit: commit) }
                    }
            } else {
                Text(value.isEmpty ? placeholder : value)
                    .font(.caption)
                    .foregroundStyle(value.isEmpty ? .tertiary : .primary)
                Spacer()
                Button {
                    // Commit any in-progress edit on a DIFFERENT row first, against that row's own
                    // value/commit — so the shared editText can't be written into the wrong field.
                    if editingField != nil, editingField != label, let commitActive = activeCommit {
                        commitEdit(current: activeCurrent, commit: commitActive)
                    }
                    editText = value
                    editingField = label
                    activeCurrent = value
                    activeCommit = commit
                    editFocused = true
                } label: {
                    Image(systemName: "pencil").font(.caption2)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Edit \(label.lowercased())")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }

    private func commitEdit(current: String, commit: @escaping (String) -> Void) {
        guard editingField != nil else { return }
        editingField = nil
        let trimmed = editText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed != current { commit(trimmed) }
    }

    private var captureDomain: String? {
        guard let urlStr = JobURLPolicy.displayURL(job: job),
              let url = URL(string: urlStr), let host = url.host else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    // MARK: Helpers

    private func sectionBlock(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.4)
            content()
        }
    }

    private func reqList(_ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .top, spacing: 6) {
                    Circle().fill(Color.secondary.opacity(0.4)).frame(width: 4, height: 4).padding(.top, 5)
                    Text(item).font(.caption).lineSpacing(2).textSelection(.enabled)
                }
            }
        }
    }

    private var salaryText: String {
        SalaryDisplay.text(min: job.salaryMin, max: job.salaryMax, currency: job.salaryCurrency) ?? "—"
    }

    private func fitColor(_ score: Int) -> Color {
        if score >= 85 { return Color(red: 0.34, green: 0.76, blue: 0.45) }
        if score >= 70 { return .accentColor }
        if score >= 55 { return .orange }
        return Color(red: 0.88, green: 0.45, blue: 0.44)
    }

    private func fitWord(_ score: Int) -> String {
        if score >= 85 { return "Strong fit" }
        if score >= 70 { return "Good fit" }
        if score >= 55 { return "Partial fit" }
        return "Low fit"
    }

    private func loadSkills() {
        skills = JobDetailProjection(job: job).skills
    }

    private func commitNewSkill() {
        let trimmed = newSkillText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, !skills.contains(trimmed) {
            skills.append(trimmed)
            saveSkills()
        }
        newSkillText = ""
        showAddSkill = false
    }

    private func saveSkills() {
        Task {
            do {
                guard let svc = jobService else { return }
                try await svc.updateSkills(skills, for: job.id)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - Fit Tab

struct FitTabView: View {
    @Environment(AppServices.self) private var appServices
    let job: Job

    @Environment(\.queueActor) private var queueActor
    @Query private var allResumes: [Resume]

    @State private var openResumeName: String?
    @State private var isBusy = false

    private var activeResumes: [Resume] {
        allResumes.filter(\.active)
    }

    /// Sort by score desc, highest is "best". Skip resume-less scores: an orphaned fit score
    /// (resume deleted after scoring, or a legacy score whose resume didn't survive migration)
    /// has no resume name, so it would otherwise render as the model name and hijack "Best match".
    private var sortedScores: [JobFitScore] {
        job.fitScores
            // Active résumés only — a deactivated résumé is one the user has stopped applying with, so
            // its score shouldn't be presented as their fit. Re-activating brings it straight back.
            .filter { $0.resume?.active == true }
            .sorted { ($0.fitScore ?? 0) > ($1.fitScore ?? 0) }
    }

    /// Highest *scored* resume (nil until a real score exists) — drives the hero.
    private var bestScore: JobFitScore? {
        sortedScores.first { $0.fitScore != nil }
    }

    private var scoredCount: Int {
        sortedScores.lazy.count(where: { $0.fitScore != nil })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Resumes exist but none is active → fit scoring is silently off for new jobs.
                if activeResumes.isEmpty && !allResumes.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        Text("No active résumé — new jobs won't be fit-scored. Activate one in the Resumes sidebar.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(10)
                    .background(Color.orange.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                if sortedScores.isEmpty && activeResumes.isEmpty {
                    ContentUnavailableView(
                        "No resume configured",
                        systemImage: "doc.text",
                        description: Text("Add a resume in Settings to score how well you fit this role.")
                    )
                } else {
                    // Hero
                    fitHero

                    // Per-resume accordion
                    if !sortedScores.isEmpty {
                        VStack(spacing: 6) {
                            ForEach(sortedScores) { fs in
                                ResumeScoreCard(
                                    fitScore: fs,
                                    isBest: scoredCount >= 2 && fs.fitScore != nil
                                        && fs.persistentModelID == bestScore?.persistentModelID,
                                    isPreviousVersion: fs.reflectsPreviousResumeVersion,
                                    isOpen: openResumeName == (fs.resume?.name ?? fs.model ?? ""),
                                    isRescoring: isBusy,
                                    onToggle: {
                                        let key = fs.resume?.name ?? fs.model ?? ""
                                        openResumeName = openResumeName == key ? nil : key
                                    },
                                    onRescore: {
                                        guard let resumeID = fs.resume?.id else { return }
                                        isBusy = true
                                        Task { defer { isBusy = false }
                                            do { try await queueActor?.enqueueFit(jobIDs: [job.id], resumeID: resumeID)
                                            } catch { appServices.toastStore.show(
                                                "Couldn't start fit scoring: \(error.localizedDescription)",
                                                isError: true
                                            ) }
                                        }
                                    }
                                )
                            }
                        }
                    } else {
                        // No scores yet — show score button
                        HStack {
                            Spacer()
                            Button(isBusy ? "Queuing…"
                                :
                                (activeResumes
                                    .count > 1 ? "Score against \(activeResumes.count) resumes" :
                                    "Score against resume")) {
                                isBusy = true
                                Task { defer { isBusy = false }
                                    do { try await queueActor?.enqueueFitForActiveResumes(jobIDs: [job.id]) } catch {
                                        appServices.toastStore.show(
                                            "Couldn't start fit scoring: \(error.localizedDescription)",
                                            isError: true
                                        )
                                    }
                                }
                            }
                            .disabled(isBusy || activeResumes.isEmpty)
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            Spacer()
                        }
                    }
                }
            }
            .padding(14)
        }
        .onAppear {
            // Auto-open best resume
            if openResumeName == nil, let best = bestScore {
                openResumeName = best.resume?.name ?? best.model ?? ""
            }
        }
    }

    private var fitHero: some View {
        HStack(spacing: 14) {
            if let score = bestScore?.fitScore {
                FitRingView(score: score, size: 52)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Best match · \(score)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    if let model = bestScore?.model {
                        Text(
                            "scored against \(sortedScores.count) resume\(sortedScores.count == 1 ? "" : "s") " +
                                "· \(model)"
                        )
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                }
            } else {
                Image(systemName: "sparkle")
                    .font(.title)
                    .foregroundStyle(.quaternary)
                Text("Not scored yet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Resume score card (accordion)

private struct ResumeScoreCard: View {
    let fitScore: JobFitScore
    let isBest: Bool
    /// The résumé has been edited since this score was computed — the score is real work and still
    /// shown, just labelled so it isn't mistaken for current.
    let isPreviousVersion: Bool
    let isOpen: Bool
    let isRescoring: Bool
    let onToggle: () -> Void
    let onRescore: () -> Void

    private var resumeName: String {
        let base = fitScore.resume?.name ?? fitScore.model ?? "Resume"
        return isPreviousVersion ? "\(base) (previous version)" : base
    }

    /// Cached (TASK-611). FitScoreProjection.init parses fitScoreJSON; it was rebuilt up to 4× per
    /// render (the derived vars below) across every visible résumé card. Recompute only when the score
    /// JSON changes (e.g. a re-score lands).
    @State private var fitProjection: FitScoreProjection?
    /// The requirement whose correction sheet is open, identified by text — the assessments have no
    /// stable id of their own.
    @State private var feedbackTarget: String?
    /// Which row's flag is under the cursor, so the control can brighten and name itself.
    @State private var hoveredFlag: String?

    @Environment(AppServices.self) private var appServices

    private var requirementsMet: [String] {
        fitProjection?.requirementsMet ?? []
    }

    private var requirementsNotMet: [String] {
        fitProjection?.requirementsNotMet ?? []
    }

    private var requirementAssessments: [RequirementAssessment] {
        fitProjection?.requirementAssessments ?? []
    }

    private var dimensions: [FitDimension] {
        fitProjection?.dimensions ?? []
    }

    private func assessmentColumn(_ title: String, _ items: [RequirementAssessment]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .help(Self.columnLegend)
            ForEach(items, id: \.self) { item in
                assessmentRow(item)
            }
        }
    }

    private func assessmentRow(_ item: RequirementAssessment) -> some View {
        requirementRowBody(item)
            .sheet(isPresented: Binding(
                get: { feedbackTarget == item.requirement },
                set: { if !$0 { feedbackTarget = nil } }
            )) {
                ScoringFeedbackSheet(
                    requirement: item.requirement,
                    currentStatus: item.status,
                    jobNumber: fitScore.job?.jobNumber,
                    onSave: { saveScoringFeedback($0) },
                    onCancel: { feedbackTarget = nil },
                    measureReach: { phrase, kind, jobNumber in
                        try? await appServices.jobService.scoringFeedbackMatchPreview(
                            phrase: phrase, kind: kind, jobNumber: jobNumber
                        )
                    }
                )
            }
    }

    /// Adding feedback changes gaps for every stored score, so the affected ones are recomputed
    /// immediately — no LLM call, and the number the user is looking at updates rather than going
    /// stale until something else triggers a pass.
    private func saveScoringFeedback(_ entry: ScoringFeedback) {
        feedbackTarget = nil
        appServices.settings.addScoringFeedback(entry)
        rebuildProjection()
        Task {
            do {
                let updated = try await appServices.jobService.recomputeAllFitScores()
                appServices.toastStore.show(
                    "Correction saved — \(updated) score\(updated == 1 ? "" : "s") updated"
                )
            } catch {
                appServices.toastStore.show(
                    "Correction saved, but scores couldn't be updated: \(error.localizedDescription)",
                    isError: true
                )
            }
        }
    }

    /// Rebuilt with the user's corrections applied, so the icons agree with the score they produced.
    private func rebuildProjection() {
        fitProjection = FitScoreProjection(
            fitScore: fitScore,
            feedback: appServices.settings.scoringFeedback,
            jobNumber: fitScore.job?.jobNumber
        )
    }

    private func isFlagHovered(_ item: RequirementAssessment) -> Bool {
        hoveredFlag == item.requirement
    }

    private func requirementRowBody(_ item: RequirementAssessment) -> some View {
        HStack(alignment: .top, spacing: 5) {
            Image(systemName: Self.assessmentIcon(item.status))
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Self.assessmentColor(item.status))
                .frame(width: 10)
            VStack(alignment: .leading, spacing: 1) {
                // Selectable like the rest of the detail view — these were the only text in
                // the pane you couldn't copy, and a compound requirement is exactly the thing
                // you want to quote a clause out of.
                Text(item.requirement).font(.caption2).lineSpacing(2)
                    .textSelection(.enabled)
                if !item.evidence.isEmpty {
                    Text(item.evidence)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineSpacing(1)
                        .textSelection(.enabled)
                }
            }
            Spacer(minLength: 4)
            // A visible control, not a context menu: `.textSelection(.enabled)` on the text above
            // consumes the right-click and shows the system Look Up/Copy menu instead, so a context
            // menu here never opens — and an invisible one nobody discovers is barely better.
            // Muted red at rest keeps a column of correct rows quiet while still reading as an
            // action; solid on hover confirms it's live. Tertiary grey was invisible — the control
            // was missed twice in testing, with the native right-click menu reached for instead.
            // The hint occupies permanently reserved width, so revealing it on hover doesn't reflow
            // the row — and being inline rather than a `.help()` tooltip it appears immediately,
            // without the system's hover delay.
            Text("Wrong?")
                .font(.system(size: 9))
                .foregroundStyle(.red)
                .opacity(isFlagHovered(item) ? 1 : 0)
                .frame(width: 42, alignment: .trailing)
                .accessibilityHidden(true)
            Button { feedbackTarget = item.requirement } label: {
                Image(systemName: isFlagHovered(item) ? "flag.fill" : "flag")
                    .font(.system(size: 10))
                    .foregroundStyle(isFlagHovered(item) ? Color.red : Color.red.opacity(0.45))
            }
            .buttonStyle(.borderless)
            .onHover { hoveredFlag = $0 ? item.requirement : nil }
            .help("This assessment is wrong…")
            .accessibilityLabel("Correct this assessment")
            if item.isPreferred {
                Text("Preferred")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Theme.accent.opacity(0.14)))
                    .fixedSize()
            }
        }
        // No hover tooltip: it restated the icon, the "Preferred" badge and the evidence line, all
        // three of which are already on the row — and the column header carries the icon legend. A
        // tooltip that repeats the screen just teaches people to ignore tooltips. The explanation is
        // kept for VoiceOver, where the icon and badge aren't perceivable.
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.requirement). \(item.explanation)")
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Legend for the column headings — states that the icon and the "Preferred" tag mean different
    /// things, which is the ambiguity the icons alone create.
    private static let columnLegend = """
    ✓ met · ! partially met · ✗ not met — how well your résumé matches.
    Rows tagged "Preferred" are nice-to-haves; untagged rows are required by the job.
    """

    private static func assessmentIcon(_ status: String) -> String {
        switch status {
        case "met": "checkmark"
        case "partial": "exclamationmark"
        default: "xmark" // missing
        }
    }

    private static func assessmentColor(_ status: String) -> Color {
        switch status {
        case "met": Color(red: 0.34, green: 0.76, blue: 0.45)
        case "partial": Color(red: 0.90, green: 0.62, blue: 0.0) // amber for partial evidence
        default: Color(red: 0.88, green: 0.45, blue: 0.44) // red for missing
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Card header (always visible)
            Button(action: onToggle) {
                HStack(spacing: 8) {
                    Image(systemName: isOpen ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .frame(width: 14)

                    Text(resumeName)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if isBest {
                        Text("BEST")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.accentColor)
                            .clipShape(Capsule())
                    }

                    Spacer()

                    if let score = fitScore.fitScore {
                        Text("\(score)")
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(fitColor(score))
                    } else {
                        Text(fitScore.fitStatus.rawValue)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Expanded body
            if isOpen {
                Divider()

                VStack(alignment: .leading, spacing: 14) {
                    // Per-requirement assessments (TASK-490): every job qualification is evaluated
                    // (met / partial / missing) with evidence — the same list for every resume, so
                    // gaps are consistent. Falls back to the legacy met/not-met lists for old scores.
                    if !requirementAssessments.isEmpty {
                        let met = requirementAssessments.filter(\.isMet)
                        let gaps = requirementAssessments.filter { !$0.isMet }
                        HStack(alignment: .top, spacing: 12) {
                            if !met.isEmpty {
                                assessmentColumn("Requirements met", met)
                            }
                            if !gaps.isEmpty {
                                assessmentColumn("Gaps", gaps)
                            }
                        }
                    } else if !requirementsMet.isEmpty || !requirementsNotMet.isEmpty {
                        HStack(alignment: .top, spacing: 12) {
                            if !requirementsMet.isEmpty {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Requirements met")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(Color(red: 0.34, green: 0.76, blue: 0.45))
                                    ForEach(requirementsMet, id: \.self) { req in
                                        HStack(alignment: .top, spacing: 5) {
                                            Image(systemName: "checkmark").font(.system(size: 9, weight: .bold))
                                                .foregroundStyle(Color(red: 0.34, green: 0.76, blue: 0.45))
                                            Text(req).font(.caption2).lineSpacing(2)
                                        }
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            if !requirementsNotMet.isEmpty {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Not met")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(Color(red: 0.88, green: 0.45, blue: 0.44))
                                    ForEach(requirementsNotMet, id: \.self) { req in
                                        HStack(alignment: .top, spacing: 5) {
                                            Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                                                .foregroundStyle(Color(red: 0.88, green: 0.45, blue: 0.44))
                                            Text(req).font(.caption2).lineSpacing(2)
                                        }
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }

                    // Subscore bars
                    if !dimensions.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(dimensions, id: \.name) { dim in
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack {
                                        Text(dimensionLabel(dim.name))
                                            .font(.caption2)
                                        Spacer()
                                        Text("\(dim.score)")
                                            .font(.caption2.weight(.semibold).monospacedDigit())
                                            .foregroundStyle(fitColor(dim.score))
                                    }
                                    GeometryReader { geo in
                                        ZStack(alignment: .leading) {
                                            RoundedRectangle(cornerRadius: 2)
                                                .fill(Color.secondary.opacity(0.12))
                                            RoundedRectangle(cornerRadius: 2)
                                                .fill(fitColor(dim.score))
                                                .frame(width: geo.size
                                                    .width * CGFloat(max(0, min(100, dim.score))) / 100)
                                        }
                                    }
                                    .frame(height: 4)
                                    if let rationale = dim.rationale {
                                        Text(rationale)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineSpacing(1)
                                    }
                                }
                            }
                        }
                    }

                    // Footer: model + date + re-score
                    HStack {
                        if let model = fitScore.model {
                            Text(model)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        if let at = fitScore.scoredAt {
                            Text("·").font(.caption2).foregroundStyle(.quaternary)
                            Text(at.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                        Button {
                            onRescore()
                        } label: {
                            Label("Re-score", systemImage: "arrow.clockwise")
                                .font(.caption2)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .disabled(isRescoring)
                        .help("Re-run fit scoring for this resume against the job")
                    }
                }
                .padding(12)
                .background(Color.secondary.opacity(0.04))
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.12), lineWidth: 0.5))
        .onAppear { rebuildProjection() }
        .onChange(of: fitScore.fitScoreJSON) { _, _ in rebuildProjection() }
    }

    private func fitColor(_ score: Int) -> Color {
        if score >= 85 { return Color(red: 0.34, green: 0.76, blue: 0.45) }
        if score >= 70 { return .accentColor }
        if score >= 55 { return .orange }
        return Color(red: 0.88, green: 0.45, blue: 0.44)
    }

    private func dimensionLabel(_ name: String) -> String {
        switch name {
        case "required_qualifications": return "Required Quals"
        case "preferred_qualifications": return "Preferred Quals"
        case "skills": return "Skills"
        case "experience_level": return "Experience"
        case "domain_fit": return "Domain Fit"
        default: return name.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}

// MARK: - Timeline Tab

struct TimelineTabView: View {
    let job: Job

    @Environment(\.jobService) private var jobService
    @Environment(AppServices.self) private var appServices
    @State private var noteText = ""
    @State private var showSetAction = false
    @State private var saveNoteError: String?

    /// Pending actions
    private var pendingActions: [JobAction] {
        let now = Date()
        return job.actions
            .filter { $0.completedAt == nil && (($0.snoozedUntil ?? now) <= now) }
            .sorted { $0.dueDate < $1.dueDate }
    }

    private var isSystemEvent: (JobEvent) -> Bool {
        { ["capture", "extraction", "recapture", "duplicate_detected"].contains($0.eventType) }
    }

    private var sortedEvents: [JobEvent] {
        job.events.sorted { $0.occurredAt > $1.occurredAt }
    }

    private var userEvents: [JobEvent] {
        sortedEvents.filter { !isSystemEvent($0) }
    }

    private var systemEvents: [JobEvent] {
        sortedEvents.filter { isSystemEvent($0) }
    }

    private var completedActions: [JobAction] {
        job.actions
            .filter { $0.completedAt != nil }
            .sorted { ($0.completedAt ?? $0.dueDate) > ($1.completedAt ?? $1.dueDate) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Composer
            composerSection

            Divider()

            // Timeline
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    // Pending actions at top
                    ForEach(pendingActions, id: \.id) { action in
                        PendingActionRow(action: action)
                        Divider().padding(.leading, 44)
                    }

                    // User events
                    ForEach(userEvents, id: \.id) { event in
                        TimelineEventRow(event: event)
                        Divider().padding(.leading, 44)
                    }

                    // Completed actions (history)
                    ForEach(completedActions, id: \.id) { action in
                        CompletedActionRow(action: action)
                        Divider().padding(.leading, 44)
                    }

                    // System events (capture / extraction / …) — shown inline, dimmed to keep them
                    // visually subordinate to user notes and actions.
                    ForEach(systemEvents, id: \.id) { event in
                        TimelineEventRow(event: event, isDimmed: true)
                        Divider().padding(.leading, 44)
                    }

                    if sortedEvents.isEmpty && pendingActions.isEmpty && completedActions.isEmpty {
                        ContentUnavailableView("No events yet", systemImage: "clock")
                            .padding()
                    }
                }
            }
        }
        .sheet(isPresented: $showSetAction) {
            SetNextActionSheet(job: job, followupDefaultDays: appServices.settings.followupDefaultDays)
        }
    }

    private var composerSection: some View {
        VStack(spacing: 0) {
            // Note field
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    Circle().fill(Color.accentColor.opacity(0.15)).frame(width: 24, height: 24)
                    Text("B").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.accentColor)
                }
                TextField("Add a note — ⌘↵ to save", text: $noteText, axis: .vertical)
                    .font(.caption)
                    .lineLimit(2 ... 6)
                    .textFieldStyle(.plain)
                    .onKeyPress(keys: [.return]) { press in
                        guard press.modifiers.contains(.command) else { return .ignored }
                        saveNote()
                        return .handled
                    }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 8)

            // Action row
            HStack(spacing: 8) {
                Button {
                    showSetAction = true
                } label: {
                    Label("Set next action", systemImage: "calendar.badge.plus")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Schedule a follow-up action for this job")

                Spacer()

                Text("⌘↵")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 3))

                Button("Save note") { saveNote() }
                    .disabled(noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .font(.caption)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, saveNoteError == nil ? 10 : 4)

            if let err = saveNoteError {
                Text(err).font(.caption2).foregroundStyle(.red).padding(.horizontal, 12).padding(.bottom, 8)
            }
        }
    }

    private func saveNote() {
        let text = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        saveNoteError = nil
        Task {
            do {
                try await jobService?.addNote(text, to: job.id)
                noteText = ""
            } catch {
                saveNoteError = error.localizedDescription
            }
        }
    }
}

// MARK: - Pending action row

private struct PendingActionRow: View {
    @Environment(AppServices.self) private var appServices
    let action: JobAction
    @Environment(\.jobService) private var jobService

    @State private var isEditing = false
    @State private var draft = ""

    private func completeWithUndo(actionID: String) {
        completeFollowUpWithUndo(actionID: actionID, jobService: jobService, toastStore: appServices.toastStore)
    }

    private func saveEdit() {
        let id = action.id
        let text = draft
        isEditing = false
        Task {
            do { try await jobService?.updateAction(actionID: id, text: text) } catch { appServices.toastStore.show(
                "Couldn't save follow-up: \(error.localizedDescription)",
                isError: true
            ) }
        }
    }

    private func deleteAction() {
        let id = action.id
        Task {
            do { try await jobService?.deleteAction(actionID: id) } catch { appServices.toastStore.show(
                "Couldn't delete follow-up: \(error.localizedDescription)",
                isError: true
            ) }
        }
    }

    private var dueDateLabel: String {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let due = cal.startOfDay(for: action.dueDate)
        let days = cal.dateComponents([.day], from: today, to: due).day ?? 0
        if days < 0 { return "\(-days)d overdue" }
        if days == 0 { return "Today" }
        if days == 1 { return "Tomorrow" }
        return "in \(days)d"
    }

    private var dueColor: Color {
        let today = Calendar.current.startOfDay(for: Date())
        let due = Calendar.current.startOfDay(for: action.dueDate)
        if due < today { return .red }
        if due == today { return .orange }
        return .secondary
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Color.orange.opacity(0.12)).frame(width: 24, height: 24)
                Image(systemName: "flag.fill").font(.system(size: 10)).foregroundStyle(.orange)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text("Next action")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text("·")
                        .font(.caption2)
                        .foregroundStyle(.quaternary)
                    Text(dueDateLabel)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(dueColor)
                }
                if isEditing {
                    VStack(alignment: .leading, spacing: 6) {
                        TextField("Follow-up", text: $draft, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(1 ... 4)
                            .onSubmit { saveEdit() }
                        HStack(spacing: 8) {
                            Button("Save") { saveEdit() }
                                .buttonStyle(.borderedProminent).controlSize(.small)
                            Button("Cancel") { isEditing = false }
                                .buttonStyle(.bordered).controlSize(.small)
                            Spacer()
                            Text("Clear the text to delete this follow-up.")
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                } else {
                    Text(action.note)
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .onTapGesture(count: 2) { draft = action.note; isEditing = true }
                        .contextMenu {
                            Button("Edit Follow-up", systemImage: "pencil") { draft = action.note; isEditing = true }
                            Button("Delete Follow-up", systemImage: "trash", role: .destructive, action: deleteAction)
                        }
                        .help("Double-click to edit · right-click for more")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if !isEditing {
                Button {
                    completeWithUndo(actionID: action.id)
                } label: {
                    Label("Done", systemImage: "checkmark")
                        .font(.caption2)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

// MARK: - Set next action sheet

private struct SetNextActionSheet: View {
    let job: Job
    let followupDefaultDays: Int
    @Environment(\.dismiss) private var dismiss
    @Environment(\.jobService) private var jobService

    @State private var noteText = ""
    @State private var dueDate: Date

    init(job: Job, followupDefaultDays: Int) {
        self.job = job
        self.followupDefaultDays = followupDefaultDays
        _dueDate = State(initialValue: Calendar.current
            .date(byAdding: .day, value: followupDefaultDays, to: Date()) ?? Date())
    }

    @State private var saveError: String?
    @State private var isSaving = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Set Next Action")
                .font(.headline)

            TextField("What to do (e.g. Follow up with recruiter)", text: $noteText)
                .textFieldStyle(.roundedBorder)

            // Click-driven calendar rather than a segmented field editor, which can go dead in a sheet
            // on the multi-sheet detail window (audit follow-up to the referral date fix).
            SheetDateField(label: "Due date", date: $dueDate)

            if let err = saveError {
                Text(err).font(.caption).foregroundStyle(.red)
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)
                Spacer()
                Button(isSaving ? "Saving…" : "Save") {
                    let text = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { return }
                    saveError = nil
                    isSaving = true
                    let due = dueDate
                    let id = job.id
                    Task {
                        defer { isSaving = false }
                        do {
                            try await jobService?.createAction(jobID: id, text: text, dueAt: due)
                            dismiss()
                        } catch {
                            saveError = error.localizedDescription
                        }
                    }
                }
                .disabled(noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(minWidth: 340)
    }
}

// MARK: - Timeline event row

private struct TimelineEventRow: View {
    let event: JobEvent
    var isDimmed: Bool = false

    @Environment(\.jobService) private var jobService
    @Environment(AppServices.self) private var appServices
    @State private var isEditing = false
    @State private var draft = ""

    /// Only user notes are editable; system events (capture/extraction/…) are not.
    private var isEditableNote: Bool {
        event.eventType == "note"
    }

    private var icon: String {
        switch event.eventType {
        case "capture": return "tray.and.arrow.down"
        case "note": return "note.text"
        case "status": return "tag"
        case "applied": return "paperplane"
        case "interview": return "calendar"
        case "offer": return "star"
        case "rejected": return "xmark.circle"
        case "recapture": return "arrow.clockwise"
        case "duplicate_detected": return "doc.on.doc"
        case "extraction": return "cpu"
        default: return "clock"
        }
    }

    private var iconColor: Color {
        guard !isDimmed else { return .secondary }
        switch event.eventType {
        case "applied": return .accentColor
        case "interview": return .blue
        case "offer": return .green
        case "rejected": return .red
        case "note": return .orange
        default: return .secondary
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(isDimmed ? Color.secondary.opacity(0.07) : iconColor.opacity(0.1))
                    .frame(width: 24, height: 24)
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundStyle(iconColor)
            }
            .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(event.eventType.replacingOccurrences(of: "_", with: " ").capitalized)
                        .font(.caption.weight(isDimmed ? .regular : .medium))
                        .foregroundStyle(isDimmed ? .secondary : .primary)
                    Text(event.occurredAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                if isEditing {
                    VStack(alignment: .leading, spacing: 6) {
                        TextField("Note", text: $draft, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(1 ... 6)
                            .onSubmit { saveEdit() }
                        HStack(spacing: 8) {
                            Button("Save") { saveEdit() }
                                .buttonStyle(.borderedProminent).controlSize(.small)
                            Button("Cancel") { isEditing = false }
                                .buttonStyle(.bordered).controlSize(.small)
                            Spacer()
                            Text("Clear the text to delete this note.")
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.top, 4)
                } else if let note = event.note, !note.isEmpty {
                    // Stored notes embed the raw status token ("… to pursuing"); translate for display
                    // only — DashboardMetrics.statusTarget parses the stored text.
                    Text(StatusDisplay.humanizedNote(note))
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .padding(.top, 4)
                        .padding(8)
                        .background(Color.secondary.opacity(0.07))
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                        .textSelection(.enabled)
                        .modifier(NoteEditMenu(
                            enabled: isEditableNote,
                            onEdit: { draft = note; isEditing = true },
                            onDelete: { deleteNote() }
                        ))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private func saveEdit() {
        let id = event.id
        let text = draft
        isEditing = false
        Task {
            do { try await jobService?.updateNote(eventID: id, text: text) } catch { appServices.toastStore.show(
                "Couldn't save note: \(error.localizedDescription)",
                isError: true
            ) }
        }
    }

    private func deleteNote() {
        let id = event.id
        let text = event.note ?? ""
        let occurredAt = event.occurredAt
        let createdAt = event.createdAt
        let jobID = event.job?.id
        Task {
            do {
                try await jobService?.updateNote(eventID: id, text: "")
                if let jobID, !text.isEmpty {
                    appServices.toastStore.show("Note deleted.", actionLabel: "Undo") {
                        Task {
                            try? await jobService?.restoreNote(
                                jobID: jobID, text: text, occurredAt: occurredAt, createdAt: createdAt
                            )
                        }
                    }
                }
            } catch { appServices.toastStore.show("Couldn't delete note: \(error.localizedDescription)", isError: true)
            }
        }
    }
}

/// Right-click + double-click affordances for editing/deleting a user note.
private struct NoteEditMenu: ViewModifier {
    let enabled: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void

    func body(content: Content) -> some View {
        if enabled {
            content
                .onTapGesture(count: 2, perform: onEdit)
                .contextMenu {
                    Button("Edit Note", systemImage: "pencil", action: onEdit)
                    Button("Delete Note", systemImage: "trash", role: .destructive, action: onDelete)
                }
                .help("Double-click to edit · right-click for more")
        } else {
            content
        }
    }
}

// MARK: - Completed action row (shown in timeline history)

private struct CompletedActionRow: View {
    let action: JobAction

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 16)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text("Completed")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                if let at = action.completedAt {
                    Text(at.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text(action.note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

// MARK: - Description Tab (parsed JD blocks)

struct DescriptionTabView: View {
    let job: Job

    @State private var showCleanedSource = false
    /// Parsed once per job (the description is static for a given view) instead of on every render —
    /// parseJdBlocks scans the full ~10 KB description. The view re-mounts per job (.id(job.id)).
    @State private var blocks: [JDBlock] = []

    private var cleanedBytes: Int {
        (job.capture?.cleanedDescription ?? job.capture?.visibleText ?? "").utf8.count
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if blocks.isEmpty {
                    ContentUnavailableView(
                        "No job description captured",
                        systemImage: "doc.text",
                        description: Text("Recapture this posting to see the full description.")
                    )
                } else {
                    ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                        blockView(block)
                    }

                    // Collapsible cleaned source
                    Button {
                        withAnimation { showCleanedSource.toggle() }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: showCleanedSource ? "chevron.down" : "chevron.right")
                                .font(.system(size: 9, weight: .semibold))
                            Text("Cleaned source text · \(cleanedBytes.formatted()) bytes")
                                .font(.caption)
                        }
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)

                    if showCleanedSource, let raw = job.capture?.cleanedDescription ?? job.capture?.visibleText {
                        Text(raw)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .padding(10)
                            .background(Color.secondary.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                    }
                }
            }
            .padding(14)
        }
        .onAppear { blocks = parseJdBlocks(job.capture?.cleanedDescription ?? job.capture?.visibleText) }
    }

    @ViewBuilder
    private func blockView(_ block: JDBlock) -> some View {
        switch block {
        case let .heading(text):
            Text(text).font(.caption.weight(.semibold)).padding(.top, 4)
        case let .paragraph(text):
            Text(text).font(.caption).lineSpacing(3).textSelection(.enabled)
        case let .list(items):
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 5) {
                        Text("•").font(.caption).foregroundStyle(.secondary)
                        Text(item).font(.caption).textSelection(.enabled)
                    }
                }
            }
        case .horizontalRule:
            Divider()
        }
    }
}

// MARK: - Raw Tab (diagnostics + metadata)

struct RawTabView: View {
    @Environment(AppServices.self) private var appServices
    let job: Job
    var onClose: () -> Void = {}

    @Environment(\.jobService) private var jobService

    @State private var showDeleteConfirm = false
    @State private var showArchiveConfirm = false
    @State private var showMarkUnavailableConfirm = false
    @State private var expandedHash: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Diagnostic actions
                sectionHeader("Diagnostics")

                HStack(spacing: 8) {
                    if let urlStr = JobURLPolicy.displayURL(job: job), let url = URL(string: urlStr) {
                        Link(destination: url) {
                            Label("Open source", systemImage: "arrow.up.right.square")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    Button {
                        Task {
                            do { try await jobService?.resetExtraction(jobID: job.id) } catch {
                                appServices.toastStore.show(
                                    "Couldn't re-run AI: \(error.localizedDescription)",
                                    isError: true
                                )
                            }
                        }
                    } label: {
                        Label("Re-run AI", systemImage: "arrow.clockwise")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button {
                        showMarkUnavailableConfirm = true
                    } label: {
                        Label("Mark unavailable", systemImage: "xmark.circle")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                HStack(spacing: 8) {
                    Button {
                        showArchiveConfirm = true
                    } label: {
                        Label("Archive", systemImage: "archivebox")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    if showDeleteConfirm {
                        Button("Confirm Delete", role: .destructive) {
                            let id = job.id
                            onClose()
                            Task {
                                do { try await jobService?.delete(jobID: id) } catch { appServices.toastStore.show(
                                    "Couldn't delete job: \(error.localizedDescription)",
                                    isError: true
                                ) }
                            }
                        }
                        .font(.caption)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        Button("Cancel") { showDeleteConfirm = false }
                            .font(.caption)
                            .buttonStyle(.borderless)
                            .controlSize(.small)
                    } else {
                        Button("Delete", role: .destructive) { showDeleteConfirm = true }
                            .font(.caption)
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }

                Divider()

                // Capture metadata grid
                if let capture = job.capture {
                    sectionHeader("Capture metadata")

                    VStack(alignment: .leading, spacing: 0) {
                        rawRow("Capture URL", value: capture.url)
                        Divider()
                        if let canonical = capture.canonicalURL {
                            rawRow("Canonical", value: canonical)
                            Divider()
                        }
                        rawRow("Page title", value: capture.pageTitle)
                        Divider()
                        rawRow("Captured", value: capture.capturedAt.formatted(date: .abbreviated, time: .shortened))
                        Divider()
                        if let extractedAt = job.extractedAt {
                            rawRow("Extracted", value: extractedAt.formatted(date: .abbreviated, time: .shortened))
                            Divider()
                        }
                        hashRow("Content hash", value: capture.rawHash)
                        if let cleanedHash = capture.cleanedHash {
                            Divider()
                            hashRow("Cleaned hash", value: cleanedHash)
                        }
                        if let model = job.extractionModel {
                            Divider()
                            rawRow("Model", value: model)
                        }
                        if let conf = job.extractionConfidence {
                            Divider()
                            rawRow("Confidence", value: "\(Int(conf * 100))%")
                        }
                        Divider()
                        HStack(spacing: 10) {
                            Text("Extraction")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .frame(width: 90, alignment: .leading)
                            ExtractionChip(status: job.extractionStatus)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                    }
                    .background(Color(NSColor.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 9))
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.secondary.opacity(0.12), lineWidth: 0.5))
                }

                // Raw captured text
                if let rawText = job.capture?.visibleText {
                    sectionHeader("Raw captured text · \(rawText.utf8.count.formatted()) bytes")
                    Text(rawText)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .padding(10)
                        .background(Color.secondary.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                }

                // Extraction JSON
                if let json = job.extractedJSON {
                    sectionHeader("Extracted JSON")
                    Text(prettyJSON(json) ?? json)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .padding(10)
                        .background(Color.secondary.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                }
            }
            .padding(14)
        }
        .confirmationDialog("Archive this job?", isPresented: $showArchiveConfirm, titleVisibility: .visible) {
            Button("Archive", role: .destructive) {
                Task {
                    do { try await jobService?.archive(jobID: job.id) } catch { appServices.toastStore.show(
                        "Couldn't archive job: \(error.localizedDescription)",
                        isError: true
                    ) }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The job will be moved to Archived status.")
        }
        .confirmationDialog(
            "Mark job as unavailable?",
            isPresented: $showMarkUnavailableConfirm,
            titleVisibility: .visible
        ) {
            Button("Mark Unavailable", role: .destructive) {
                Task {
                    do { try await jobService?.setStatus(.closed, for: job.id) } catch { appServices.toastStore.show(
                        "Couldn't mark unavailable: \(error.localizedDescription)",
                        isError: true
                    ) }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The job status will be changed to Closed.")
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .tracking(0.4)
    }

    private func rawRow(_ label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 90, alignment: .leading)
            Text(value)
                .font(.caption2)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .lineLimit(2)
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }

    private func hashRow(_ label: String, value: String) -> some View {
        Button {
            expandedHash = expandedHash == label ? nil : label
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(width: 90, alignment: .leading)
                HStack(spacing: 4) {
                    Image(systemName: expandedHash == label ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.tertiary)
                    Text(expandedHash == label ? value : String(value.prefix(14)) + "…")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func prettyJSON(_ json: String) -> String? {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data),
              let prettyData = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
              let str = String(data: prettyData, encoding: .utf8) else { return nil }
        return str
    }
}

// MARK: - Compare Tab

struct CompareTabView: View {
    @Environment(AppServices.self) private var appServices
    let job: Job
    @Environment(Router.self) private var router
    @Environment(\.jobService) private var jobService
    @Query private var allJobs: [Job]

    private var originalJob: Job? {
        guard let id = job.duplicateOfJobID else { return nil }
        return allJobs.first { $0.id == id }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let original = originalJob {
                    compareTable(original: original)
                    HStack(spacing: 8) {
                        Button("Unmark as Duplicate") {
                            Task {
                                do { try await jobService?.updateJobFields(jobID: job.id, duplicateOfJobID: .some(nil))
                                } catch { appServices.toastStore.show(
                                    "Couldn't unmark duplicate: \(error.localizedDescription)",
                                    isError: true
                                ) }
                            }
                        }
                        .buttonStyle(.bordered).controlSize(.small).font(.caption)
                        Button("View Original") { router.selectedJobID = original.id }
                            .buttonStyle(.borderedProminent).controlSize(.small).font(.caption)
                    }
                } else {
                    ContentUnavailableView("Original job not found", systemImage: "questionmark.square.dashed")
                }
            }
            .padding(14)
        }
    }

    private func compareTable(original: Job) -> some View {
        let rows: [(String, String, String)] = [
            ("Company", job.company ?? "—", original.company ?? "—"),
            ("Title", job.title ?? "—", original.title ?? "—"),
            ("Location", job.location ?? "—", original.location ?? "—"),
            ("Remote", job.remoteType?.displayName ?? "—", original.remoteType?.displayName ?? "—"),
            ("Status", job.status.rawValue, original.status.rawValue),
            ("Rating", job.rating.map { "\($0)" } ?? "—", original.rating.map { "\($0)" } ?? "—")
        ]

        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                Text("Field").font(.caption2).foregroundStyle(.secondary).frame(width: 80, alignment: .leading)
                Text("This").font(.caption2).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                Text("Original").font(.caption2).foregroundStyle(.secondary).frame(
                    maxWidth: .infinity,
                    alignment: .leading
                )
            }
            .padding(.horizontal, 10).padding(.vertical, 6).background(Color.secondary.opacity(0.06))
            Divider()
            ForEach(Array(rows.enumerated()), id: \.offset) { idx, row in
                let differs = row.1 != row.2
                HStack(spacing: 0) {
                    Text(row.0).font(.caption2).foregroundStyle(.secondary).frame(width: 80, alignment: .leading)
                    Text(row.1).font(.caption2).foregroundStyle(differs ? .primary : .secondary)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 4)
                        .background(differs ? Color.yellow.opacity(0.15) : Color.clear)
                    Text(row.2).font(.caption2).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 4)
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                if idx < rows.count - 1 { Divider() }
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 9))
    }
}

// MARK: - Interactive Star Rating

private struct InteractiveStarRating: View {
    let rating: Int
    let onSelect: (Int) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(1 ... 5, id: \.self) { star in
                Image(systemName: star <= rating ? "star.fill" : "star")
                    .font(.caption)
                    .foregroundStyle(star <= rating ? Color.yellow : Color.secondary.opacity(0.4))
                    .onTapGesture { onSelect(star == rating ? 0 : star) }
            }
        }
    }
}

// MARK: - Flow layout for pills

private struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width && x > 0 { y += rowHeight + spacing; x = 0; rowHeight = 0 }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds
                .minX { y += rowHeight + spacing; x = bounds.minX; rowHeight = 0 }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - RemoteType display name

extension RemoteType {
    var displayName: String {
        switch self {
        case .remote: "Remote"
        case .hybrid: "Hybrid"
        case .onsite: "On-site"
        case .unknown: "Unknown"
        }
    }
}

/// Mark a follow-up done and surface an Undo toast (TASK: review-2 #12). Shared by the
/// footer's pending-action chip and the timeline's PendingActionRow.
@MainActor
private func completeFollowUpWithUndo(actionID: String, jobService: JobService?, toastStore: ToastStore) {
    Task {
        do {
            try await jobService?.completeAction(actionID: actionID)
            toastStore.show("Follow-up marked done.", actionLabel: "Undo") {
                Task {
                    do { try await jobService?.reopenAction(actionID: actionID) } catch {
                        toastStore.show("Couldn't undo: \(error.localizedDescription)", isError: true)
                    }
                }
            }
        } catch {
            toastStore.show("Couldn't complete action: \(error.localizedDescription)", isError: true)
        }
    }
}

// swiftlint:enable file_length
