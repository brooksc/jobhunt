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

    @State private var useCustomRange = false
    @State private var startDate = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
    @State private var endDate = Date()

    private var records: [ApplicationRecord] {
        let eventsByJob = Dictionary(grouping: allEvents) { $0.job?.id }
        let inputs: [ApplicationHistory.JobInput] = allJobs.map { job in
            let jobEvents = (eventsByJob[job.id] ?? []).map { ($0.eventType, $0.note, $0.occurredAt) }
            return ApplicationHistory.JobInput(
                jobID: job.id, jobNumber: job.jobNumber, company: job.company, title: job.title,
                sourceURL: JobURLPolicy.sourceURL(job: job) ?? "", currentStatus: job.status.rawValue,
                notes: nil, appliedAt: job.appliedAt,
                appliedEventDates: ApplicationHistory.appliedEventDates(from: jobEvents)
            )
        }
        return ApplicationHistory.build(jobs: inputs)
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
                Link("Washington ESD job-search requirements",
                     destination: URL(string:
                        "https://esd.wa.gov/get-financial-help/unemployment-benefits/weekly-unemployment-claims/job-search-requirements")
                        ?? URL(fileURLWithPath: "/"))
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
        Button {
            router.selectedJobID = record.jobID
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(record.company ?? "Unknown company")
                        .font(.subheadline.weight(.medium)).lineLimit(1)
                    Text(record.jobTitle ?? "Untitled").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    if record.sourceURL.isEmpty {
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
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
