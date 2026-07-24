import JobhuntCore
import SwiftData
import SwiftUI

struct SiteDetailView: View {
    let site: Site
    let siteService: SiteService

    @Environment(Router.self) private var router

    @State private var intervalDaysText: String
    @State private var noteText: String
    @State private var companyWebsiteText: String
    @State private var jobsURLText: String
    @State private var showDeleteConfirmation = false
    @State private var errorMessage: String?
    @FocusState private var intervalFieldFocused: Bool

    init(site: Site, siteService: SiteService) {
        self.site = site
        self.siteService = siteService
        _intervalDaysText = State(initialValue: String(site.intervalDays))
        _noteText = State(initialValue: site.note)
        _companyWebsiteText = State(initialValue: site.companyWebsite ?? "")
        _jobsURLText = State(initialValue: site.jobsURL ?? "")
    }

    private var displayName: String {
        if let name = site.companyName, !name.isEmpty { return name }
        if !site.pageTitle.isEmpty { return site.pageTitle }
        return site.origin
    }

    private var visitURL: URL? {
        // Only ever hand a web link to NSWorkspace.open — never a file:// or custom-scheme URL that a
        // forged site-review could have stored before ingestion validation (F16).
        guard let url = URL(string: site.jobsURL ?? site.url),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return nil }
        return url
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Header
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(displayName)
                            .font(.title3.weight(.semibold))
                            .lineLimit(2)

                        if let url = URL(string: site.url) {
                            Link(site.origin, destination: url)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text(site.origin)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    reviewStatusChip
                }
                .padding(16)

                Divider()

                // Fields
                VStack(alignment: .leading, spacing: 0) {
                    siteField(label: "State") {
                        Picker("State", selection: Binding(
                            get: { site.state },
                            set: { setSiteState($0) }
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

                    siteField(label: "Check every") {
                        HStack(spacing: 4) {
                            TextField("14", text: $intervalDaysText)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 56)
                                .focused($intervalFieldFocused)
                                .onSubmit { saveIntervalDays() }
                                .onChange(of: intervalFieldFocused) { _, focused in
                                    if !focused { saveIntervalDays() }
                                }
                            Text("days")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Divider().padding(.leading, 16)

                    siteField(label: "Last reviewed") {
                        if let last = site.lastReviewedAt {
                            Text(last, style: .date)
                                .font(.callout)
                                .foregroundStyle(.primary)
                        } else {
                            Text("Never")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Divider().padding(.leading, 16)

                    siteField(label: "Next review") {
                        if let next = site.nextReviewAt {
                            nextReviewLabel(next)
                        } else {
                            Text("—").font(.callout).foregroundStyle(.secondary)
                        }
                    }

                    Divider().padding(.leading, 16)

                    siteField(label: "Added") {
                        Text(site.addedAt, style: .date)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }

                    Divider().padding(.leading, 16)

                    siteField(label: "Jobs URL") {
                        TextField("https://…/careers", text: $jobsURLText)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { saveSiteFields() }
                    }

                    Divider().padding(.leading, 16)

                    siteField(label: "Company site") {
                        TextField("https://…", text: $companyWebsiteText)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { saveSiteFields() }
                    }

                    Divider().padding(.leading, 16)

                    siteField(label: "Note") {
                        TextField("Add a note…", text: $noteText, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(1 ... 4)
                            .onSubmit { saveSiteFields() }
                    }
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                }
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button(action: markReviewed) {
                    Label("Mark Reviewed", systemImage: "checkmark.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .help("Mark this site as reviewed today")

                if let url = visitURL {
                    Button { NSWorkspace.shared.open(url) } label: {
                        Label("Visit Site", systemImage: "arrow.up.right.square")
                    }
                    .buttonStyle(.bordered)
                    .help("Open jobs page in browser")
                }

                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                }
                .help("Delete this site")
                .confirmationDialog(
                    "Delete \(displayName)?",
                    isPresented: $showDeleteConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Delete", role: .destructive) { deleteSite() }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This action cannot be undone.")
                }
            }
        }
        .onChange(of: site.id) { _, _ in
            intervalDaysText = String(site.intervalDays)
            noteText = site.note
            companyWebsiteText = site.companyWebsite ?? ""
            jobsURLText = site.jobsURL ?? ""
            errorMessage = nil
        }
    }

    private func saveSiteFields() {
        let id = site.id
        let note = noteText
        let website = companyWebsiteText.trimmingCharacters(in: .whitespaces)
        let jobs = jobsURLText.trimmingCharacters(in: .whitespaces)
        Task {
            do {
                try await siteService.updateSite(id: id, note: note, companyWebsite: website, jobsURL: jobs)
            } catch {
                errorMessage = "Save failed: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Review status chip (top-right of header)

    @ViewBuilder
    private var reviewStatusChip: some View {
        if let next = site.nextReviewAt {
            let days = Calendar.current.dateComponents([.day], from: Date(), to: next).day ?? 0
            if days < 0 {
                Label("Overdue \(-days)d", systemImage: "exclamationmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.red)
                    .clipShape(Capsule())
            } else if days == 0 {
                Label("Due today", systemImage: "clock.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.orange)
                    .clipShape(Capsule())
            } else if days <= 7 {
                Label("Due in \(days)d", systemImage: "clock")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.orange.opacity(0.12))
                    .clipShape(Capsule())
            } else {
                Label("Due \(next, style: .date)", systemImage: "checkmark.circle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.green.opacity(0.1))
                    .clipShape(Capsule())
            }
        }
    }

    // MARK: - Next review inline label

    @ViewBuilder
    private func nextReviewLabel(_ date: Date) -> some View {
        let days = Calendar.current.dateComponents([.day], from: Date(), to: date).day ?? 0
        if days < 0 {
            Text("Overdue by \(-days) days")
                .font(.callout)
                .foregroundStyle(.red)
        } else if days == 0 {
            Text("Today")
                .font(.callout)
                .foregroundStyle(.orange)
        } else {
            Text(date, style: .date)
                .font(.callout)
                .foregroundStyle(days <= 7 ? .orange : .primary)
        }
    }

    // MARK: - Field row

    private func siteField(label: String, @ViewBuilder content: () -> some View) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 100, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Actions

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
            errorMessage = "Enter a positive number of days"
            return
        }
        errorMessage = nil
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
                await MainActor.run { router.selectedSiteID = nil }
            } catch {
                await MainActor.run { errorMessage = error.localizedDescription }
            }
        }
    }
}
