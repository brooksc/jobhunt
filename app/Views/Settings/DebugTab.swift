import JobhuntCore
import SwiftData
import SwiftUI

struct DebugTab: View {
    @Query private var jobs: [Job]
    @Query private var captures: [Capture]
    @Query private var resumes: [Resume]
    @Query private var sites: [Site]

    var body: some View {
        Form {
            jobStatsSection
            entityCountsSection
        }
        .formStyle(.grouped)
    }

    // MARK: - Job stats by status

    private var jobStatsSection: some View {
        Section("Jobs by Status") {
            ForEach(JobStatus.allCases, id: \.self) { status in
                let count = jobs.filter { $0.status == status }.count
                LabeledContent(status.rawValue.capitalized) {
                    Text("\(count)")
                        .foregroundStyle(count > 0 ? .primary : .tertiary)
                        .monospacedDigit()
                }
            }
            LabeledContent("Total") {
                Text("\(jobs.count)")
                    .fontWeight(.semibold)
                    .monospacedDigit()
            }
        }
    }

    // MARK: - Entity counts

    private var entityCountsSection: some View {
        Section("Database") {
            LabeledContent("Captures") {
                Text("\(captures.count)").foregroundStyle(.secondary).monospacedDigit()
            }
            LabeledContent("Resumes") {
                Text("\(resumes.count)").foregroundStyle(.secondary).monospacedDigit()
            }
            LabeledContent("Sites") {
                Text("\(sites.count)").foregroundStyle(.secondary).monospacedDigit()
            }
            LabeledContent("Extraction pending") {
                let pending = jobs.filter { $0.extractionStatus == .pending }.count
                Text("\(pending)").foregroundStyle(.secondary).monospacedDigit()
            }
            LabeledContent("Extraction failed") {
                let failed = jobs.filter { $0.extractionStatus == .failed }.count
                Text("\(failed)")
                    .foregroundStyle(failed > 0 ? .red : .secondary)
                    .monospacedDigit()
            }
        }
    }
}
