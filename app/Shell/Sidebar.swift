import SwiftUI
import JobhuntCore

struct Sidebar: View {
    var router: Router
    var theme: Theme

    // Quick-filter status options shown as pills
    private let quickFilters: [(label: String, value: String?)] = [
        ("All", nil),
        ("Saved", JobStatus.saved.rawValue),
        ("Applied", JobStatus.applied.rawValue),
        ("Interview", JobStatus.interview.rawValue),
        ("Offer", JobStatus.offer.rawValue)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Main navigation list
            List(SidebarSection.allCases, id: \.self, selection: Binding(
                get: { router.selectedSection },
                set: { if let section = $0 { router.navigateToSection(section) } }
            )) { section in
                Label(section.title, systemImage: section.systemImage)
                    .tag(section)
            }
            .listStyle(.sidebar)

            Divider()

            // Quick-filter pills
            VStack(alignment: .leading, spacing: 6) {
                Text("Filter")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.top, 10)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(quickFilters, id: \.label) { filter in
                            Button {
                                router.statusFilter = filter.value
                                router.selectedSection = .jobs
                            } label: {
                                Text(filter.label)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(
                                        router.statusFilter == filter.value
                                            ? Theme.accent
                                            : Color.secondary.opacity(0.12)
                                    )
                                    .foregroundStyle(
                                        router.statusFilter == filter.value
                                            ? .white
                                            : .primary
                                    )
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.bottom, 10)
            }

            Divider()

            // Footer: theme toggle
            HStack {
                ForEach(Theme.ColorSchemePreference.allCases, id: \.self) { pref in
                    Button {
                        theme.colorSchemePreference = pref
                    } label: {
                        Image(systemName: pref.systemImage)
                            .font(.caption)
                            .frame(width: 28, height: 28)
                            .background(
                                theme.colorSchemePreference == pref
                                    ? Color.secondary.opacity(0.2)
                                    : Color.clear
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .help(pref.label)
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .navigationTitle("Jobhunt")
    }
}

#Preview {
    NavigationSplitView {
        Sidebar(router: Router(), theme: Theme())
    } content: {
        Text("Content")
    } detail: {
        Text("Detail")
    }
}
