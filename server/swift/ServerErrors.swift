import Foundation
import JobhuntCore

// MARK: - Safe server error codes

/// Stable codes returned to clients in HTTP error bodies.
/// Never expose localizedDescription or implementation details.
enum ServerErrorCode: String {
    case storeUnavailable = "store_unavailable"
    case requestInvalid = "request_invalid"
    case internalError = "internal_error"
}

/// Logs the full error to the console and returns a stable, non-leaking message
/// suitable for inclusion in an HTTP response body.
func safeServerError(_ error: Error, context: String) -> String {
    // The HTTP body is already safe (a stable code); the Console line is a support surface too, so
    // redact file paths / URL queries / secrets from the raw error text before logging (TASK-551).
    print("[JobhuntServer] \(context): \(DiagnosticsRedactor.redact("\(error)"))")
    return ServerErrorCode.internalError.rawValue
}
