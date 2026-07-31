// Extracted from main.swift so these symbols are importable by MCPTests (@testable import JobhuntMCP).
// main.swift symbols are implicitly @MainActor-isolated and can't be imported.
import Foundation
import JobhuntCore

// MARK: - Simple string error

struct MCPError: Error {
    let message: String
    init(_ message: String) {
        self.message = message
    }
}

// MARK: - Token & port discovery

func readToken(at url: URL = MCPTokenManager.tokenURL) -> String? {
    // Single source of truth for the token path + owner-only permission policy — shared with the app
    // via JobhuntCore instead of a duplicated stat/permission check that could drift (TASK-531).
    MCPTokenManager.read(at: url)
}

/// The token + port the bridge forwards to. Mutable and long-lived: the bridge is spawned once by the
/// MCP client, while the Jobhunt app it talks to is relaunched during development. Each relaunch
/// rotates `~/.jobhunt-mcp-token` (401s the cached token) and may change the port (refuses the old
/// connection). Holding these on a shared instance lets `callTool` refresh them on failure and retry,
/// instead of every request failing until the bridge itself is restarted (TASK-629).
final class MCPSession {
    var token: String
    var port: Int
    init(token: String, port: Int) {
        self.token = token
        self.port = port
    }
}

/// Whether a bridge response should trigger a one-time token/port refresh + retry: a 401 (the app
/// rotated the token on relaunch) or a bodyless server error (connection refused — the app moved ports
/// or is down). A 401 means we reached the server, so only the token needs refreshing (TASK-629).
func shouldRefreshMCP(status: Int, hasBody: Bool) -> Bool {
    status == 401 || (status >= 500 && !hasBody)
}

func discoverPort() -> Int? {
    // Shared contract with the app server + extension (TASK-433).
    let candidates = ServerPortContract.discoveryPorts.map(Int.init)
    for port in candidates {
        guard let url = URL(string: "http://127.0.0.1:\(port)/api/ping") else { continue }
        var request = URLRequest(url: url)
        request.timeoutInterval = 1.0
        var found = false
        let sem = DispatchSemaphore(value: 0)
        let task = URLSession.shared.dataTask(with: request) { _, response, _ in
            if let resp = response as? HTTPURLResponse, resp.statusCode == 200 {
                found = true
            }
            sem.signal()
        }
        task.resume()
        sem.wait()
        if found { return port }
    }
    return nil
}

// MARK: - HTTP helper

func postMCP(path: String, body: [String: Any], port: Int, token: String) -> (Int, Any?) {
    guard let url = URL(string: "http://127.0.0.1:\(port)\(path)") else {
        return (500, nil)
    }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(token, forHTTPHeaderField: "X-MCP-Token")
    request.timeoutInterval = 30.0
    if let bodyData = try? JSONSerialization.data(withJSONObject: body) {
        request.httpBody = bodyData
    }

    var statusCode = 500
    var resultObj: Any?
    let sem = DispatchSemaphore(value: 0)
    let task = URLSession.shared.dataTask(with: request) { data, response, _ in
        if let resp = response as? HTTPURLResponse {
            statusCode = resp.statusCode
        }
        if let data {
            resultObj = try? JSONSerialization.jsonObject(with: data)
        }
        sem.signal()
    }
    task.resume()
    sem.wait()
    return (statusCode, resultObj)
}

// MARK: - JSON-RPC helpers

func writeResponse(_ obj: [String: Any]) {
    if let data = try? JSONSerialization.data(withJSONObject: obj),
       let str = String(data: data, encoding: .utf8) {
        print(str)
        fflush(stdout)
    }
}

func successResponse(id: Any?, result: Any) -> [String: Any] {
    var resp: [String: Any] = ["jsonrpc": "2.0", "result": result]
    if let id { resp["id"] = id }
    return resp
}

func errorResponse(id: Any?, code: Int, message: String) -> [String: Any] {
    var resp: [String: Any] = [
        "jsonrpc": "2.0",
        "error": ["code": code, "message": message] as [String: Any]
    ]
    if let id { resp["id"] = id }
    return resp
}

// MARK: - Tool definitions

let tools: [[String: Any]] = [
    [
        "name": "jobs_list",
        "description": "List jobs with extraction metadata. Paginated: the response is an object " +
            "with jobs, total, offset, limit, has_more and next_offset — always check has_more " +
            "rather than assuming one call returned everything. Use summary: true for a compact " +
            "projection that pages up to 1000 rows at a time, and query for a server-side keyword " +
            "search so corpus-wide questions don't require paging every record. " +
            "Each row carries fit_score; use min_score to filter on it, and job_get for the full " +
            "per-résumé breakdown. requirements_verdict is the composite pass/fail across " +
            "location, salary and fit — prefer it over meets_criteria, which is location-only.",
        "inputSchema": [
            "type": "object",
            "properties": [
                "status": ["type": "string", "description": "Exact job status, e.g. archived."] as [String: Any],
                "limit": [
                    "type": "integer", "default": 50, "minimum": 1,
                    "description": "Max 200, or 1000 when summary is true. A higher value is " +
                        "reduced and reported in the response notice."
                ] as [String: Any],
                "offset": [
                    "type": "integer", "default": 0, "minimum": 0,
                    "description": "Rows to skip. Pass the response's next_offset to get the next page."
                ] as [String: Any],
                "summary": [
                    "type": "boolean", "default": false,
                    "description": "Return only job_number, company, title, status, location, " +
                        "salary and source_url."
                ] as [String: Any],
                "query": [
                    "type": "string",
                    "description": "Case-insensitive substring matched against title, company, " +
                        "location and the cleaned job description."
                ] as [String: Any],
                "company": ["type": "string", "description": "Case-insensitive company substring."] as [String: Any],
                "captured_after": [
                    "type": "string",
                    "description": "ISO-8601 timestamp or YYYY-MM-DD; keeps jobs captured on/after it."
                ] as [String: Any],
                "min_salary": [
                    "type": "integer",
                    "description": "Keeps jobs whose salary ceiling reaches this. Jobs with no " +
                        "stated salary are excluded when set."
                ] as [String: Any],
                "requirements_verdict": [
                    "type": "string", "enum": ["meets", "not_stated", "does_not_meet"],
                    "description": "Filter on the COMPOSITE verdict across location, salary floor " +
                        "and fit floor. Prefer this over meets_criteria, which is location-only."
                ] as [String: Any],
                "min_score": [
                    "type": "integer", "minimum": 0, "maximum": 100,
                    "description": "Keeps jobs whose fit score against your active résumés is at " +
                        "least this. Unscored jobs are excluded when set."
                ] as [String: Any]
            ] as [String: Any]
        ] as [String: Any]
    ],
    [
        "name": "job_get",
        "description": "Fetch full job metadata. Identify the job by job_number (preferred) or job_id. " +
            "Raw captured page text (selected_text, visible_text) is omitted by default; " +
            "pass include_raw_text: true to include it. Includes fit_scores: the stored per-résumé " +
            "analysis with dimension scores and per-requirement met/partial/missing assessments, " +
            "plus base/penalty (the score before and after gap penalties) and " +
            "assessment_prompt_version — scores from different versions are not comparable.",
        "inputSchema": [
            "type": "object",
            "required": [],
            "properties": [
                "job_number": ["type": "integer"],
                "job_id": [
                    "type": "string",
                    "description": "Internal job id (back-compat alternative to job_number)."
                ] as [String: Any],
                "include_raw_text": [
                    "type": "boolean",
                    "description": "Set to true to include raw captured page text " +
                        "(selected_text, visible_text). Omitted by default for privacy."
                ] as [String: Any]
            ] as [String: Any]
        ] as [String: Any]
    ],
    [
        "name": "add_capture",
        "description": "Create or update a job capture from browser content. Structured job metadata " +
            "(JSON-LD / Greenhouse) may be supplied either as `structured_data_json` (a pre-stringified " +
            "JSON array) or as `structured_data` (a raw JSON array); `structured_data_json` takes " +
            "precedence. Both are optional — capture still ingests from visible/selected text without them.",
        "inputSchema": [
            "type": "object",
            "required": ["url", "page_title"],
            "properties": [
                "url": ["type": "string"],
                "page_title": ["type": "string"],
                "visible_text": ["type": "string", "default": ""],
                "selected_text": ["type": "string", "default": ""],
                "canonical_url": ["type": "string"],
                "user_note": ["type": "string", "default": ""],
                "structured_data_json": [
                    "type": "string",
                    "description": "Pre-stringified JSON array of structured-data objects."
                ] as [String: Any],
                "structured_data": [
                    "type": "array",
                    "items": ["type": "object"] as [String: Any],
                    "description": "Raw JSON array of structured-data objects (the browser-extension shape)."
                ] as [String: Any]
            ] as [String: Any]
        ] as [String: Any]
    ],
    [
        "name": "update_job",
        "description": "Patch selected job fields. Identify the job by job_number (preferred) or job_id.",
        "inputSchema": [
            "type": "object",
            "required": [],
            "properties": [
                "job_number": ["type": "integer"],
                "job_id": ["type": "string"],
                "company": ["type": "string"],
                "title": ["type": "string"],
                "location": ["type": "string"],
                "salary_min": ["type": "integer"],
                "salary_max": ["type": "integer"],
                "salary_note": ["type": "string"]
            ] as [String: Any]
        ] as [String: Any]
    ],
    [
        "name": "set_job_status",
        "description": "Set workflow status for a job. Identify the job by job_number (preferred) or job_id.",
        "inputSchema": [
            "type": "object",
            "required": ["status"],
            "properties": [
                "job_number": ["type": "integer"],
                "job_id": ["type": "string"],
                "status": ["type": "string"]
            ] as [String: Any]
        ] as [String: Any]
    ],
    [
        "name": "mark_job_applied",
        "description": """
        Mark a job as applied using its posting URL. Resolves an existing job by capture URL, canonical \
        URL, normalized variants (tracking params / trailing slash), or its application URL. If the \
        posting was never captured, creates a minimal job record and marks it applied without waiting \
        for extraction. Idempotent: repeating the call does not create another job, status event, or \
        note. A job already at Interview/Offer is not regressed.
        """,
        "inputSchema": [
            "type": "object",
            "required": ["url"],
            "properties": [
                "url": ["type": "string", "description": "The job posting URL"],
                "company": ["type": "string"],
                "title": ["type": "string"],
                "page_title": ["type": "string"],
                "application_url": ["type": "string"],
                "note": ["type": "string"]
            ] as [String: Any]
        ] as [String: Any]
    ],
    [
        "name": "add_job_note",
        "description": "Add a note event to a job. Identify the job by job_number (preferred) or job_id.",
        "inputSchema": [
            "type": "object",
            "required": ["note"],
            "properties": [
                "job_number": ["type": "integer"],
                "job_id": ["type": "string"],
                "note": ["type": "string"]
            ] as [String: Any]
        ] as [String: Any]
    ],
    [
        "name": "rerun_extraction",
        "description": "Reset extraction so it will be retried on the next run. " +
            "Identify the job by job_number (preferred) or job_id.",
        "inputSchema": [
            "type": "object",
            "required": [],
            "properties": [
                "job_number": ["type": "integer"],
                "job_id": ["type": "string"]
            ] as [String: Any]
        ] as [String: Any]
    ],
    [
        "name": "list_sites",
        "description": "List all prospecting/review sites.",
        "inputSchema": [
            "type": "object",
            "properties": [:] as [String: Any]
        ] as [String: Any]
    ],
    [
        "name": "add_site",
        "description": "Create a prospective site for later review.",
        "inputSchema": [
            "type": "object",
            "required": ["url"],
            "properties": [
                "url": ["type": "string"],
                "name": ["type": "string"],
                "state": ["type": "string"],
                "interval_days": ["type": "integer"],
                "note": ["type": "string"],
                "company_website": ["type": "string"],
                "jobs_url": ["type": "string"],
                "company_description": ["type": "string"]
            ] as [String: Any]
        ] as [String: Any]
    ],
    [
        "name": "update_site",
        "description": "Update site metadata or next-review schedule.",
        "inputSchema": [
            "type": "object",
            "required": ["id"],
            "properties": [
                "id": ["type": "string"],
                "name": ["type": "string"],
                "state": ["type": "string"],
                "interval_days": ["type": "integer"],
                "note": ["type": "string"],
                "company_website": ["type": "string"],
                "jobs_url": ["type": "string"],
                "company_description": ["type": "string"]
            ] as [String: Any]
        ] as [String: Any]
    ],
    [
        "name": "delete_site",
        "description": "Delete a prospect site.",
        "inputSchema": [
            "type": "object",
            "required": ["id"],
            "properties": [
                "id": ["type": "string"]
            ] as [String: Any]
        ] as [String: Any]
    ],
    [
        "name": "workflow_snapshot",
        "description": "Compact status snapshot for triage workflows.",
        "inputSchema": [
            "type": "object",
            "properties": [:] as [String: Any]
        ] as [String: Any]
    ]
]

// MARK: - Tool dispatch

func textResult(_ value: Any) -> [String: Any] {
    let text: String = if let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted]),
                          let str = String(data: data, encoding: .utf8) {
        str
    } else {
        "\(value)"
    }
    return ["content": [["type": "text", "text": text]]]
}

// swiftlint:disable:next cyclomatic_complexity
func resolveToolRoute(name: String, args: [String: Any]) -> Result<(String, [String: Any]), MCPError> {
    switch name {
    case "jobs_list":
        var b: [String: Any] = [:]
        for key in [
            "status", "limit", "offset", "summary", "query", "company",
            "captured_after", "min_salary", "min_score", "requirements_verdict"
        ] {
            if let value = args[key] { b[key] = value }
        }
        return .success(("/mcp/jobs/list", b))
    case "job_get":
        // TASK-464: accept either job_number (primary) or job_id (Electron back-compat).
        guard args["job_number"] != nil || args["job_id"] != nil else {
            return .failure(MCPError("job_number or job_id required"))
        }
        var b: [String: Any] = [:]
        if let num = args["job_number"] { b["job_number"] = num }
        if let jid = args["job_id"] { b["job_id"] = jid }
        if let raw = args["include_raw_text"] { b["include_raw_text"] = raw }
        return .success(("/mcp/jobs/get", b))
    case "add_capture":
        guard args["url"] != nil, args["page_title"] != nil else {
            return .failure(MCPError("url and page_title required"))
        }
        return .success(("/mcp/captures/add", args))
    case "update_job":
        guard args["job_number"] != nil || args["job_id"] != nil else {
            return .failure(MCPError("job_number or job_id required"))
        }
        return .success(("/mcp/jobs/update", args))
    case "set_job_status":
        guard args["job_number"] != nil || args["job_id"] != nil, args["status"] != nil else {
            return .failure(MCPError("job_number or job_id, and status, required"))
        }
        return .success(("/mcp/jobs/status", args))
    case "mark_job_applied":
        guard args["url"] != nil else { return .failure(MCPError("url required")) }
        return .success(("/mcp/jobs/mark-applied", args))
    case "add_job_note":
        guard args["job_number"] != nil || args["job_id"] != nil, args["note"] != nil else {
            return .failure(MCPError("job_number or job_id, and note, required"))
        }
        return .success(("/mcp/jobs/note", args))
    case "rerun_extraction":
        guard args["job_number"] != nil || args["job_id"] != nil else {
            return .failure(MCPError("job_number or job_id required"))
        }
        return .success(("/mcp/jobs/rerun", args))
    case "list_sites": return .success(("/mcp/sites/list", [:]))
    case "add_site":
        guard args["url"] != nil else { return .failure(MCPError("url required")) }
        return .success(("/mcp/sites/add", args))
    case "update_site":
        guard args["id"] != nil else { return .failure(MCPError("id required")) }
        return .success(("/mcp/sites/update", args))
    case "delete_site":
        guard args["id"] != nil else { return .failure(MCPError("id required")) }
        return .success(("/mcp/sites/delete", args))
    case "workflow_snapshot": return .success(("/mcp/snapshot", [:]))
    default: return .failure(MCPError("unknown tool: \(name)"))
    }
}

func callTool(name: String, args: [String: Any], session: MCPSession) -> Result<[String: Any], MCPError> {
    let routeResult = resolveToolRoute(name: name, args: args)
    let (path, body): (String, [String: Any])
    switch routeResult {
    case let .success(r): (path, body) = r
    case let .failure(e): return .failure(e)
    }

    var (status, result) = postMCP(path: path, body: body, port: session.port, token: session.token)

    // The app may have relaunched since the bridge started: refresh the token (always) and, only on a
    // connection failure, re-probe the port — then retry once before surfacing the error (TASK-629).
    if shouldRefreshMCP(status: status, hasBody: result != nil) {
        if let freshToken = readToken() { session.token = freshToken }
        if status != 401, let freshPort = discoverPort() { session.port = freshPort }
        (status, result) = postMCP(path: path, body: body, port: session.port, token: session.token)
    }

    if status >= 400 {
        let msg: String = if let obj = result as? [String: Any], let err = obj["error"] as? String {
            err
        } else {
            "HTTP \(status)"
        }
        return .failure(MCPError(msg))
    }
    if let result {
        return .success(textResult(result))
    }
    return .success(textResult(["ok": true]))
}
