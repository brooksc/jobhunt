import Foundation

/// Whether a URL's host really belongs to a vendor (TASK-703).
///
/// The obvious spellings are both wrong, and both were in use here:
///
/// - `host.hasSuffix("myworkdayjobs.com")` accepts **`evilmyworkdayjobs.com`** — an attacker's
///   domain, which jobhunt would then fetch and treat as a Workday tenant.
/// - `host.contains("greenhouse.io")` accepts **`greenhouse.io.evil.com`**, which isn't even a
///   subdomain of the vendor.
///
/// A host belongs to a domain only if it *is* that domain or sits beneath it, and the dot is what
/// makes the difference. These requests carry no application credentials, so this isn't credential
/// exfiltration — but it does let a hostile URL steer jobhunt's outbound traffic and have the
/// response parsed as though a vendor had sent it.
public enum ATSHost {
    public static func belongs(_ host: String?, to domain: String) -> Bool {
        guard let host = host?.lowercased(), !host.isEmpty else { return false }
        let domain = domain.lowercased()
        if host == domain {
            return true
        }
        // A subdomain needs an actual label in front of the dot: ".lever.co" ends with ".lever.co"
        // but names nothing. Not reachable through URLComponents today, which is exactly why it
        // should be refused here rather than relied on not to arrive.
        return host.hasSuffix(".\(domain)") && host.count > domain.count + 1
    }

    /// Convenience for a URL string, so callers don't each re-derive the host.
    public static func belongs(urlString: String, to domain: String) -> Bool {
        belongs(URLComponents(string: urlString)?.host, to: domain)
    }
}
