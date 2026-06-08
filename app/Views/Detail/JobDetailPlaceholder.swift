import SwiftUI

struct JobDetailPlaceholder: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "briefcase")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("No job selected")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Select a job from the list to view details.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    JobDetailPlaceholder()
}
