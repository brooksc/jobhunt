import Foundation

/// Central redaction for any free-form error string before it enters a support/diagnostics bundle.
///
/// Error strings come from arbitrary `localizedDescription` values and can carry file paths, URL
/// query strings, API keys/bearer tokens, or provider response fragments. Everything that gets
/// copied out of the app for support must pass through here.
public enum DiagnosticsRedactor {
    /// Replaces file paths, URL query strings, and common secret prefixes with `[redacted]`.
    public static func redact(_ s: String) -> String {
        var result = s

        // File paths: /Users/..., /private/..., /var/..., /tmp/...
        result = replace(in: result, pattern: #"(/Users/|/private/|/var/|/tmp/)[^\s\"\']+"#, template: "[redacted]")

        // URL query strings: strip everything after '?' in http/https URLs (keep the path).
        result = replace(in: result, pattern: #"(https?://[^\s\?]+)\?[^\s]*"#, template: "$1?[redacted]")

        // Common secret prefixes: Bearer tokens, OpenAI-style keys, Google API keys.
        result = replace(in: result, pattern: #"(Bearer\s+|sk-|AIza)[A-Za-z0-9\-_\.]{8,}"#, template: "[redacted]")

        return result
    }

    private static func replace(in s: String, pattern: String, template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return s }
        let range = NSRange(s.startIndex..., in: s)
        return regex.stringByReplacingMatches(in: s, range: range, withTemplate: template)
    }
}
