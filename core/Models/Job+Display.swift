import Foundation

// MARK: - Display fallbacks (no-LLM / pre-extraction)

/// Display-only fallbacks so a job is legible before (or without) extraction. These never touch
/// extraction-owned stored fields (TASK-525) — they're computed at read time, so re-extraction still
/// populates `title`/`company` normally. Used for rendering *and* sorting/searching so an un-extracted
/// job sorts and matches by its captured page title rather than collapsing to "Untitled".
public extension Job {
    /// Extracted title → captured page title → capture host → "Untitled".
    var displayTitle: String {
        if let title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return title }
        if let pageTitle = capture?.pageTitle,
           !pageTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return pageTitle }
        if let host = captureHost { return host }
        return "Untitled"
    }

    /// Extracted company → capture host (domain) as a hint. Nil when neither is available.
    var displayCompany: String? {
        if let company, !company.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return company }
        return captureHost
    }

    /// The capture's host with a leading `www.` stripped (e.g. `boards.greenhouse.io`). Nil when there
    /// is no capture or its URL has no host.
    var captureHost: String? {
        guard let urlString = capture?.canonicalURL ?? capture?.url,
              let host = URL(string: urlString)?.host, !host.isEmpty else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}
