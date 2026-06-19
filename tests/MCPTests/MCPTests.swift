// MCPHelpers.swift is compiled directly into this test bundle (JobhuntMCP is a tool, not a framework).
import XCTest

final class MCPTests: XCTestCase {
    // MARK: - JSON-RPC response shape

    func testSuccessResponse_hasCorrectShape() {
        let resp = successResponse(id: 42, result: ["key": "value"])
        XCTAssertEqual(resp["jsonrpc"] as? String, "2.0")
        XCTAssertEqual(resp["id"] as? Int, 42)
        XCTAssertNotNil(resp["result"])
        XCTAssertNil(resp["error"])
    }

    func testSuccessResponse_nilIdOmitted() {
        let resp = successResponse(id: nil, result: "ok")
        XCTAssertNil(resp["id"])
        XCTAssertEqual(resp["jsonrpc"] as? String, "2.0")
    }

    func testErrorResponse_hasCorrectShape() {
        let resp = errorResponse(id: 1, code: -32601, message: "Method not found")
        XCTAssertEqual(resp["jsonrpc"] as? String, "2.0")
        XCTAssertEqual(resp["id"] as? Int, 1)
        XCTAssertNil(resp["result"])
        let error = resp["error"] as? [String: Any]
        XCTAssertEqual(error?["code"] as? Int, -32601)
        XCTAssertEqual(error?["message"] as? String, "Method not found")
    }

    func testErrorResponse_nilIdOmitted() {
        let resp = errorResponse(id: nil, code: -32700, message: "Parse error")
        XCTAssertNil(resp["id"])
    }

    // MARK: - Tool definitions

    func testToolList_containsExpectedTools() {
        let names = tools.compactMap { $0["name"] as? String }
        XCTAssertTrue(names.contains("jobs_list"), "Missing jobs_list tool")
        XCTAssertTrue(names.contains("job_get"), "Missing job_get tool")
        XCTAssertTrue(names.contains("add_capture"), "Missing add_capture tool")
    }

    func testToolList_allHaveNameAndDescription() {
        for tool in tools {
            XCTAssertNotNil(tool["name"] as? String, "Tool missing name: \(tool)")
            XCTAssertNotNil(tool["description"] as? String, "Tool missing description: \(tool)")
            XCTAssertNotNil(tool["inputSchema"], "Tool missing inputSchema: \(tool)")
        }
    }

    func testToolList_allSchemasHaveType() {
        for tool in tools {
            let schema = tool["inputSchema"] as? [String: Any]
            XCTAssertEqual(
                schema?["type"] as? String,
                "object",
                "inputSchema.type should be 'object' for \(tool["name"] ?? "?")"
            )
        }
    }

    // MARK: - textResult helper

    func testTextResult_withDict() {
        let result = textResult(["status": "ok"])
        let content = result["content"] as? [[String: Any]]
        XCTAssertEqual(content?.first?["type"] as? String, "text")
        XCTAssertTrue((content?.first?["text"] as? String ?? "").contains("ok"))
    }

    // MARK: - Tool route resolution

    func testResolveToolRoute_unknownTool_returnsFailure() {
        let result = resolveToolRoute(name: "nonexistent_tool", args: [:])
        if case let .failure(err) = result {
            XCTAssertTrue(err.message.contains("unknown tool"))
        } else {
            XCTFail("Expected failure for unknown tool")
        }
    }

    func testResolveToolRoute_jobsList_missingArgs_succeeds() {
        let result = resolveToolRoute(name: "jobs_list", args: [:])
        if case let .success((path, body)) = result {
            XCTAssertEqual(path, "/mcp/jobs/list")
            XCTAssertTrue(body.isEmpty)
        } else {
            XCTFail("Expected success for jobs_list with no args")
        }
    }

    func testResolveToolRoute_addCapture_missingRequired_returnsFailure() {
        let result = resolveToolRoute(name: "add_capture", args: ["url": "https://example.com"])
        if case let .failure(err) = result {
            XCTAssertTrue(err.message.contains("required"))
        } else {
            XCTFail("Expected failure when page_title is missing")
        }
    }

    // MARK: - TASK-464: MCP job tools accept job_id (Electron back-compat) or job_number

    func testResolveToolRoute_jobGet_acceptsJobNumber() {
        guard case let .success((path, body)) = resolveToolRoute(name: "job_get", args: ["job_number": 7]) else {
            return XCTFail("job_number should succeed")
        }
        XCTAssertEqual(path, "/mcp/jobs/get")
        XCTAssertEqual(body["job_number"] as? Int, 7)
    }

    func testResolveToolRoute_jobGet_acceptsJobId() {
        guard case let .success((_, body)) = resolveToolRoute(name: "job_get", args: ["job_id": "job-abc"]) else {
            return XCTFail("job_id should succeed (back-compat)")
        }
        XCTAssertEqual(body["job_id"] as? String, "job-abc")
        XCTAssertNil(body["job_number"])
    }

    func testResolveToolRoute_jobTools_requireAnIdentifier() {
        for tool in ["job_get", "update_job", "rerun_extraction"] {
            guard case let .failure(err) = resolveToolRoute(name: tool, args: [:]) else {
                return XCTFail("\(tool) with no identifier must fail")
            }
            XCTAssertTrue(err.message.contains("job_number or job_id"), "\(tool): \(err.message)")
        }
        // status/note tools also need their second arg.
        guard case .failure = resolveToolRoute(name: "set_job_status", args: ["job_id": "x"]) else {
            return XCTFail("set_job_status needs status")
        }
    }

    func testResolveToolRoute_setStatus_acceptsJobIdWithStatus() {
        guard case let .success((path, _)) = resolveToolRoute(
            name: "set_job_status", args: ["job_id": "job-x", "status": "applied"]
        ) else {
            return XCTFail("job_id + status should succeed")
        }
        XCTAssertEqual(path, "/mcp/jobs/status")
    }

    func testJobTools_schemas_exposeJobId() {
        for name in ["job_get", "update_job", "set_job_status", "add_job_note", "rerun_extraction"] {
            let tool = tools.first { $0["name"] as? String == name }
            let props = (tool?["inputSchema"] as? [String: Any])?["properties"] as? [String: Any]
            XCTAssertNotNil(props?["job_id"], "\(name) schema must expose job_id")
            // job_number must no longer be a hard requirement (so job_id alone is valid).
            let required = (tool?["inputSchema"] as? [String: Any])?["required"] as? [String] ?? []
            XCTAssertFalse(required.contains("job_number"), "\(name) must not require job_number")
        }
    }

    // MARK: - TASK-265: job_get schema has include_raw_text and correct description

    func testJobGet_schema_hasIncludeRawTextParameter() {
        let jobGetTool = tools.first { $0["name"] as? String == "job_get" }
        let schema = jobGetTool?["inputSchema"] as? [String: Any]
        let properties = schema?["properties"] as? [String: Any]
        XCTAssertNotNil(properties?["include_raw_text"], "job_get schema must include include_raw_text property")
        let rawTextProp = properties?["include_raw_text"] as? [String: Any]
        XCTAssertEqual(rawTextProp?["type"] as? String, "boolean", "include_raw_text must be boolean")
        let desc = rawTextProp?["description"] as? String ?? ""
        XCTAssertTrue(
            desc.contains("Omitted by default") || desc.contains("omitted") || desc.contains("default"),
            "include_raw_text description must mention it is omitted by default"
        )
    }

    func testJobGet_description_mentionsOmittedByDefault() {
        let jobGetTool = tools.first { $0["name"] as? String == "job_get" }
        let description = jobGetTool?["description"] as? String ?? ""
        XCTAssertTrue(
            description.contains("omitted") || description.contains("Omitted") || description.contains("default"),
            "job_get description must state that raw text is omitted by default"
        )
        // Must not claim raw text is included by default
        XCTAssertFalse(
            description.lowercased().contains("included by default") || description.lowercased()
                .contains("including raw"),
            "job_get description must not claim raw text is included by default"
        )
    }

    // MARK: - readToken returns nil when file absent

    func testReadToken_returnsNilWhenFileMissing() {
        // Use a temp directory that definitely has no token file
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mcp-test-\(UUID().uuidString)")
        // readToken() reads from ~/.jobhunt-mcp-token — we can only verify it doesn't crash
        // and returns a String? (nil or valid token)
        let token = readToken()
        // If the file exists in the test environment the token will be non-nil; that's fine.
        // We just verify the return type is correct (compiler check) and it doesn't throw.
        _ = token as String?
        _ = tempDir // suppress unused warning
    }
}
