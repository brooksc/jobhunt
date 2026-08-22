import JobhuntCore
import SwiftUI

/// Maps a fit band to its colour. The thresholds live in Core (`FitBand`) so the colour and the
/// spoken label can't drift apart — they were three separate copies before (TASK-506 #4).
extension FitBand {
    var color: Color {
        switch self {
        case .strong: Color(red: 0.34, green: 0.76, blue: 0.45)
        case .good: .accentColor
        case .partial: .orange
        case .low: Color(red: 0.88, green: 0.45, blue: 0.44)
        }
    }
}

// MARK: - FitRingView

/// Circular progress ring showing a 0–100 fit score.
struct FitRingView: View {
    let score: Int
    var size: CGFloat = 32

    var color: Color {
        FitBand.band(for: score).color
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.15), lineWidth: ringWidth)
            Circle()
                .trim(from: 0, to: CGFloat(score) / 100)
                .stroke(color, style: StrokeStyle(lineWidth: ringWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(score)")
                .font(.system(size: size * 0.31, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .monospacedDigit()
        }
        .frame(width: size, height: size)
        .animation(.easeInOut(duration: 0.3), value: score)
        // #1: the number alone means nothing without the scale; the band alone loses 55-vs-69.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(FitBand.accessibilityLabel(score: score))
    }

    private var ringWidth: CGFloat {
        size * 0.088
    }
}

// MARK: - CompanyMarkView

/// Letter-badge for a company name (2 initials).
struct CompanyMarkView: View {
    let name: String?
    var size: CGFloat = 22

    private var initials: String {
        guard let name, !name.isEmpty else { return "?" }
        let words = name.split(separator: " ")
        if words.count >= 2 {
            return String(words[0].prefix(1) + words[1].prefix(1)).uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.26)
                .fill(Color.secondary.opacity(0.13))
            Text(initials)
                .font(.system(size: size * 0.40, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.secondary)
        }
        .frame(width: size, height: size)
    }
}

#Preview("FitRingView") {
    HStack(spacing: 16) {
        FitRingView(score: 92, size: 48)
        FitRingView(score: 74, size: 48)
        FitRingView(score: 57, size: 48)
        FitRingView(score: 32, size: 48)
    }
    .padding()
}
