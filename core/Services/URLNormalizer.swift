import Foundation

/// Centralized URL normalization for job/capture lookup and dedup comparison (TASK-443/444).
/// One place defines what "the same job URL" means, so the extension's open-in-app, capture lookup,
/// and future precedence logic agree.
public enum URLNormalizer {
    /// Why a URL failed the captured-job ingestion policy (TASK-443).
    public enum ValidationError: Error, Equatable {
        case empty
        case unsupportedScheme(String)
        case malformed
    }

    /// Validate a captured/job URL against one shared ingestion policy and return a lightly
    /// normalized form: trimmed, with scheme + host lowercased (both case-insensitive per RFC 3986)
    /// while path/query/fragment are preserved so the stored URL still opens the exact page.
    /// Rejects empty, non-`http(s)`, and malformed URLs. Use this at every ingestion boundary so the
    /// store never persists a URL that later breaks availability checks, dedup, or open-in-app.
    public static func validatedForIngestion(_ raw: String) throws -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ValidationError.empty }
        guard var components = URLComponents(string: trimmed) else { throw ValidationError.malformed }
        guard let rawScheme = components.scheme else { throw ValidationError.unsupportedScheme("") }
        let scheme = rawScheme.lowercased()
        guard scheme == "http" || scheme == "https" else { throw ValidationError.unsupportedScheme(scheme) }
        guard let host = components.host, !host.isEmpty else { throw ValidationError.malformed }
        components.scheme = scheme
        components.host = host.lowercased()
        guard let result = components.url?.absoluteString else { throw ValidationError.malformed }
        return result
    }

    /// Query parameters that don't identify the resource — tracking/analytics noise that should not
    /// make two otherwise-identical URLs look different.
    private static let trackingParams: Set<String> = [
        "utm_source", "utm_medium", "utm_campaign", "utm_term", "utm_content",
        "gclid", "fbclid", "msclkid", "mc_cid", "mc_eid", "ref", "ref_src", "src", "trk"
    ]

    /// A canonical comparison form: lowercased scheme+host, no fragment, tracking params dropped and
    /// the rest sorted, trailing slash stripped. Returns nil if not an absolute http(s) URL.
    public static func normalized(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = components.host?.lowercased(), !host.isEmpty
        else { return nil }
        components.scheme = scheme
        components.host = host
        components.fragment = nil
        if let items = components.queryItems {
            let kept = items
                .filter { !trackingParams.contains($0.name.lowercased()) }
                .sorted { ($0.name, $0.value ?? "") < ($1.name, $1.value ?? "") }
            components.queryItems = kept.isEmpty ? nil : kept
        }
        var path = components.path
        while path.count > 1, path.hasSuffix("/") {
            path = String(path.dropLast())
        }
        components.path = path
        return components.url?.absoluteString
    }
}
