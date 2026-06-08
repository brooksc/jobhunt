import JobhuntCore
import SwiftData
import SwiftUI

struct SiteDetailView: View {
    let site: Site
    let siteService: SiteService

    @State private var intervalDaysText: String
    @State private var showDeleteConfirmation = false
    @State private var errorMessage: String?

    init(site: Site, siteService: SiteService) {
        self.site = site
        self.siteService = siteService
        _intervalDaysText = State(initialValue: String(site.intervalDays))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Header
                VStack(alignment: .leading, spacing: 6) {
                    Text(site.companyName ?? (site.pageTitle.isEmpty ? site.origin : site.pageTitle))
                        .font(.title3)
                        .fontWeight(.semibold)
                        .lineLimit(2)

                    Text(site.origin)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 12)

                Divider()

                // Fields
                VStack(alignment: .leading, spacing: 0) {
                    siteField(label: "URL") {
                        Text(site.url)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    Divider().padding(.leading, 16)

                    siteField(label: "State") {
                        Picker("State", selection: Binding(
                            get: { site.state },
                            set: { newState in
                                setSiteState(newState)
                            }
                        )) {
                            Text("Not Reviewed").tag(SiteState.notReviewed)
                            Text("Reviewed").tag(SiteState.reviewed)
                            Text("Exclude").tag(SiteState.exclude)
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .fixedSize()
                    }

                    Divider().padding(.leading, 16)

                    siteField(label: "Interval (days)") {
                        TextField("14", text: $intervalDaysText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                            .onSubmit { saveIntervalDays() }
                    }

                    Divider().padding(.leading, 16)

                    siteField(label: "Last Reviewed") {
                        if let lastReviewed = site.lastReviewedAt {
                            Text(lastReviewed, style: .date)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Never")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Divider().padding(.leading, 16)

                    siteField(label: "Next Review") {
                        if let nextReview = site.nextReviewAt {
                            nextReviewText(nextReview)
                        } else {
                            Text("—")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Divider().padding(.leading, 16)

                    siteField(label: "Added") {
                        Text(site.addedAt, style: .date)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                }

                Divider().padding(.top, 8)

                // Actions
                VStack(spacing: 8) {
                    Button {
                        markReviewed()
                    } label: {
                        Label("Mark Reviewed", systemImage: "checkmark.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    if let jobsURL = site.jobsURL, let url = URL(string: jobsURL) {
                        Button {
                            NSWorkspace.shared.open(url)
                        } label: {
                            Label("Visit Jobs URL", systemImage: "arrow.up.right.square")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    } else if let url = URL(string: site.url) {
                        Button {
                            NSWorkspace.shared.open(url)
                        } label: {
                            Label("Visit Site", systemImage: "arrow.up.right.square")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }

                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Label("Delete Site", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .confirmationDialog(
                        "Delete \(site.companyName ?? site.origin)?",
                        isPresented: $showDeleteConfirmation,
                        titleVisibility: .visible
                    ) {
                        Button("Delete", role: .destructive) {
                            deleteSite()
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("This action cannot be undone.")
                    }
                }
                .padding(16)
            }
        }
        .onChange(of: site.id) { _, _ in
            intervalDaysText = String(site.intervalDays)
            errorMessage = nil
        }
    }

    @ViewBuilder
    private func nextReviewText(_ date: Date) -> some View {
        let now = Date()
        let diff = Calendar.current.dateComponents([.day], from: now, to: date).day ?? 0
        if diff < 0 {
            Text("Overdue by \(-diff)d")
                .font(.caption)
                .foregroundStyle(.red)
        } else if diff == 0 {
            Text("Today")
                .font(.caption)
                .foregroundStyle(.orange)
        } else {
            Text(date, style: .date)
                .font(.caption)
                .foregroundStyle(diff <= 7 ? .orange : .secondary)
        }
    }

    private func siteField(label: String, @ViewBuilder content: () -> some View) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func setSiteState(_ state: SiteState) {
        let id = site.id
        Task {
            do {
                try await siteService.setSiteState(siteID: id, state: state)
            } catch {
                await MainActor.run { errorMessage = error.localizedDescription }
            }
        }
    }

    private func markReviewed() {
        let id = site.id
        Task {
            do {
                try await siteService.markReviewed(siteID: id)
            } catch {
                await MainActor.run { errorMessage = error.localizedDescription }
            }
        }
    }

    private func saveIntervalDays() {
        guard let days = Int(intervalDaysText), days > 0 else {
            intervalDaysText = String(site.intervalDays)
            return
        }
        let id = site.id
        Task {
            do {
                try await siteService.updateSite(id: id, name: nil, excludeState: nil, intervalDays: days)
            } catch {
                await MainActor.run { errorMessage = error.localizedDescription }
            }
        }
    }

    private func deleteSite() {
        let id = site.id
        Task {
            do {
                try await siteService.deleteSite(id: id)
            } catch {
                await MainActor.run { errorMessage = error.localizedDescription }
            }
        }
    }
}
