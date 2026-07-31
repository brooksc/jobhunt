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

/// Boundary mapper for capture ingestion (TASK-558): typed client-input validation failures from
/// `JobService.ingestCapture` are client errors, so they return HTTP 400 with their stable,
/// non-leaking message. Everything else (persistence/server faults) falls back to the safe 500 path.
/// Shared by the extension `/captures` route and the MCP `/mcp/captures/add` route.
func captureIngestionErrorResponse(_ error: Error, context: String) -> HTTPResponse {
    if case let svcError as JobServiceError = error {
        switch svcError {
        case .missingURL, .invalidURL, .missingPageTitle, .missingText:
            return HTTPResponse.error(svcError.errorDescription ?? "Invalid capture", code: 400)
        case .jobNotFound, .actionNotFound, .contactNotFound, .coverLetterNotFound, .invalidStatus:
            break // not reachable from ingestion, but treat as unexpected → safe 500
        }
    }
    return HTTPResponse.error(safeServerError(error, context: context), code: 500)
}
