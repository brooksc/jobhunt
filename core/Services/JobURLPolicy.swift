import Foundation

/// Single source of truth for which URL each surface uses for a job (TASK-460).
///
/// Different surfaces previously inlined different precedence (CSV used `canonical ?? captureURL`,
/// MCP projections used the raw `captureURL`, availability used `applicationURL ?? canonical ??
/// captureURL`, detail actions used `captureURL ?? applicationURL`), so the same job could export,
/// display, and be checked under different URLs. These helpers define the precedence once.
///
/// All helpers skip nil *and* empty/whitespace values, so an empty field never shadows a usable
/// fallback (TASK-460 AC#4).
public enum JobURLPolicy {
    // MARK: - Value-level precedence (pure, testable)

    /// The listing the job was captured from: prefer the page's canonical link over the raw URL.
    public static func sourceURL(canonicalURL: String?, captureURL: String?) -> String? {
        firstUsable(canonicalURL, captureURL)
    }

    /// Where the user applies / what automation should hit: an explicit application URL wins, then
    /// the source listing. Availability checking uses this same precedence.
    public static func applicationURL(applicationURL: String?, canonicalURL: String?, captureURL: String?) -> String? {
        firstUsable(applicationURL, canonicalURL, captureURL)
    }

    /// What "View Posting" should open: prefer the source listing, falling back to the application
    /// URL when there's no capture URL at all.
    public static func displayURL(applicationURL: String?, canonicalURL: String?, captureURL: String?) -> String? {
        firstUsable(canonicalURL, captureURL, applicationURL)
    }

    // MARK: - Job conveniences

    public static func sourceURL(job: Job) -> String? {
        sourceURL(canonicalURL: job.capture?.canonicalURL, captureURL: job.capture?.url)
    }

    public static func applicationURL(job: Job) -> String? {
        applicationURL(applicationURL: job.applicationURL,
                       canonicalURL: job.capture?.canonicalURL,
                       captureURL: job.capture?.url)
    }

    /// URL to verify the posting is still live — same precedence as `applicationURL`.
    public static func availabilityCheckURL(job: Job) -> String? {
        applicationURL(job: job)
    }

    public static func displayURL(job: Job) -> String? {
        displayURL(applicationURL: job.applicationURL,
                   canonicalURL: job.capture?.canonicalURL,
                   captureURL: job.capture?.url)
    }

    // MARK: - Helper

    /// First value that is non-nil and not blank after trimming.
    private static func firstUsable(_ candidates: String?...) -> String? {
        for candidate in candidates {
            if let value = candidate?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
                return value
            }
        }
        return nil
    }
}
