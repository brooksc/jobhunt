---
id: TASK-486
title: Mock OpenAI-compatible LLM server for keyless AI-path testing
status: In Progress
assignee: []
created_date: '2026-06-18 17:31'
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
- [ ] #1 A localhost server speaks /v1/chat/completions + /v1/models and returns valid extraction/fit JSON the engine parses
- [ ] #2 Responses are lightly input-aware (extraction echoes the captured page title/company)
- [ ] #3 Automated tests exercise the real provider→transport→engine path (and the QueueActor→store pipeline) over a socket with no key
- [ ] #4 The app can be pointed at the mock in UI tests (--llm-mock-port, uiTest-gated) and a UI test verifies the AI wiring
- [ ] #5 Mock sources are test-only — not shipped in the app bundle
<!-- AC:END -->
