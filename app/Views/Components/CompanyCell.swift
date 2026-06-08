import SwiftUI

struct CompanyCell: View {
    let company: String?
    let title: String?

    private var monogram: String {
        let source = company ?? title ?? "?"
        return String(source.first ?? "?").uppercased()
    }

    private var avatarColor: Color {
        let source = company ?? title ?? ""
        let hash = source.unicodeScalars.reduce(0) { $0 + $1.value }
        let colors: [Color] = [
            .blue, .purple, .green, .orange, .pink, .teal, .indigo, .mint
        ]
        return colors[Int(hash) % colors.count]
    }

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(avatarColor.opacity(0.2))
                    .frame(width: 32, height: 32)
                Text(monogram)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(avatarColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                if let company {
                    Text(company)
                        .font(.body)
                        .fontWeight(.medium)
                        .lineLimit(1)
                }
                if let title {
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }
}

#Preview {
    VStack(spacing: 12) {
        CompanyCell(company: "Apple", title: "Senior Engineer")
        CompanyCell(company: "Google", title: "Staff SWE")
        CompanyCell(company: nil, title: "Software Engineer")
    }
    .padding()
}
