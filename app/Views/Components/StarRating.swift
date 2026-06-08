import SwiftUI

struct StarRating: View {
    let rating: Int?

    var body: some View {
        HStack(spacing: 2) {
            ForEach(1 ... 5, id: \.self) { star in
                Image(systemName: starSymbol(for: star))
                    .font(.caption)
                    .foregroundStyle(starColor(for: star))
            }
        }
    }

    private func starSymbol(for star: Int) -> String {
        guard let rating else { return "star" }
        return star <= rating ? "star.fill" : "star"
    }

    private func starColor(for star: Int) -> Color {
        guard let rating, star <= rating else {
            return Color.secondary.opacity(0.4)
        }
        return .yellow
    }
}

#Preview {
    VStack(spacing: 8) {
        StarRating(rating: nil)
        StarRating(rating: 1)
        StarRating(rating: 3)
        StarRating(rating: 5)
    }
    .padding()
}
