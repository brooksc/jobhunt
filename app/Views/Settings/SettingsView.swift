import JobhuntCore
import SwiftUI

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var settings: SettingsStore?

    var body: some View {
        Group {
            if let settings {
                SettingsTabView(settings: settings)
            } else {
                ProgressView("Loading settings…")
                    .onAppear {
                        settings = SettingsStore(modelContext: modelContext)
                    }
            }
        }
        .onAppear {
            if settings == nil {
                settings = SettingsStore(modelContext: modelContext)
            }
        }
    }
}

private struct SettingsTabView: View {
    let settings: SettingsStore

    var body: some View {
        TabView {
            SettingsTab(settings: settings)
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
                .tag(0)

            ResumesTab(settings: settings)
                .tabItem {
                    Label("Resumes", systemImage: "doc.text")
                }
                .tag(1)

            DebugTab(settings: settings)
                .tabItem {
                    Label("Debug", systemImage: "ant")
                }
                .tag(2)
        }
        .padding()
    }
}
