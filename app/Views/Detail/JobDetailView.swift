import JobhuntCore
import SwiftData

// swiftlint:disable file_length
import SwiftUI

// MARK: - JobDetailView

struct JobDetailView: View {
    let job: Job
    var onNavigatePrev: () -> Void = {}
    var onNavigateNext: () -> Void = {}

    @Environment(Router.self) private var router
    @Environment(\.jobService) private var jobService
    @Environment(\.queueActor) private var queueActor
    @Environment(\.modelContext) private var modelContext

    @State private var selectedTab: DetailTab = .overview

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
            DetailHeader(job: job, selectedTab: $selectedTab, onNavigatePrev: onNavigatePrev, onNavigateNext: onNavigateNext)
            Divider()
            // HIG-5: system segmented Picker replaces hand-rolled tab bar
            Picker("Tab", selection: $selectedTab) {
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
        .onKeyPress(.escape) { router.selectedJobID = nil; return .handled }
    }

    @ViewBuilder
    private var tabBody: some View {
        switch selectedTab {
        case .overview:    OverviewTabView(job: job, goFit: { selectedTab = .fit })
        case .fit:         FitTabView(job: job)
        case .timeline:    TimelineTabView(job: job)
        case .description: DescriptionTabView(job: job)
        case .raw:         RawTabView(job: job)
        case .compare:     CompareTabView(job: job)
        }
    }
}

// MARK: - Header

private struct DetailHeader: View {
    let job: Job
    @Binding var selectedTab: JobDetailView.DetailTab
    let onNavigatePrev: () -> Void
    let onNavigateNext: () -> Void
    @Environment(\.jobService) private var jobService
    @State private var showNoteSheet = false
    @State private var quickNoteText = ""

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
                    Button { router.selectedJobID = nil } label: {
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
                Text(job.title ?? "Untitled")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 4)

            // Row 3: meta chips
            HStack(spacing: 6) {
                if let loc = job.location { metaChip(loc) }
                if let remote = job.remoteType, remote != .unknown { metaChip(remote.displayName) }
                if let sal = salaryText { metaChip(sal).font(.caption.monospacedDigit()) }
                if let emp = job.employmentType { metaChip(emp) }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.bottom, 8)

            // Row 4: action bar
            HStack(spacing: 6) {
                StatusPickerButton(job: job)

                Divider().frame(height: 16).padding(.horizontal, 2)

                if let urlStr = job.capture?.url ?? job.applicationURL, let url = URL(string: urlStr) {
                    Link(destination: url) {
                        Label("Source", systemImage: "arrow.up.right.square")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Open source posting")
                }

                Button {
                    Task { try? await jobService?.resetExtraction(jobID: job.id) }
                } label: {
                    Label("Re-run", systemImage: "arrow.clockwise")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Re-run AI extraction")

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
        }
    }

    @Environment(Router.self) private var router

    private var captureDomain: String? {
        guard let urlStr = job.capture?.url ?? job.applicationURL,
              let url = URL(string: urlStr),
              let host = url.host else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    private var salaryText: String? {
        let sym: String
        switch job.salaryCurrency ?? "USD" {
        case "GBP": sym = "£"
        case "EUR": sym = "€"
        default: sym = "$"
        }
        let k: (Int) -> String = { v in v >= 1000 ? "\(v / 1000)k" : "\(v)" }
        if let min = job.salaryMin, let max = job.salaryMax { return "\(sym)\(k(min))–\(k(max))" }
        if let min = job.salaryMin { return "\(sym)\(k(min))+" }
        if let max = job.salaryMax { return "up to \(sym)\(k(max))" }
        return nil
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
                        Task { try? await jobService?.setStatus(s, for: job.id) }
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

    private var pendingAction: JobAction? {
        let now = Date()
        return job.actions
            .filter { $0.completedAt == nil && ($0.snoozedUntil == nil || $0.snoozedUntil! <= now) }
            .sorted { $0.dueDate < $1.dueDate }
            .first
    }

    var body: some View {
        HStack(spacing: 10) {
            // Capture date note
            if let cap = job.capture?.capturedAt {
                Text("\(job.status.displayName) · captured \(relativeCaptured(cap))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            if let action = pendingAction {
                HStack(spacing: 6) {
                    Image(systemName: "flag.fill").font(.caption2).foregroundStyle(.orange)
                    Text(action.note).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    Button {
                        let id = action.id
                        Task { try? await jobService?.completeAction(actionID: id) }
                    } label: { Image(systemName: "checkmark").font(.caption2) }
                    .buttonStyle(.bordered).controlSize(.mini)
                }
            }
            if job.status == .pursuing, let urlStr = job.applicationURL ?? job.capture?.url, let url = URL(string: urlStr) {
                Link("Apply", destination: url)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .font(.caption.weight(.semibold))
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

struct OverviewTabView: View {
    let job: Job
    let goFit: () -> Void

    @Environment(\.jobService) private var jobService
    @Environment(Router.self) private var router

    @State private var skills: [String] = []
    @State private var newSkillText = ""
    @State private var showAddSkill = false
    @State private var showDeleteConfirm = false
    @State private var errorMessage: String?

    private var extractedDict: [String: Any]? {
        guard let json = job.extractedJSON,
              let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return dict
    }

    private var summary: String? { extractedDict?["summary"] as? String }
    private var requirements: [String] { (extractedDict?["requirements"] as? [String]) ?? [] }
    private var niceToHaves: [String] {
        (extractedDict?["nice_to_have"] as? [String])
        ?? (extractedDict?["nice_to_haves"] as? [String]) ?? []
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Decision strip
                decisionStrip
                Divider()

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
        .onAppear { loadSkills() }
    }

    // MARK: Decision strip

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
                    } else {
                        Image(systemName: "sparkle")
                            .font(.title2)
                            .foregroundStyle(.quaternary)
                            .frame(width: 48, height: 48)
                        Text("Not scored")
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
                    Task { try? await jobService?.setRating(newVal == 0 ? nil : newVal, for: job.id) }
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

            VStack(alignment: .leading, spacing: 0) {
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

    private var captureDomain: String? {
        guard let urlStr = job.capture?.url ?? job.applicationURL,
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
        let sym: String
        switch job.salaryCurrency ?? "USD" {
        case "GBP": sym = "£"
        case "EUR": sym = "€"
        default: sym = "$"
        }
        let k: (Int) -> String = { v in v >= 1000 ? "\(v / 1000)k" : "\(v)" }
        if let min = job.salaryMin, let max = job.salaryMax { return "\(sym)\(k(min))–\(k(max))" }
        if let min = job.salaryMin { return "\(sym)\(k(min))+" }
        if let max = job.salaryMax { return "up to \(sym)\(k(max))" }
        return "—"
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
        let json = job.manualOverridesJSON
        if let data = json.data(using: .utf8),
           let arr = try? JSONSerialization.jsonObject(with: data) as? [String] {
            skills = arr
        } else if let extracted = extractedDict?["skills"] as? [String] {
            skills = extracted
        }
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
    let job: Job

    @Environment(\.queueActor) private var queueActor
    @Query private var allResumes: [Resume]

    @State private var openResumeName: String? = nil
    @State private var isBusy = false
    @State private var tailorAlertShowing = false

    private var activeResumes: [Resume] { allResumes.filter(\.active) }

    // Sort by score desc, highest is "best"
    private var sortedScores: [JobFitScore] {
        job.fitScores.sorted { ($0.fitScore ?? 0) > ($1.fitScore ?? 0) }
    }

    private var bestScore: JobFitScore? { sortedScores.first }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
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
                                    isBest: fs.persistentModelID == bestScore?.persistentModelID,
                                    isOpen: openResumeName == (fs.resume?.name ?? fs.model ?? ""),
                                    isRescoring: isBusy,
                                    onToggle: {
                                        let key = fs.resume?.name ?? fs.model ?? ""
                                        openResumeName = openResumeName == key ? nil : key
                                    },
                                    onRescore: {
                                        isBusy = true
                                        Task { defer { isBusy = false }
                                            try? await queueActor?.enqueue(jobIDs: [job.id], mode: .fit)
                                        }
                                    }
                                )
                            }
                        }

                        // Tailor resume button
                        Button {
                            tailorAlertShowing = true
                        } label: {
                            Label("Tailor resume to this role", systemImage: "sparkle")
                                .font(.caption)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .padding(.top, 4)
                    } else {
                        // No scores yet — show score button
                        HStack {
                            Spacer()
                            Button(isBusy ? "Queuing…" : "Score against resume") {
                                guard !activeResumes.isEmpty else { return }
                                isBusy = true
                                Task { defer { isBusy = false }
                                    try? await queueActor?.enqueue(jobIDs: [job.id], mode: .fit)
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
        .alert("Not Yet Available", isPresented: $tailorAlertShowing) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Tailored resume generation is coming in a future update.")
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
                        Text("scored against \(sortedScores.count) resume\(sortedScores.count == 1 ? "" : "s") · \(model)")
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
    let isOpen: Bool
    let isRescoring: Bool
    let onToggle: () -> Void
    let onRescore: () -> Void

    private var resumeName: String { fitScore.resume?.name ?? fitScore.model ?? "Resume" }

    private var fitDict: [String: Any]? {
        guard let json = fitScore.fitScoreJSON,
              let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return dict
    }

    private var requirementsMet: [String] { (fitDict?["requirements_met"] as? [String]) ?? [] }
    private var requirementsNotMet: [String] { (fitDict?["requirements_not_met"] as? [String]) ?? [] }
    private var dimensions: [(name: String, score: Int, rationale: String?)] {
        guard let dims = fitDict?["dimensions"] as? [[String: Any]] else { return [] }
        return dims.compactMap { d in
            guard let name = d["name"] as? String, let score = d["score"] as? Int else { return nil }
            return (name: name, score: score, rationale: d["rationale"] as? String)
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
                    // Met / Not Met two-column
                    if !requirementsMet.isEmpty || !requirementsNotMet.isEmpty {
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
                                                .frame(width: geo.size.width * CGFloat(max(0, min(100, dim.score))) / 100)
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
    @State private var noteText = ""
    @State private var showSetAction = false
    @State private var showSystemEvents = false

    // Pending actions
    private var pendingActions: [JobAction] {
        let now = Date()
        return job.actions
            .filter { $0.completedAt == nil && ($0.snoozedUntil == nil || $0.snoozedUntil! <= now) }
            .sorted { $0.dueDate < $1.dueDate }
    }

    private var isSystemEvent: (JobEvent) -> Bool {
        { ["capture", "extraction", "recapture"].contains($0.eventType) }
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

                    // System events toggle
                    if !systemEvents.isEmpty {
                        Button {
                            withAnimation { showSystemEvents.toggle() }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: showSystemEvents ? "chevron.down" : "chevron.right")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(.tertiary)
                                Image(systemName: "gear")
                                    .font(.caption2)
                                    .foregroundStyle(.quaternary)
                                Text("\(systemEvents.count) system event\(systemEvents.count == 1 ? "" : "s")")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                if !showSystemEvents {
                                    Text("· show")
                                        .font(.caption2)
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)

                        if showSystemEvents {
                            ForEach(systemEvents, id: \.id) { event in
                                TimelineEventRow(event: event, isDimmed: true)
                                Divider().padding(.leading, 44)
                            }
                        }
                    }

                    if userEvents.isEmpty && pendingActions.isEmpty {
                        ContentUnavailableView("No events yet", systemImage: "clock")
                            .padding()
                    }
                }
            }
        }
        .sheet(isPresented: $showSetAction) {
            SetNextActionSheet(job: job)
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
                    .lineLimit(2...6)
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
            .padding(.bottom, 10)
        }
    }

    private func saveNote() {
        let text = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        noteText = ""
        Task { try? await jobService?.addNote(text, to: job.id) }
    }
}

// MARK: - Pending action row

private struct PendingActionRow: View {
    let action: JobAction
    @Environment(\.jobService) private var jobService

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
                Text(action.note)
                    .font(.caption)
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                let id = action.id
                Task { try? await jobService?.completeAction(actionID: id) }
            } label: {
                Label("Done", systemImage: "checkmark")
                    .font(.caption2)
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

// MARK: - Set next action sheet

private struct SetNextActionSheet: View {
    let job: Job
    @Environment(\.dismiss) private var dismiss
    @Environment(\.jobService) private var jobService

    @State private var noteText = ""
    @State private var dueDate = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Set Next Action")
                .font(.headline)

            TextField("What to do (e.g. Follow up with recruiter)", text: $noteText)
                .textFieldStyle(.roundedBorder)

            DatePicker("Due date", selection: $dueDate, displayedComponents: .date)
                .datePickerStyle(.compact)

            HStack {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)
                Spacer()
                Button("Save") {
                    let text = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { return }
                    let due = dueDate
                    let id = job.id
                    Task {
                        try? await jobService?.createAction(jobID: id, text: text, dueAt: due)
                        dismiss()
                    }
                }
                .disabled(noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
                if let note = event.note, !note.isEmpty {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .padding(.top, 4)
                        .padding(8)
                        .background(Color.secondary.opacity(0.07))
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

// MARK: - Description Tab (parsed JD blocks)

struct DescriptionTabView: View {
    let job: Job

    @State private var showCleanedSource = false

    private var blocks: [JDBlock] {
        parseJdBlocks(job.capture?.cleanedDescription ?? job.capture?.visibleText)
    }

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
    let job: Job

    @Environment(\.jobService) private var jobService
    @Environment(Router.self) private var router

    @State private var showDeleteConfirm = false
    @State private var showArchiveConfirm = false
    @State private var showMarkUnavailableConfirm = false
    @State private var expandedHash: String? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Diagnostic actions
                sectionHeader("Diagnostics")

                HStack(spacing: 8) {
                    if let urlStr = job.capture?.url ?? job.applicationURL, let url = URL(string: urlStr) {
                        Link(destination: url) {
                            Label("Open source", systemImage: "arrow.up.right.square")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    Button {
                        Task { try? await jobService?.resetExtraction(jobID: job.id) }
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
                            router.selectedJobID = nil
                            Task { try? await jobService?.delete(jobID: id) }
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
                Task { try? await jobService?.archive(jobID: job.id) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The job will be moved to Archived status.")
        }
        .confirmationDialog("Mark job as unavailable?", isPresented: $showMarkUnavailableConfirm, titleVisibility: .visible) {
            Button("Mark Unavailable", role: .destructive) {
                Task { try? await jobService?.setStatus(.closed, for: job.id) }
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
                                try? await jobService?.updateJobFields(jobID: job.id, duplicateOfJobID: .some(nil))
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
            ("Rating", job.rating.map { "\($0)" } ?? "—", original.rating.map { "\($0)" } ?? "—"),
        ]

        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                Text("Field").font(.caption2).foregroundStyle(.secondary).frame(width: 80, alignment: .leading)
                Text("This").font(.caption2).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                Text("Original").font(.caption2).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
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

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
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

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX { y += rowHeight + spacing; x = bounds.minX; rowHeight = 0 }
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


// swiftlint:enable file_length
