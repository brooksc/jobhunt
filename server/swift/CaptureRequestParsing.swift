import Foundation

/// Centralized policy for how a capture request carries structured (JSON-LD / Greenhouse) data,
/// so the server, MCP bridge, extension, and ingestion don't drift on field names (TASK-442).
///
/// Accepted shapes, in precedence order:
///  1. `structured_data_json` — a pre-stringified JSON array of objects (the typed
///     `CaptureRequest.structuredDataJSON` / `MCPCaptureIngestRequest.structuredDataJSON`).
///  2. `structured_data` — a raw JSON array on the request body (what the browser extension sends).
///
/// When neither is present, or the array can't be re-serialized, this returns `nil` and the caller
/// still ingests visible/selected text — structured data degrades safely, it is never required.
enum CaptureRequestParsing {
    static let structuredDataJSONField = "structured_data_json"
    static let structuredDataArrayField = "structured_data"

    static func resolveStructuredDataJSON(typed: String?, rawBody: Data?) -> String? {
        if let typed = typed?.trimmingCharacters(in: .whitespacesAndNewlines), !typed.isEmpty {
            return typed
        }
        guard let rawBody,
              let obj = try? JSONSerialization.jsonObject(with: rawBody) as? [String: Any],
              let arr = obj[structuredDataArrayField], !(arr is NSNull),
              JSONSerialization.isValidJSONObject(arr),
              let data = try? JSONSerialization.data(withJSONObject: arr) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
}
