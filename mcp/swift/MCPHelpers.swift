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

func readToken() -> String? {
    let tokenURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".jobhunt-mcp-token")
    let path = tokenURL.path
    // Refuse to use the token if the file has group or world-readable bits (must be 0600).
    var st = stat()
    guard stat(path, &st) == 0,
          (st.st_mode & 0o177) == 0
    else { return nil }
    guard let token = try? String(contentsOf: tokenURL, encoding: .utf8) else { return nil }
    return token.trimmingCharacters(in: .whitespacesAndNewlines)
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
        "description": "List jobs with extraction metadata.",
        "inputSchema": [
            "type": "object",
            "properties": [
                "status": ["type": "string"],
                "limit": ["type": "integer", "default": 50, "minimum": 1]
            ] as [String: Any]
        ] as [String: Any]
    ],
    [
        "name": "job_get",
        "description": "Fetch full job metadata. Raw captured page text (selected_text, visible_text) is omitted by default; pass include_raw_text: true to include it.",
        "inputSchema": [
            "type": "object",
            "required": ["job_number"],
            "properties": [
                "job_number": ["type": "integer"],
                "include_raw_text": [
                    "type": "boolean",
                    "description": "Set to true to include raw captured page text (selected_text, visible_text). Omitted by default for privacy."
                ] as [String: Any]
            ] as [String: Any]
        ] as [String: Any]
    ],
    [
        "name": "add_capture",
        "description": "Create or update a job capture from browser content.",
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
                "structured_data_json": ["type": "string"]
            ] as [String: Any]
        ] as [String: Any]
    ],
    [
        "name": "update_job",
        "description": "Patch selected job fields.",
        "inputSchema": [
            "type": "object",
            "required": ["job_number"],
            "properties": [
                "job_number": ["type": "integer"],
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
        "description": "Set workflow status for a job.",
        "inputSchema": [
            "type": "object",
            "required": ["job_number", "status"],
            "properties": [
                "job_number": ["type": "integer"],
                "status": ["type": "string"]
            ] as [String: Any]
        ] as [String: Any]
    ],
    [
        "name": "add_job_note",
        "description": "Add a note event to a job.",
        "inputSchema": [
            "type": "object",
            "required": ["job_number", "note"],
            "properties": [
                "job_number": ["type": "integer"],
                "note": ["type": "string"]
            ] as [String: Any]
        ] as [String: Any]
    ],
    [
        "name": "rerun_extraction",
        "description": "Reset extraction so it will be retried on the next run.",
        "inputSchema": [
            "type": "object",
            "required": ["job_number"],
            "properties": [
                "job_number": ["type": "integer"]
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
                "name": ["type": "string"]
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
        if let s = args["status"] { b["status"] = s }
        if let l = args["limit"] { b["limit"] = l }
        return .success(("/mcp/jobs/list", b))
    case "job_get":
        guard let num = args["job_number"] else { return .failure(MCPError("job_number required")) }
        var b: [String: Any] = ["job_number": num]
        if let raw = args["include_raw_text"] { b["include_raw_text"] = raw }
        return .success(("/mcp/jobs/get", b))
    case "add_capture":
        guard args["url"] != nil, args["page_title"] != nil else {
            return .failure(MCPError("url and page_title required"))
        }
        return .success(("/mcp/captures/add", args))
    case "update_job":
        guard args["job_number"] != nil else { return .failure(MCPError("job_number required")) }
        return .success(("/mcp/jobs/update", args))
    case "set_job_status":
        guard args["job_number"] != nil, args["status"] != nil else {
            return .failure(MCPError("job_number and status required"))
        }
        return .success(("/mcp/jobs/status", args))
    case "add_job_note":
        guard args["job_number"] != nil, args["note"] != nil else {
            return .failure(MCPError("job_number and note required"))
        }
        return .success(("/mcp/jobs/note", args))
    case "rerun_extraction":
        guard args["job_number"] != nil else { return .failure(MCPError("job_number required")) }
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

func callTool(name: String, args: [String: Any], port: Int, token: String) -> Result<[String: Any], MCPError> {
    let routeResult = resolveToolRoute(name: name, args: args)
    let (path, body): (String, [String: Any])
    switch routeResult {
    case let .success(r): (path, body) = r
    case let .failure(e): return .failure(e)
    }

    let (status, result) = postMCP(path: path, body: body, port: port, token: token)
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
