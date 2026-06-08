import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationSplitView {
            List {
                Label("Jobs", systemImage: "briefcase")
                Label("Dashboard", systemImage: "chart.bar")
                Label("Sites", systemImage: "globe")
                Label("Duplicates", systemImage: "doc.on.doc")
                Label("LLM Queue", systemImage: "cpu")
                Label("Data Quality", systemImage: "checkmark.shield")
                Label("Needs Action", systemImage: "bell")
            }
            .navigationTitle("Jobhunt")
        } content: {
            Text("Select an item")
                .foregroundStyle(.secondary)
        } detail: {
            Text("Select a job to view details")
                .foregroundStyle(.secondary)
        }
    }
}
