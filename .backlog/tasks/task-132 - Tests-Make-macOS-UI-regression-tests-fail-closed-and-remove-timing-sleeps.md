---
id: TASK-132
title: 'Tests: Make macOS UI regression tests fail closed and remove timing sleeps'
status: Done
assignee: []
created_date: '2026-06-11 03:26'
updated_date: '2026-06-11 19:35'
labels:
  - tests
  - ui
  - macos
  - accessibility
  - flakiness
dependencies: []
references:
  - tests/AppUITests/AppUITests.swift
  - tests/AppUITests/BehaviorUITests.swift
  - tests/AppUITests/ScreenshotTests.swift
  - tests/AppUITests/JobsScreenUITests.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Current UI tests include screenshot tours and behavior tests, but some behavior checks return successfully when controls are missing and many interactions rely on fixed Thread.sleep delays. Harden these tests so they fail when named controls are absent and wait on actual UI state changes.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Behavior tests fail when required controls such as filter chips are absent instead of returning successfully.
- [ ] #2 Fixed sleeps in shared launch/navigation helpers are replaced with state-based waits where feasible.
- [ ] #3 Screenshot tests remain visual artifacts, but critical screens have semantic assertions for selected state, visible controls, or detail-pane content.
- [ ] #4 UI tests produce actionable failure messages for missing controls and failed navigation.
- [ ] #5 A local or VM run command for the hardened UI tests is documented.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Added waitUntil() polling helper to AppUITests.swift. Replaced all Thread.sleep calls in launchApp() and navigate() with state-based waits (sidebar.dashboard existence, btn.isSelected). Filter chip guard-and-return blocks in BehaviorUITests.swift changed to XCTAssertTrue(...) so missing chips fail the test instead of silently skipping. Command-key sleeps replaced with waitUntil on window count / waitForExistence. clickSettingsTab() uses waitUntil{btn.isSelected} instead of sleep. ScreenshotTests detail-pane clicks wait on staticTexts.count. test02_JobsAll gains a sidebar selected-state assertion. Run command documented at top of AppUITests.swift.
<!-- SECTION:FINAL_SUMMARY:END -->
