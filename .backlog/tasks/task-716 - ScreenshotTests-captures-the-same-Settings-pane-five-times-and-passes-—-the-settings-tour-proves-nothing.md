---
id: TASK-716
title: >-
  ScreenshotTests captures the same Settings pane five times and passes — the
  settings tour proves nothing
status: To Do
assignee: []
created_date: '2026-09-04 17:39'
labels: []
dependencies: []
priority: high
type: bug
ordinal: 101000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found 2026-09-04 while root-causing the `MockLLMUITests` failure. **Verified from artifacts of a real VM run** (`local-screenshots/2026-09-04_17-18-21/`).

`CLAUDE.md` describes `ScreenshotTests` as a "visual tour of every view and settings tab (General/Jobs/AI/Data/Search/Debug)". It isn't. The run produced:

- `16-settings-general.png`
- `16b-settings-jobs.png` → **shows General**
- `17-settings-ai.png` → **shows General**
- `17b-settings-data.png`
- `18-settings-debug.png` → **shows General**

Three confirmed by eye; title bar reads "General" and the General tab is selected in each. The MD5s differ, but only by pixel-level rendering noise — the content is the same pane.

**The suite passes anyway, because it never asserts what it captured.** `ScreenshotTests.swift` contains exactly one `XCTAssert` in the whole file. A screenshot test that cannot fail on content is worse than no test: it is cited in `CLAUDE.md` as coverage for the settings UI, and it was the reason TASK-540 argued "coverage is not lost" when the MockLLM test was skipped. That argument was resting on nothing.

## Root cause

XCUITest clicks on the macOS Settings `TabView` do not switch panes. The same interaction failure makes `MockLLMUITests.testLLMTestConnection_succeedsAgainstMockServer` fail — it clicks the "AI" tab and the pane never changes. `MockLLMUITests.swift:37` already hints at the difficulty: "TabView's accessibility role varies by macOS release, so identify the tab by its label."

**This is not a product defect.** Settings tabs work correctly for a human — confirmed against a user screenshot of the Search tab rendering normally. The app is fine; the test harness cannot drive the control.

## Fix

1. **Assert the pane, not just the click.** Each settings screenshot step must verify it is on the tab it claims — a control unique to that pane, or the window title. This will turn the suite red until (2) is done, which is correct: it is red today and lying about it.
2. **Make the tab click work.** The Settings `TabView` renders as a toolbar-style control whose accessibility role varies by macOS version; `.buttons`/`.radioButtons`/`.toolbars.buttons` should be tried explicitly rather than `descendants(matching: .any)` with a label predicate, which is what silently matches something non-interactive today.
3. Consider driving tab selection deterministically through a launch argument, as TASK-540 suggested, so the tour does not depend on hitting a moving accessibility target at all.

Related: [[TASK-540]] should be reopened — it was marked Done claiming "30 AppUITests passed with 0 failures", and its `MockLLMUITests` test fails 3/3 iterations today on both CI and a clean macOS 15.7.3 VM.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Each settings screenshot step asserts it is on the intended tab before capturing
- [ ] #2 Clicking a Settings tab in XCUITest switches the pane, verified by that assertion
- [ ] #3 The five settings screenshots show five different panes
- [ ] #4 MockLLMUITests either passes or is skipped with an honest, current reason
- [ ] #5 TASK-540 is reopened or superseded rather than left Done
<!-- AC:END -->
