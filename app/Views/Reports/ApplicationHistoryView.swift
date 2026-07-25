import AppKit
import JobhuntCore
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

// MARK: - ApplicationHistoryView (TASK-628)

/// Lists every job that ever entered Applied — regardless of its current status — grouped by Washington
/// claim week (Sun–Sat), with a date-range filter and CSV export for unemployment job-search logs. It's
/// a recordkeeping aid, not an eligibility determination.
struct ApplicationHistoryView: View {
    @Environment(AppServices.self) private var appServices
    @Environment(Router.self) private var router

    @Query private var allJobs: [Job]
    @Query private var allEvents: [JobEvent]
    @Query private var allEvidence: [ApplicationEvidence]

    @State private var useCustomRange = false
    @State private var startDate = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
    @State private var endDate = Date()
    @State private var editing: ApplicationRecord?

    private var records: [ApplicationRecord] {
        let eventsByJob = Dictionary(grouping: allEvents) { $0.job?.id }
        let evidenceByJob = Dictionary(allEvidence.map { ($0.jobID, $0) }, uniquingKeysWith: { first, _ in first })
        let inputs: [ApplicationHistory.JobInput] = allJobs.map { job in
            let jobEvents = (eventsByJob[job.id] ?? []).map { ($0.eventType, $0.note, $0.occurredAt) }
            return ApplicationHistory.JobInput(
                jobID: job.id, jobNumber: job.jobNumber, company: job.company, title: job.title,
                sourceURL: JobURLPolicy.sourceURL(job: job) ?? "", currentStatus: job.status.rawValue,
                notes: nil, appliedAt: job.appliedAt,
                appliedEventDates: ApplicationHistory.appliedEventDates(from: jobEvents),
                evidence: evidenceByJob[job.id].map(Self.evidenceOverlay)
            )
        }
        return ApplicationHistory.build(jobs: inputs)
    }

    private static func evidenceOverlay(_ evidence: ApplicationEvidence) -> ApplicationHistory.JobInput.Evidence {
        .init(
            correctedAppliedAt: evidence.correctedAppliedAt, contactMethod: evidence.contactMethod,
            contactType: evidence.contactType, employerWebsiteOrEmail: evidence.employerWebsiteOrEmail,
            phone: evidence.phone, employerAddress: evidence.employerAddress, city: evidence.city,
            state: evidence.state, jobReferenceNumber: evidence.jobReferenceNumber,
            applicationResult: evidence.applicationResult
        )
    }

    private var filtered: [ApplicationRecord] {
        useCustomRange
            ? ApplicationHistory.filter(records, from: startDate, to: endDate)
            : records
    }

    private struct WeekGroup: Identifiable {
        let id: String
        let weekEnding: Date? // nil = the "missing application date" group
        let records: [ApplicationRecord]
    }

    private var weekGroups: [WeekGroup] {
        var byWeek: [Date: [ApplicationRecord]] = [:]
        var missing: [ApplicationRecord] = []
        for record in filtered {
            if let applied = record.appliedAt {
                byWeek[ApplicationHistory.claimWeekEnding(for: applied), default: []].append(record)
            } else {
                missing.append(record)
            }
        }
        var groups = byWeek.keys.sorted(by: >).map { week in
            WeekGroup(id: ISO8601DateFormatter().string(from: week), weekEnding: week, records: byWeek[week] ?? [])
        }
        if !missing.isEmpty { groups.append(WeekGroup(id: "missing", weekEnding: nil, records: missing)) }
        return groups
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            controls
            Divider()
            if filtered.isEmpty {
                emptyState
            } else {
                List {
                    Section { disclaimer }
                    ForEach(weekGroups) { group in
                        Section(header: weekHeader(group)) {
                            ForEach(group.records) { record in row(record) }
                        }
                    }
                }
            }
        }
        .navigationTitle("Application History")
        .accessibilityIdentifier("content.applicationHistory")
        .sheet(item: $editing) { record in
            ApplicationEvidenceEditor(record: record) { input in
                saveEvidence(input)
                editing = nil
            }
        }
    }

    private func saveEvidence(_ input: ApplicationEvidenceInput) {
        Task {
            do {
                try await appServices.backgroundStore.upsertApplicationEvidence(input)
            } catch {
                appServices.toastStore.show("Couldn't save: \(error.localizedDescription)", isError: true)
            }
        }
    }

    // MARK: - Controls

    private var controls: some View {
        HStack(spacing: 12) {
            Toggle("Custom date range", isOn: $useCustomRange)
                .toggleStyle(.switch)
                .controlSize(.small)
            if useCustomRange {
                DatePicker("From", selection: $startDate, displayedComponents: .date)
                    .labelsHidden()
                Text("–").foregroundStyle(.secondary)
                DatePicker("To", selection: $endDate, displayedComponents: .date)
                    .labelsHidden()
            } else {
                Text("All time").foregroundStyle(.secondary).font(.callout)
            }
            Spacer()
            Text("\(filtered.count) application\(filtered.count == 1 ? "" : "s")")
                .font(.callout).foregroundStyle(.secondary).monospacedDigit()
            Button {
                exportCSV()
            } label: {
                Label("Export CSV", systemImage: "square.and.arrow.up")
            }
            .disabled(filtered.isEmpty)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var disclaimer: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle").foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("A recordkeeping aid — not an eligibility determination.")
                    .font(.caption.weight(.medium))
                Text("This lists jobs you marked Applied in JobHunt. It may not include all approved "
                    + "job-search activities, and it doesn't decide whether a week meets requirements — "
                    + "Washington ESD makes that determination.")
                    .font(.caption).foregroundStyle(.secondary)
                Link(
                    "Washington ESD job-search requirements",
                    destination: URL(string:
                        "https://esd.wa.gov/get-financial-help/unemployment-benefits/weekly-unemployment-claims/job-search-requirements")
                        ?? URL(fileURLWithPath: "/")
                )
                .font(.caption)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Rows

    private func weekHeader(_ group: WeekGroup) -> some View {
        HStack {
            if let week = group.weekEnding {
                Text("Claim week ending \(week.formatted(date: .abbreviated, time: .omitted))")
            } else {
                Label("Missing application date", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
            Spacer()
            Text("\(group.records.count) application\(group.records.count == 1 ? "" : "s")")
                .foregroundStyle(.secondary)
        }
        .font(.caption)
    }

    private func row(_ record: ApplicationRecord) -> some View {
        HStack(spacing: 8) {
            Button {
                router.selectedJobID = record.jobID
            } label: {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(record.company ?? "Unknown company")
                            .font(.subheadline.weight(.medium)).lineLimit(1)
                        Text(record.jobTitle ?? "Untitled").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        if !record.missingEvidenceFields.isEmpty {
                            Text("Add: \(record.missingEvidenceFields.joined(separator: ", "))")
                                .font(.caption2).foregroundStyle(.orange).lineLimit(1)
                        } else if record.sourceURL.isEmpty {
                            Text("No source URL on this job").font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 3) {
                        if let applied = record.appliedAt {
                            Text(applied.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption.monospacedDigit())
                        } else {
                            Text("date needed").font(.caption2).foregroundStyle(.orange)
                        }
                        if let number = record.jobNumber {
                            Text("#\(number)").font(.caption2.monospacedDigit()).foregroundStyle(.tertiary)
                        }
                    }
                    if let status = JobStatus(rawValue: record.currentStatus) {
                        StatusChip(status: status)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button { editing = record } label: {
                Image(systemName: "square.and.pencil")
            }
            .buttonStyle(.borderless)
            .help("Add or correct application evidence (contact method, date, result, …)")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "list.bullet.rectangle").font(.largeTitle).foregroundStyle(.tertiary)
            Text(useCustomRange ? "No applications in this date range." : "No applications recorded yet.")
                .foregroundStyle(.secondary)
            Text("Jobs appear here once you mark them Applied.")
                .font(.caption).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Export

    private func exportCSV() {
        let csv = ExportService.applicationHistoryCSV(records: filtered)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "application-history.csv"
        guard panel.runModal() == .OK, let url = panel.url else { return } // cancelled → no file (AC #14)
        do {
            try ExportService.write(csv, to: url)
            appServices.toastStore.show("Exported \(filtered.count) application\(filtered.count == 1 ? "" : "s")")
        } catch {
            appServices.toastStore.show("Export failed: \(error.localizedDescription)", isError: true)
        }
    }
}

// MARK: - ApplicationEvidenceEditor (TASK-628 phase 2)

/// Sheet to record/correct the ESD employer-contact evidence for one applied job — including a date
/// correction for legacy missing-date rows. Nothing is inferred; blank fields stay empty on save.
private struct ApplicationEvidenceEditor: View {
    let record: ApplicationRecord
    let onSave: (ApplicationEvidenceInput) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var overrideDate: Bool
    @State private var appliedDate: Date
    @State private var contactMethod: String
    @State private var contactType: String
    @State private var website: String
    @State private var phone: String
    @State private var address: String
    @State private var city: String
    @State private var stateField: String
    @State private var jobRef: String
    @State private var result: String

    init(record: ApplicationRecord, onSave: @escaping (ApplicationEvidenceInput) -> Void) {
        self.record = record
        self.onSave = onSave
        _overrideDate = State(initialValue: record.appliedAt == nil) // missing-date rows default to entering one
        _appliedDate = State(initialValue: record.appliedAt ?? Date())
        _contactMethod = State(initialValue: record.contactMethod ?? "")
        _contactType = State(initialValue: record.contactType ?? "")
        _website = State(initialValue: record.employerWebsiteOrEmail ?? "")
        _phone = State(initialValue: record.phone ?? "")
        _address = State(initialValue: record.employerAddress ?? "")
        _city = State(initialValue: record.city ?? "")
        _stateField = State(initialValue: record.state ?? "")
        _jobRef = State(initialValue: record.jobReferenceNumber ?? "")
        _result = State(initialValue: record.applicationResult ?? "")
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Application evidence").font(.headline)
                    Text("\(record.company ?? "Unknown") — \(record.jobTitle ?? "Untitled")")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
            }
            .padding()
            Divider()
            Form {
                Section("Application date") {
                    Toggle("Set or correct the application date", isOn: $overrideDate)
                    if overrideDate {
                        // Click-driven calendar — a segmented date field in a sheet can lose keyboard
                        // first-responder and become uneditable (audit follow-up to the referral fix).
                        SheetDateField(label: "Date", date: $appliedDate)
                    }
                }
                Section("Employer contact (for the ESD log)") {
                    field("Contact method", "online, email, in person…", $contactMethod)
                    field("Contact type", "application, résumé, inquiry…", $contactType)
                    field("Website or email", "", $website)
                    field("Phone", "", $phone)
                    field("Address", "", $address)
                    field("City", "", $city)
                    field("State", "", $stateField)
                    field("Job reference #", "", $jobRef)
                    field("Result", "applied, interview, no response…", $result)
                }
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 460, height: 580)
    }

    private func field(_ label: String, _ prompt: String, _ text: Binding<String>) -> some View {
        TextField(label, text: text, prompt: prompt.isEmpty ? nil : Text(prompt))
    }

    private func save() {
        onSave(ApplicationEvidenceInput(
            jobID: record.jobID,
            correctedAppliedAt: overrideDate ? appliedDate : nil,
            contactMethod: contactMethod, contactType: contactType, employerWebsiteOrEmail: website,
            phone: phone, employerAddress: address, city: city, state: stateField,
            jobReferenceNumber: jobRef, applicationResult: result
        ))
    }
}
