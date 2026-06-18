---
id: TASK-486
title: Mock OpenAI-compatible LLM server for keyless AI-path testing
status: Done
assignee: []
created_date: '2026-06-18 17:31'
updated_date: '2026-06-18 17:33'
labels:
  - testing
  - llm
  - infrastructure
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Provide a localhost server that implements the OpenAI-style API (/v1/chat/completions, /v1/models) and returns deterministic, lightly input-aware extraction + fit-score JSON, so automated and UI tests can exercise the AI inference path with no real provider or API key.

Implemented as shared test-support sources (tests/Support/MockLLM/) compiled into CoreTests and AppUITests — a real NWListener loopback server, never shipped in the app:
- CoreTests: engine-level (ExtractionEngine.extract/scoreFit over the socket) + full QueueActor pipeline (enqueue→drain→provider→mock→store) + responder unit tests.
- AppUITests: the app is pointed at the runner-hosted mock via --llm-mock-port (uiTest mode only); a UI test drives Settings → LLM → Test Connection against it.

References: tests/Support/MockLLM/MockLLMResponder.swift, tests/Support/MockLLM/MockLLMServer.swift, tests/CoreTests/MockLLMInferenceTests.swift, tests/AppUITests/MockLLMUITests.swift, app/JobhuntApp.swift.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A localhost server speaks /v1/chat/completions + /v1/models and returns valid extraction/fit JSON the engine parses
- [x] #2 Responses are lightly input-aware (extraction echoes the captured page title/company)
- [x] #3 Automated tests exercise the real provider→transport→engine path (and the QueueActor→store pipeline) over a socket with no key
- [x] #4 The app can be pointed at the mock in UI tests (--llm-mock-port, uiTest-gated) and a UI test verifies the AI wiring
- [x] #5 Mock sources are test-only — not shipped in the app bundle
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
A localhost OpenAI-compatible mock server now lets automated AND UI tests exercise the full AI inference path with no provider key.

**Mock (test-support, never shipped — AC#5):** `tests/Support/MockLLM/`
- `MockLLMResponder.swift` (pure): classifies a request as extraction vs fit by `response_format.json_schema.name` (fallback: prompt keywords); returns valid structured JSON the engine parses; **input-aware** — echoes the captured "Page title: …" into the extraction's title/company (AC#2); fit JSON carries exactly the 5 `FitScorer` dimensions so validation passes.
- `MockLLMServer.swift`: minimal HTTP/1.1 over an NWListener loopback ephemeral port, serving `/v1/chat/completions` + `/v1/models` (AC#1). Compiled into CoreTests and AppUITests via Project.swift; not in the app bundle.

**Automated (CoreTests, 11 tests — AC#3):** `MockLLMInferenceTests` drives a real `LMStudioProvider` over the socket through `ExtractionEngine.extract`/`scoreFit` (asserts echoed title/company + 5 fit dimensions) and through the full `QueueActor` pipeline (enqueue → drain → provider → mock → `BackgroundStore`, asserting the Job is written `.succeeded` with the echoed fields). `MockLLMResponderTests` covers the pure logic. All green in the fast gate.

**UI (AppUITests — AC#4):** `JobhuntApp` reads `--llm-mock-port` (uiTest-gated) and points the LLM at lmstudio → the mock + unpauses the queue; `launchApp(llmMockPort:)` passes the runner-hosted server's port. `MockLLMUITests` launches the app against the mock and asserts Settings → LLM → Test Connection succeeds (new `llm.connection.success` accessibility id). **Verified in the Tart VM: passed (23.7s).**

Also added `jobContextMenu.reextract` accessibility id for future extraction-trigger UI tests. Scope note: packaged as test-compiled sources (no standalone CLI / product target), per the steer that the core use is automated + UI tests — the XCUITest runner hosts the server and the app connects over loopback.
<!-- SECTION:FINAL_SUMMARY:END -->
