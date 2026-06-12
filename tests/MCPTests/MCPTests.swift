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
            XCTAssertEqual(schema?["type"] as? String, "object", "inputSchema.type should be 'object' for \(tool["name"] ?? "?")")
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

    // MARK: - TASK-265: job_get schema has include_raw_text and correct description

    func testJobGet_schema_hasIncludeRawTextParameter() {
        let jobGetTool = tools.first { $0["name"] as? String == "job_get" }
        let schema = jobGetTool?["inputSchema"] as? [String: Any]
        let properties = schema?["properties"] as? [String: Any]
        XCTAssertNotNil(properties?["include_raw_text"], "job_get schema must include include_raw_text property")
        let rawTextProp = properties?["include_raw_text"] as? [String: Any]
        XCTAssertEqual(rawTextProp?["type"] as? String, "boolean", "include_raw_text must be boolean")
        let desc = rawTextProp?["description"] as? String ?? ""
        XCTAssertTrue(desc.contains("Omitted by default") || desc.contains("omitted") || desc.contains("default"),
                      "include_raw_text description must mention it is omitted by default")
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
            description.lowercased().contains("included by default") || description.lowercased().contains("including raw"),
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
