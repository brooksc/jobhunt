import Foundation

/// Centralized URL normalization for job/capture lookup and dedup comparison (TASK-443/444).
/// One place defines what "the same job URL" means, so the extension's open-in-app, capture lookup,
/// and future precedence logic agree.
public enum URLNormalizer {
    /// Query parameters that don't identify the resource — tracking/analytics noise that should not
    /// make two otherwise-identical URLs look different.
    private static let trackingParams: Set<String> = [
        "utm_source", "utm_medium", "utm_campaign", "utm_term", "utm_content",
        "gclid", "fbclid", "msclkid", "mc_cid", "mc_eid", "ref", "ref_src", "src", "trk",
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
        while path.count > 1, path.hasSuffix("/") { path = String(path.dropLast()) }
        components.path = path
        return components.url?.absoluteString
    }
}
