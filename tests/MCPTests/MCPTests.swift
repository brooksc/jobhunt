// MCPHelpers.swift is compiled directly into this test bundle (JobhuntMCP is a tool, not a framework).
import JobhuntCore
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

    /// TASK-559 AC#3: the add_capture schema documents every accepted structured-data shape, so MCP
    /// clients know they can send either the typed string or the raw array (matching /captures).
    func testAddCapture_schema_exposesBothStructuredDataShapes() {
        let addCapture = tools.first { $0["name"] as? String == "add_capture" }
        let props = (addCapture?["inputSchema"] as? [String: Any])?["properties"] as? [String: Any]
        XCTAssertNotNil(props?["structured_data_json"], "schema must document structured_data_json")
        XCTAssertNotNil(props?["structured_data"], "schema must document the raw structured_data array")
        let arraySchema = props?["structured_data"] as? [String: Any]
        XCTAssertEqual(arraySchema?["type"] as? String, "array")
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

    // MARK: - readToken (shared policy via MCPTokenManager — TASK-531)

    // Exercised through the helper-facing API via its URL seam, never the production token path.

    private func tokenTempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("mcp-token-test-\(UUID().uuidString)")
    }

    func testReadToken_returnsNilWhenFileMissing() {
        let url = tokenTempURL()
        XCTAssertNil(readToken(at: url), "missing token file must read as nil (helper fails closed)")
    }

    func testReadToken_returnsTokenForOwnerOnlyFile() throws {
        let url = tokenTempURL()
        defer { MCPTokenManager.delete(at: url) }
        let written = try MCPTokenManager.generateAndWrite(at: url)
        XCTAssertEqual(readToken(at: url), written, "owner-only (0600) token must be readable")
    }

    func testReadToken_rejectsGroupOrWorldReadableFile() throws {
        let url = tokenTempURL()
        defer { MCPTokenManager.delete(at: url) }
        try "tok".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
        XCTAssertNil(readToken(at: url), "group/world-readable token must be rejected")
    }

    // MARK: - shouldRefreshMCP (token/port refresh trigger — TASK-629)

    func testShouldRefreshMCP_triggersOn401() {
        // A 401 = the app rotated the token on relaunch; refresh + retry (we reached the server).
        XCTAssertTrue(shouldRefreshMCP(status: 401, hasBody: true))
        XCTAssertTrue(shouldRefreshMCP(status: 401, hasBody: false))
    }

    func testShouldRefreshMCP_triggersOnBodylessServerError() {
        // Connection refused (app moved ports / down) surfaces as a bodyless 5xx from postMCP.
        XCTAssertTrue(shouldRefreshMCP(status: 500, hasBody: false))
        XCTAssertTrue(shouldRefreshMCP(status: 503, hasBody: false))
    }

    func testShouldRefreshMCP_doesNotTriggerOnNormalOrAppErrors() {
        XCTAssertFalse(shouldRefreshMCP(status: 200, hasBody: true), "success never refreshes")
        XCTAssertFalse(shouldRefreshMCP(status: 400, hasBody: true), "a real 4xx (bad args) is not a stale token")
        XCTAssertFalse(shouldRefreshMCP(status: 404, hasBody: true), "not-found is not a token/port problem")
        XCTAssertFalse(shouldRefreshMCP(status: 500, hasBody: true), "a server error WITH a body reached the app")
    }
}
