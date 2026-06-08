// JobhuntMCP — stdio→HTTP bridge (DMG only).
// MAS builds exclude this target via the Jobhunt-MAS scheme.
// Reads MCP JSON-RPC 2.0 requests from stdin, forwards to the running Jobhunt.app
// HTTP server via /mcp/* endpoints authenticated with X-MCP-Token.
import Foundation

// MARK: - Token & port discovery

func readToken() -> String? {
    let tokenURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".jobhunt-mcp-token")
    guard let token = try? String(contentsOf: tokenURL, encoding: .utf8) else { return nil }
    return token.trimmingCharacters(in: .whitespacesAndNewlines)
}

func discoverPort() -> Int? {
    let candidates = [8765, 8766, 8767, 8768, 8769]
    for port in candidates {
        guard let url = URL(string: "http://127.0.0.1:\(port)/api/ping") else { continue }
        var request = URLRequest(url: url)
        request.timeoutInterval = 1.0
        var found = false
        let sem = DispatchSemaphore(value: 0)
        let task = URLSession.shared.dataTask(with: request) { data, response, _ in
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
    let task = URLSession.shared.dataTask(with: request) { data, response, error in
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
        "description": "Fetch full job metadata and capture text.",
        "inputSchema": [
            "type": "object",
            "required": ["job_number"],
            "properties": [
                "job_number": ["type": "integer"]
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
                "interval_days": ["type": "integer"]
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
    let text: String
    if let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted]),
       let str = String(data: data, encoding: .utf8) {
        text = str
    } else {
        text = "\(value)"
    }
    return ["content": [["type": "text", "text": text]]]
}

func callTool(name: String, args: [String: Any], port: Int, token: String) -> Result<[String: Any], String> {
    let (path, body): (String, [String: Any])

    switch name {
    case "jobs_list":
        var b: [String: Any] = [:]
        if let s = args["status"] { b["status"] = s }
        if let l = args["limit"] { b["limit"] = l }
        (path, body) = ("/mcp/jobs/list", b)

    case "job_get":
        guard let num = args["job_number"] else {
            return .failure("job_number required")
        }
        (path, body) = ("/mcp/jobs/get", ["job_number": num])

    case "add_capture":
        guard args["url"] != nil, args["page_title"] != nil else {
            return .failure("url and page_title required")
        }
        (path, body) = ("/mcp/captures/add", args)

    case "update_job":
        guard args["job_number"] != nil else {
            return .failure("job_number required")
        }
        (path, body) = ("/mcp/jobs/update", args)

    case "set_job_status":
        guard args["job_number"] != nil, args["status"] != nil else {
            return .failure("job_number and status required")
        }
        (path, body) = ("/mcp/jobs/status", args)

    case "add_job_note":
        guard args["job_number"] != nil, args["note"] != nil else {
            return .failure("job_number and note required")
        }
        (path, body) = ("/mcp/jobs/note", args)

    case "rerun_extraction":
        guard args["job_number"] != nil else {
            return .failure("job_number required")
        }
        (path, body) = ("/mcp/jobs/rerun", args)

    case "list_sites":
        (path, body) = ("/mcp/sites/list", [:])

    case "add_site":
        guard args["url"] != nil else {
            return .failure("url required")
        }
        (path, body) = ("/mcp/sites/add", args)

    case "update_site":
        guard args["id"] != nil else {
            return .failure("id required")
        }
        (path, body) = ("/mcp/sites/update", args)

    case "delete_site":
        guard args["id"] != nil else {
            return .failure("id required")
        }
        (path, body) = ("/mcp/sites/delete", args)

    case "workflow_snapshot":
        (path, body) = ("/mcp/snapshot", [:])

    default:
        return .failure("unknown tool: \(name)")
    }

    let (status, result) = postMCP(path: path, body: body, port: port, token: token)
    if status >= 400 {
        let msg: String
        if let obj = result as? [String: Any], let err = obj["error"] as? String {
            msg = err
        } else {
            msg = "HTTP \(status)"
        }
        return .failure(msg)
    }
    if let result {
        return .success(textResult(result))
    }
    return .success(textResult(["ok": true]))
}

// MARK: - Main loop

guard let token = readToken() else {
    fputs("jobhunt-mcp: no token found at ~/.jobhunt-mcp-token\n", stderr)
    exit(1)
}

guard let port = discoverPort() else {
    fputs("jobhunt-mcp: Jobhunt.app not running on ports 8765-8769\n", stderr)
    exit(1)
}

// Read JSON-RPC 2.0 requests from stdin line by line
while let line = readLine() {
    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { continue }

    guard let data = trimmed.data(using: .utf8),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        writeResponse(errorResponse(id: nil, code: -32700, message: "Parse error"))
        continue
    }

    let id = json["id"]
    let method = json["method"] as? String ?? ""
    let params = json["params"] as? [String: Any] ?? [:]

    switch method {
    case "initialize":
        writeResponse(successResponse(id: id, result: [
            "protocolVersion": "2024-11-05",
            "capabilities": ["tools": [:] as [String: Any]],
            "serverInfo": ["name": "jobhunt", "version": "1.0.0"]
        ] as [String: Any]))

    case "notifications/initialized":
        // No response needed for notifications
        continue

    case "tools/list":
        writeResponse(successResponse(id: id, result: ["tools": tools]))

    case "tools/call":
        let toolName = params["name"] as? String ?? ""
        let toolArgs = params["arguments"] as? [String: Any] ?? [:]

        switch callTool(name: toolName, args: toolArgs, port: port, token: token) {
        case .success(let result):
            writeResponse(successResponse(id: id, result: result))
        case .failure(let msg):
            writeResponse(successResponse(id: id, result: [
                "isError": true,
                "content": [["type": "text", "text": msg]]
            ] as [String: Any]))
        }

    default:
        writeResponse(errorResponse(id: id, code: -32601, message: "Method not found: \(method)"))
    }
}
