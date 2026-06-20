// JDParser.swift — port of static/jd-parser.js
// Pure Foundation only — no SwiftUI/AppKit/SwiftData imports.
// swiftlint:disable line_length
import Foundation

// MARK: - Types

public enum JDBlock: Equatable {
    case heading(text: String)
    case paragraph(text: String)
    case list(items: [String])
    case horizontalRule
}

// MARK: - Parser

/// Parses a job description plain text into structured blocks.
///
/// Mirrors jd-parser.js `parseJdBlocks`.
public func parseJdBlocks(_ text: String?) -> [JDBlock] {
    guard let text, !text.isEmpty else { return [] }

    let lines = text.components(separatedBy: "\n")

    // Skip leading boilerplate: find first "real content" line.
    let headerRe = try? NSRegularExpression(
        pattern: #"^(overview|about|description|what you|role|position|responsibilities|qualifications|requirements|compensation|benefits|about us|the opportunity|the role|job summary|summary|who we|hiring)"#,
        options: .caseInsensitive
    )
    let emojiRe = try? NSRegularExpression(pattern: #"^\p{Emoji_Presentation}"#)

    let isProse: (String) -> Bool = { str in
        str.count >= 80 || (str.count >= 50 && (str.contains(",") || str.contains(".")))
    }

    // For LinkedIn pages, "Feed post" marks the start of actual post content.
    let feedPostIdx = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "Feed post" }) ?? -1
    let searchFrom = feedPostIdx >= 0 ? feedPostIdx + 1 : 0

    var start = searchFrom
    let searchLimit = min(lines.count, searchFrom + 30)
    for idx in searchFrom ..< searchLimit {
        let line = lines[idx].trimmingCharacters(in: .whitespaces)
        let nsStr = line as NSString
        let range = NSRange(location: 0, length: nsStr.length)
        let matchesHeader = headerRe?.firstMatch(in: line, range: range) != nil
        let matchesEmoji = emojiRe?.firstMatch(in: line, range: range) != nil
        if isProse(line) || matchesHeader || matchesEmoji {
            start = idx
            break
        }
    }

    var blocks: [JDBlock] = []
    var current: JDBlock?

    let flush: () -> Void = {
        if let cur = current { blocks.append(cur); current = nil }
    }

    for raw in lines[start...] {
        let line = raw.trimmingCharacters(in: .whitespaces)

        if line.isEmpty {
            flush()
            continue
        }

        // Stop at LinkedIn concatenated duplicate — long run-on starting with "Feed post" + non-space
        if line.hasPrefix("Feed post") && line.count > "Feed post".count && !line[line.index(
            line.startIndex,
            offsetBy: "Feed post".count
        )].isWhitespace {
            flush()
            break
        }

        // Bullet / list item
        if let bulletContent = extractBulletContent(line) {
            if case let .list(items) = current {
                current = .list(items: items + [bulletContent])
            } else {
                flush()
                current = .list(items: [bulletContent])
            }
            continue
        }

        // Horizontal rule
        if isHorizontalRule(line) {
            flush()
            blocks.append(.horizontalRule)
            continue
        }

        // Section heading
        let nsLine = line as NSString
        let lineRange = NSRange(location: 0, length: nsLine.length)
        let matchesHeader = headerRe?.firstMatch(in: line, range: lineRange) != nil
        let matchesEmoji = emojiRe?.firstMatch(in: line, range: lineRange) != nil
        let isHeading = isHeadingLine(line, matchesHeader: matchesHeader, matchesEmoji: matchesEmoji)

        if isHeading {
            flush()
            let headingText = line.hasSuffix(":") ? String(line.dropLast()) : line
            blocks.append(.heading(text: headingText))
            continue
        }

        // Paragraph — merge consecutive lines
        if case let .paragraph(existing) = current {
            current = .paragraph(text: existing + " " + line)
        } else {
            flush()
            current = .paragraph(text: line)
        }
    }
    flush()

    // Drop trailing <hr> blocks (LinkedIn separator before duplicate)
    while case .horizontalRule = blocks.last {
        blocks.removeLast()
    }

    return blocks
}

// MARK: - Helpers

private func extractBulletContent(_ line: String) -> String? {
    // Unicode bullet characters: •-*◦·▪▸►▷→✅✓✔
    let bulletChars: Set<Character> = ["•", "-", "*", "◦", "·", "▪", "▸", "►", "▷", "→", "✅", "✓", "✔"]
    if let first = line.first, bulletChars.contains(first) {
        let rest = line.dropFirst().trimmingCharacters(in: .whitespaces)
        if !rest.isEmpty { return rest }
    }
    // Numbered: \d+[.)]\s+...
    if let match = line.range(of: #"^\d+[.)]\s+"#, options: .regularExpression) {
        let rest = String(line[match.upperBound...])
        if !rest.isEmpty { return rest }
    }
    return nil
}

private func isHorizontalRule(_ line: String) -> Bool {
    guard line.count >= 3 else { return false }
    return line.allSatisfy { $0 == "-" } || line.allSatisfy { $0 == "=" }
}

private func isHeadingLine(_ line: String, matchesHeader: Bool, matchesEmoji: Bool) -> Bool {
    let isAllCaps = line.count < 80
        && line == line.uppercased()
        && line.contains(where: \.isUppercase)
        && line.contains(where: { $0.isLetter && $0.isUppercase })
        // Must have at least 3 uppercase letters
        && line.count(where: { $0.isUppercase }) >= 3
        && !line.contains(",") && !line.contains(";") && !line.contains("(")
        && !line.contains(")") && !line.contains(where: \.isNumber)

    let endsWithColon = line.hasSuffix(":")
        && line.count < 70
        && !line.contains(".")

    let isKnownHeader = line.count < 70 && matchesHeader
    let isEmojiLed = matchesEmoji && line.count < 80

    return isAllCaps || endsWithColon || isKnownHeader || isEmojiLed
}

// swiftlint:enable line_length cyclomatic_complexity function_body_length
