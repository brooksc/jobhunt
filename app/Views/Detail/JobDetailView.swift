// swiftlint:disable file_length type_body_length
import SwiftUI
import SwiftData
import JobhuntCore

// MARK: - JobDetailView

struct JobDetailView: View {
    let job: Job

    @Environment(Router.self) private var router
    @Environment(\.jobService) private var jobService
    @Environment(\.queueActor) private var queueActor
    @Environment(\.modelContext) private var modelContext

    @State private var selectedTab: DetailTab = .details

    enum DetailTab: String, CaseIterable {
        case details = "Details"
        case extracted = "Extracted"
        case fit = "Fit"
        case summary = "Summary"
        case requirements = "Requirements"
        case timeline = "Timeline"
        case raw = "Raw"
        case compare = "Compare"
    }

    private var visibleTabs: [DetailTab] {
        var tabs: [DetailTab] = [.details, .extracted, .fit, .summary, .requirements, .timeline, .raw]
        if job.duplicateOfJobID != nil {
            tabs.append(.compare)
        }
        return tabs
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            JobDetailHeader(job: job)

            Divider()

            // Tab bar
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(visibleTabs, id: \.self) { tab in
                        Button(tab.rawValue) {
                            selectedTab = tab
                        }
                        .buttonStyle(TabButtonStyle(isSelected: selectedTab == tab))
                    }
                }
                .padding(.horizontal, 8)
            }
            .frame(height: 36)

            Divider()

            // Body
            Group {
                switch selectedTab {
                case .details:
                    DetailsTabView(job: job)
                case .extracted:
                    ExtractedTabView(job: job)
                case .fit:
                    FitTabView(job: job)
                case .summary:
                    SummaryTabView(job: job)
                case .requirements:
                    RequirementsTabView(job: job)
                case .timeline:
                    TimelineTabView(job: job)
                case .raw:
                    RawTabView(job: job)
                case .compare:
                    CompareTabView(job: job)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onKeyPress(.leftArrow) {
            router.selectedJobID = nil  // handled by list selection — post notification
            NotificationCenter.default.post(name: .navigatePreviousJob, object: nil)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            NotificationCenter.default.post(name: .navigateNextJob, object: nil)
            return .handled
        }
        .onKeyPress(.escape) {
            router.selectedJobID = nil
            return .handled
        }
    }
}

// MARK: - Notification names

extension Notification.Name {
    static let navigatePreviousJob = Notification.Name("JobDetail.navigatePreviousJob")
    static let navigateNextJob = Notification.Name("JobDetail.navigateNextJob")
}

// MARK: - Tab button style

private struct TabButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption)
            .fontWeight(isSelected ? .semibold : .regular)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundStyle(isSelected ? Theme.accent : Color.secondary)
            .background(isSelected ? Theme.accent.opacity(0.1) : Color.clear)
            .cornerRadius(6)
    }
}

// MARK: - Header

private struct JobDetailHeader: View {
    let job: Job

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let jobNumber = job.jobNumber {
                Text("#\(jobNumber)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(job.title ?? "Untitled")
                .font(.headline)
                .lineLimit(2)
            if let company = job.company {
                Text(company)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                StatusChip(status: job.status)
                if let rating = job.rating, rating > 0 {
                    StarRating(rating: rating)
                }
                Spacer()
                if let url = job.applicationURL, let parsedURL = URL(string: url) {
                    Link(destination: parsedURL) {
                        Image(systemName: "arrow.up.right.square")
                            .font(.caption)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

// MARK: - Details Tab

struct DetailsTabView: View {
    let job: Job

    @Environment(\.jobService) private var jobService
    @Environment(Router.self) private var router

    @State private var editingCompany = false
    @State private var editingTitle = false
    @State private var editingLocation = false
    @State private var editingURL = false
    @State private var editingSalaryMin = false
    @State private var editingSalaryMax = false

    @State private var draftCompany = ""
    @State private var draftTitle = ""
    @State private var draftLocation = ""
    @State private var draftURL = ""
    @State private var draftSalaryMin = ""
    @State private var draftSalaryMax = ""

    @State private var noteText = ""
    @State private var showDeleteConfirm = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Core fields
                VStack(alignment: .leading, spacing: 0) {
                    detailRow("Company") {
                        EditableTextField(
                            value: job.company ?? "",
                            isEditing: $editingCompany,
                            draft: $draftCompany,
                            placeholder: "—"
                        ) { newValue in
                            commitField { svc in
                                let v: String? = newValue.isEmpty ? nil : newValue
                                try await svc.updateJobFields(jobID: job.id, company: .some(v))
                            }
                        }
                    }
                    Divider()
                    detailRow("Title") {
                        EditableTextField(
                            value: job.title ?? "",
                            isEditing: $editingTitle,
                            draft: $draftTitle,
                            placeholder: "—"
                        ) { newValue in
                            commitField { svc in
                                let v: String? = newValue.isEmpty ? nil : newValue
                                try await svc.updateJobFields(jobID: job.id, title: .some(v))
                            }
                        }
                    }
                    Divider()
                    detailRow("Location") {
                        EditableTextField(
                            value: job.location ?? "",
                            isEditing: $editingLocation,
                            draft: $draftLocation,
                            placeholder: "—"
                        ) { newValue in
                            commitField { svc in
                                let v: String? = newValue.isEmpty ? nil : newValue
                                try await svc.updateJobFields(jobID: job.id, location: .some(v))
                            }
                        }
                    }
                    Divider()
                    detailRow("Remote") {
                        Picker("Remote", selection: remoteTypeBinding) {
                            Text("Unknown").tag(RemoteType?.none)
                            ForEach(RemoteType.allCases, id: \.self) { rt in
                                Text(rt.displayName).tag(Optional(rt))
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .font(.caption)
                    }
                    Divider()
                    detailRow("Employment") {
                        Text(job.employmentType ?? "—")
                            .font(.caption)
                            .foregroundStyle(job.employmentType == nil ? .tertiary : .primary)
                    }
                    Divider()
                    detailRow("Seniority") {
                        Text(job.seniority ?? "—")
                            .font(.caption)
                            .foregroundStyle(job.seniority == nil ? .tertiary : .primary)
                    }
                    Divider()
                    detailRow("Salary") {
                        Text(salaryText)
                            .font(.caption)
                            .foregroundStyle(job.salaryMin == nil && job.salaryMax == nil ? .tertiary : .primary)
                    }
                    Divider()
                    detailRow("Apply URL") {
                        EditableTextField(
                            value: job.applicationURL ?? "",
                            isEditing: $editingURL,
                            draft: $draftURL,
                            placeholder: "—"
                        ) { newValue in
                            commitField { svc in
                                let v: String? = newValue.isEmpty ? nil : newValue
                                try await svc.updateJobFields(jobID: job.id, applicationURL: .some(v))
                            }
                        }
                    }
                }
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)

                // Status picker
                VStack(alignment: .leading, spacing: 6) {
                    Text("Status")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("Status", selection: statusBinding) {
                        ForEach(JobStatus.allCases, id: \.self) { status in
                            StatusChip(status: status)
                                .tag(status)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }

                // Rating
                VStack(alignment: .leading, spacing: 6) {
                    Text("Rating")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    InteractiveStarRating(rating: job.rating ?? 0) { newRating in
                        Task {
                            guard let svc = jobService else { return }
                            try? await svc.setRating(newRating == 0 ? nil : newRating, for: job.id)
                        }
                    }
                }

                // Add note
                VStack(alignment: .leading, spacing: 6) {
                    Text("Add Note")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $noteText)
                        .font(.caption)
                        .frame(minHeight: 60)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3), lineWidth: 1))
                    Button("Save Note") {
                        guard !noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                        let text = noteText
                        noteText = ""
                        Task {
                            guard let svc = jobService else { return }
                            try? await svc.addNote(text, to: job.id)
                        }
                    }
                    .disabled(noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .font(.caption)
                }

                if let errMsg = errorMessage {
                    Text(errMsg)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                // Archive / Delete
                HStack(spacing: 8) {
                    Button("Archive") {
                        Task {
                            guard let svc = jobService else { return }
                            try? await svc.archive(jobID: job.id)
                        }
                    }
                    .buttonStyle(.bordered)
                    .font(.caption)

                    if showDeleteConfirm {
                        Button("Confirm Delete", role: .destructive) {
                            let id = job.id
                            router.selectedJobID = nil
                            Task {
                                guard let svc = jobService else { return }
                                try? await svc.delete(jobID: id)
                            }
                        }
                        .buttonStyle(.bordered)
                        .font(.caption)
                        Button("Cancel") {
                            showDeleteConfirm = false
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)
                    } else {
                        Button("Delete", role: .destructive) {
                            showDeleteConfirm = true
                        }
                        .buttonStyle(.bordered)
                        .font(.caption)
                    }
                }
            }
            .padding(12)
        }
    }

    private var salaryText: String {
        var parts: [String] = []
        let currency = job.salaryCurrency ?? "USD"
        if let min = job.salaryMin { parts.append("\(currency) \(min.formatted())") }
        if let max = job.salaryMax { parts.append(parts.isEmpty ? "\(currency) \(max.formatted())" : max.formatted()) }
        if let note = job.salaryNote, !note.isEmpty { parts.append("(\(note))") }
        return parts.isEmpty ? "—" : parts.joined(separator: " – ")
    }

    private var statusBinding: Binding<JobStatus> {
        Binding(
            get: { job.status },
            set: { newStatus in
                Task {
                    guard let svc = jobService else { return }
                    try? await svc.setStatus(newStatus, for: job.id)
                }
            }
        )
    }

    private var remoteTypeBinding: Binding<RemoteType?> {
        Binding(
            get: { job.remoteType },
            set: { newRemote in
                Task {
                    guard let svc = jobService else { return }
                    try? await svc.updateJobFields(jobID: job.id, remoteType: .some(newRemote))
                }
            }
        )
    }

    private func commitField(_ block: @escaping (JobService) async throws -> Void) {
        Task {
            guard let svc = jobService else { return }
            do {
                try await block(svc)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    @ViewBuilder
    private func detailRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)
            content()
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }
}

// MARK: - Extracted Tab

struct ExtractedTabView: View {
    let job: Job

    @Environment(\.jobService) private var jobService
    @Environment(\.queueActor) private var queueActor

    private var extractedFields: [(String, String)] {
        guard let json = job.extractedJSON,
              let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }
        return dict.sorted { $0.key < $1.key }.map { (key, value) in
            let strValue: String
            if let str = value as? String { strValue = str }
            else if let num = value as? NSNumber { strValue = num.stringValue }
            else if let arr = value as? [Any] {
                strValue = arr.compactMap { $0 as? String }.joined(separator: ", ")
            } else { strValue = String(describing: value) }
            return (key, strValue)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // Confidence badge
                HStack(spacing: 8) {
                    ExtractionChip(status: job.extractionStatus)
                    if let confidence = job.extractionConfidence {
                        Text("\(Int(confidence * 100))% confidence")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Re-extract") {
                        Task {
                            guard let svc = jobService else { return }
                            try? await svc.resetExtraction(jobID: job.id)
                        }
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                }

                if extractedFields.isEmpty {
                    Text("No extracted data available.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(extractedFields.enumerated()), id: \.offset) { idx, pair in
                            HStack(alignment: .top, spacing: 8) {
                                Text(pair.0)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 130, alignment: .leading)
                                Text(pair.1.isEmpty ? "—" : pair.1)
                                    .font(.caption)
                                    .textSelection(.enabled)
                                Spacer()
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            if idx < extractedFields.count - 1 {
                                Divider()
                            }
                        }
                    }
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                }
            }
            .padding(12)
        }
    }
}

// MARK: - Fit Tab

struct FitTabView: View {
    let job: Job

    @Environment(\.queueActor) private var queueActor
    @Query private var resumes: [Resume]

    @State private var isBusy = false

    private var activeResumes: [Resume] {
        resumes.filter(\.active)
    }

    private var fitDimensions: [(name: String, score: Int, rationale: String?)] {
        guard let json = job.fitScoreJSON,
              let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dims = dict["dimensions"] as? [[String: Any]] else { return [] }
        return dims.compactMap { d in
            guard let name = d["name"] as? String,
                  let score = d["score"] as? Int else { return nil }
            let rationale = d["rationale"] as? String
            return (name: name, score: score, rationale: rationale)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if activeResumes.isEmpty && job.fitScores.isEmpty {
                    Text("Add a resume in Settings to score how well you fit this job.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    // Overall score
                    HStack(spacing: 12) {
                        VStack(alignment: .leading) {
                            Text("Fit Score")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let score = job.fitScore {
                                Text("\(score)")
                                    .font(.title)
                                    .fontWeight(.bold)
                                    .foregroundStyle(fitColor(score))
                            } else {
                                Text("—")
                                    .font(.title)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button(isBusy ? "Queuing…" : "Run Fit Score") {
                            guard !isBusy else { return }
                            isBusy = true
                            Task {
                                defer { isBusy = false }
                                guard let queue = queueActor,
                                      let resume = activeResumes.first else { return }
                                try? await queue.enqueue(jobIDs: [job.id], mode: .fit)
                                _ = resume
                            }
                        }
                        .disabled(isBusy || activeResumes.isEmpty)
                        .buttonStyle(.bordered)
                        .font(.caption)
                    }

                    // Dimensions
                    if !fitDimensions.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Breakdown")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            ForEach(fitDimensions, id: \.name) { dim in
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack {
                                        Text(dimensionLabel(dim.name))
                                            .font(.caption)
                                        Spacer()
                                        Text("\(dim.score)")
                                            .font(.caption)
                                            .fontWeight(.semibold)
                                            .foregroundStyle(fitColor(dim.score))
                                    }
                                    GeometryReader { geo in
                                        ZStack(alignment: .leading) {
                                            RoundedRectangle(cornerRadius: 2)
                                                .fill(Color.secondary.opacity(0.2))
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
                                    }
                                }
                            }
                        }
                    }

                    // Per-resume fit scores
                    if !job.fitScores.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Per Resume")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            ForEach(job.fitScores.sorted { ($0.fitScore ?? 0) > ($1.fitScore ?? 0) }, id: \.self) { fitScore in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(fitScore.model ?? "Unknown model")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                        if let scoredAt = fitScore.scoredAt {
                                            Text(scoredAt.formatted(date: .abbreviated, time: .shortened))
                                                .font(.caption2)
                                                .foregroundStyle(.tertiary)
                                        }
                                    }
                                    Spacer()
                                    if let score = fitScore.fitScore {
                                        Text("\(score)")
                                            .font(.caption)
                                            .fontWeight(.bold)
                                            .foregroundStyle(fitColor(score))
                                    } else {
                                        Text(fitScore.fitStatus.rawValue)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(8)
                                .background(Color(NSColor.controlBackgroundColor))
                                .cornerRadius(6)
                            }
                        }
                    }
                }
            }
            .padding(12)
        }
    }

    private func fitColor(_ score: Int) -> Color {
        if score >= 75 { return .green }
        if score >= 50 { return .orange }
        return .red
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

// MARK: - Summary Tab

struct SummaryTabView: View {
    let job: Job

    private var summaryText: String? {
        guard let json = job.extractedJSON,
              let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let summary = dict["summary"] as? String,
              !summary.isEmpty else { return nil }
        return String(summary.prefix(500))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if let text = summaryText {
                    Text(text)
                        .font(.caption)
                        .lineSpacing(4)
                        .textSelection(.enabled)
                } else {
                    Text("No summary available.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
        }
    }
}

// MARK: - Requirements Tab

struct RequirementsTabView: View {
    let job: Job

    private var requirements: [String] {
        guard let json = job.extractedJSON,
              let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let reqs = dict["requirements"] as? [String] else { return [] }
        return reqs
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if requirements.isEmpty {
                    Text("No requirements extracted.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(requirements.enumerated()), id: \.offset) { _, req in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "circle.fill")
                                .font(.system(size: 4))
                                .foregroundStyle(.secondary)
                                .padding(.top, 5)
                            Text(req)
                                .font(.caption)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
            .padding(12)
        }
    }
}

// MARK: - Timeline Tab

struct TimelineTabView: View {
    let job: Job

    @Environment(\.jobService) private var jobService

    @State private var noteText = ""

    private var sortedEvents: [JobEvent] {
        job.events.sorted { $0.occurredAt < $1.occurredAt }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Note entry
            VStack(alignment: .leading, spacing: 6) {
                TextEditor(text: $noteText)
                    .font(.caption)
                    .frame(height: 70)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3), lineWidth: 1))
                HStack {
                    Spacer()
                    Button("Add Note") {
                        guard !noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                        let text = noteText
                        noteText = ""
                        Task {
                            guard let svc = jobService else { return }
                            try? await svc.addNote(text, to: job.id)
                        }
                    }
                    .disabled(noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .buttonStyle(.bordered)
                    .font(.caption)
                }
            }
            .padding(12)

            Divider()

            // Event list
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if sortedEvents.isEmpty {
                        Text("No events yet.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(12)
                    } else {
                        ForEach(sortedEvents, id: \.id) { event in
                            TimelineEventRow(event: event)
                            Divider()
                        }
                    }
                }
            }
        }
    }
}

private struct TimelineEventRow: View {
    let event: JobEvent

    private var icon: String {
        switch event.eventType {
        case "capture": return "tray.and.arrow.down"
        case "note": return "note.text"
        case "status": return "tag"
        case "applied": return "paperplane"
        case "interview": return "calendar"
        case "offer": return "star"
        case "rejected": return "xmark.circle"
        default: return "clock"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 16)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.eventType.replacingOccurrences(of: "_", with: " ").capitalized)
                    .font(.caption)
                    .fontWeight(.medium)
                Text(event.occurredAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if let note = event.note, !note.isEmpty {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .padding(.top, 2)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

// MARK: - Raw Tab

struct RawTabView: View {
    let job: Job

    private var rawText: String {
        job.capture?.visibleText ?? job.capture?.cleanedDescription ?? "No raw text available."
    }

    private var blocks: [JDBlock] {
        parseJdBlocks(job.capture?.cleanedDescription ?? job.capture?.visibleText)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                // Capture metadata
                VStack(alignment: .leading, spacing: 0) {
                    rawMetaRow("URL", value: job.capture?.url ?? "—")
                    Divider()
                    rawMetaRow("Page Title", value: job.capture?.pageTitle ?? "—")
                    Divider()
                    rawMetaRow("Canonical URL", value: job.capture?.canonicalURL ?? "—")
                    Divider()
                    if let capturedAt = job.capture?.capturedAt {
                        rawMetaRow("Captured", value: capturedAt.formatted(date: .abbreviated, time: .shortened))
                        Divider()
                    }
                    rawMetaRow("Raw Hash", value: job.capture?.rawHash.prefix(16).description ?? "—")
                }
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)

                // Rendered blocks if available
                if !blocks.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Parsed Content")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                            blockView(block)
                        }
                    }
                } else {
                    // Fallback: show raw text
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Raw Text")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(rawText)
                            .font(.caption)
                            .textSelection(.enabled)
                    }
                }
            }
            .padding(12)
        }
    }

    @ViewBuilder
    private func blockView(_ block: JDBlock) -> some View {
        switch block {
        case .heading(let text):
            Text(text)
                .font(.caption)
                .fontWeight(.semibold)
                .padding(.top, 6)
        case .paragraph(let text):
            Text(text)
                .font(.caption)
                .lineSpacing(3)
                .textSelection(.enabled)
        case .list(let items):
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 4) {
                        Text("•")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(item)
                            .font(.caption)
                            .textSelection(.enabled)
                    }
                }
            }
        case .horizontalRule:
            Divider()
        }
    }

    @ViewBuilder
    private func rawMetaRow(_ label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 90, alignment: .leading)
            Text(value)
                .font(.caption2)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
    }
}

// MARK: - Compare Tab

struct CompareTabView: View {
    let job: Job

    @Environment(Router.self) private var router
    @Environment(\.jobService) private var jobService
    @Query private var allJobs: [Job]

    private var originalJob: Job? {
        guard let origID = job.duplicateOfJobID else { return nil }
        return allJobs.first { $0.id == origID }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let original = originalJob {
                    compareTable(original: original)

                    HStack(spacing: 8) {
                        Button("Unmark as Duplicate") {
                            Task {
                                guard let svc = jobService else { return }
                                try? await svc.updateJobFields(jobID: job.id, duplicateOfJobID: .some(nil))
                                try? await svc.setStatus(.saved, for: job.id)
                            }
                        }
                        .buttonStyle(.bordered)
                        .font(.caption)

                        Button("View Original") {
                            router.selectedJobID = original.id
                        }
                        .buttonStyle(.borderedProminent)
                        .font(.caption)
                    }
                } else {
                    Text("Original job not found or was deleted.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
        }
    }

    @ViewBuilder
    private func compareTable(original: Job) -> some View {
        let rows: [(String, String, String)] = [
            ("Company", job.company ?? "—", original.company ?? "—"),
            ("Title", job.title ?? "—", original.title ?? "—"),
            ("Location", job.location ?? "—", original.location ?? "—"),
            ("Remote", job.remoteType?.displayName ?? "—", original.remoteType?.displayName ?? "—"),
            ("Status", job.status.rawValue, original.status.rawValue),
            ("Rating", job.rating.map { "\($0)" } ?? "—", original.rating.map { "\($0)" } ?? "—"),
        ]

        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 0) {
                Text("Field")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(width: 80, alignment: .leading)
                Text("This job (duplicate)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Original")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            ForEach(Array(rows.enumerated()), id: \.offset) { idx, row in
                let differs = row.1 != row.2
                HStack(spacing: 0) {
                    Text(row.0)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: 80, alignment: .leading)
                    Text(row.1)
                        .font(.caption2)
                        .foregroundStyle(differs ? .primary : .secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                        .background(differs ? Color.yellow.opacity(0.15) : Color.clear)
                    Text(row.2)
                        .font(.caption2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)

                if idx < rows.count - 1 {
                    Divider()
                }
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}

// MARK: - Interactive Star Rating

private struct InteractiveStarRating: View {
    let rating: Int
    let onSelect: (Int) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(1...5, id: \.self) { star in
                Image(systemName: star <= rating ? "star.fill" : "star")
                    .font(.caption)
                    .foregroundStyle(star <= rating ? Color.yellow : Color.secondary.opacity(0.4))
                    .onTapGesture {
                        onSelect(star == rating ? 0 : star)
                    }
            }
        }
    }
}

// MARK: - Editable text field

private struct EditableTextField: View {
    let value: String
    @Binding var isEditing: Bool
    @Binding var draft: String
    let placeholder: String
    let onCommit: (String) -> Void

    var body: some View {
        if isEditing {
            TextField("", text: $draft)
                .font(.caption)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed != value {
                        onCommit(trimmed)
                    }
                    isEditing = false
                }
                .onKeyPress(.escape) {
                    isEditing = false
                    return .handled
                }
        } else {
            Text(value.isEmpty ? placeholder : value)
                .font(.caption)
                .foregroundStyle(value.isEmpty ? .tertiary : .primary)
                .onTapGesture {
                    draft = value
                    isEditing = true
                }
        }
    }
}

// MARK: - RemoteType display

extension RemoteType {
    var displayName: String {
        switch self {
        case .remote: return "Remote"
        case .hybrid: return "Hybrid"
        case .onsite: return "On-site"
        case .unknown: return "Unknown"
        }
    }
}

// swiftlint:enable file_length type_body_length
