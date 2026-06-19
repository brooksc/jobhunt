---
id: TASK-540
title: >-
  AppUITests: MockLLM test can't reach the ⌘, Settings window in --llm-mock-port
  launch
status: To Do
assignee: []
created_date: '2026-06-19 06:29'
labels:
  - test-infra
  - ui-tests
  - llm
dependencies: []
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
MockLLMUITests.testLLMTestConnection_succeedsAgainstMockServer is currently skipped (XCTSkipIf) because, in the --llm-mock-port launch mode, the app does not surface the standard ⌘, Settings window to XCUITest — the Settings tab radio buttons never appear.

Investigated thoroughly (7 attempts): ⌘, with retries, the app-menu "Settings…" item, and forcing window focus by clicking a sidebar element all fail to open Settings; launching with seedData:false (idle queue) also didn't help. Meanwhile the IDENTICAL Settings UI opens reliably in every non-mock test: ScreenshotTests test16/16b/17/17b/18 (General/Jobs/AI/Data/Debug tabs) and BehaviorUITests.testCommandCommaOpensSettingsWindow all pass. The only launch difference is the --llm-mock-port argument (which sets provider=lmstudio/baseURL=mock/model=mock-model and llmQueuePaused=false). So this is a test-infra interaction specific to the mock launch, NOT a product regression.

Coverage is not lost: the Settings window + AI tab are exercised by the ScreenshotTests settings tour + the behavior test, and the provider→HTTP→parse path (the test's real purpose) is covered by CoreTests.MockLLMInferenceTests (testQueuePipeline_extractsJobViaMockServer, testExtraction_overLocalhostMock_*, testFitScoring_overLocalhostMock_*), which run in the fast gate.

To fix: determine why the mock-port launch prevents XCUITest from reaching the Settings scene (candidate causes: the in-process MockLLMServer/HTTP interaction, app activation/key-window state under that launch, or the unpaused-queue + mock provider keeping the main actor busy). Possibly add a launch argument to open Settings deterministically for the test, or split the assertion so it doesn't depend on opening Settings via the chrome. Re-enable the test (remove the XCTSkipIf in MockLLMUITests.swift).

References: tests/AppUITests/MockLLMUITests.swift, tests/AppUITests/AppUITests.swift (launchApp), app/JobhuntApp.swift (--llm-mock-port handling), tests/Support/MockLLM/*.swift, tests/CoreTests/MockLLMInferenceTests.swift (the unit-level coverage that remains).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Root cause of why --llm-mock-port launch prevents reaching the ⌘, Settings window in XCUITest is identified
- [ ] #2 MockLLMUITests.testLLMTestConnection_succeedsAgainstMockServer reliably opens Settings, selects the AI tab, and asserts Test Connection success against the mock server
- [ ] #3 The XCTSkipIf guard is removed and the test passes in a full AppUITests run
- [ ] #4 No regression to the other AppUITests
<!-- AC:END -->
