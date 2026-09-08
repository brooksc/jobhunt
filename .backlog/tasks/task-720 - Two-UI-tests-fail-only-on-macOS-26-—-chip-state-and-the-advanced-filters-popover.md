---
id: TASK-720
title: >-
  Two UI tests fail only on macOS 26 — chip state and the advanced-filters
  popover
status: To Do
assignee: []
created_date: '2026-09-08 17:55'
labels: []
dependencies: []
priority: high
type: bug
ordinal: 105000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Surfaced by the 2026-09-08 scheduled `ui-tests.yml` run on `dcd660e8`. Two tests fail, each on all three attempts (6 failures across 42 executions):

```
BehaviorUITests.swift:221  testDataQualityFilterChipAccessibleState
  XCTAssertTrue failed - Extraction pending chip should report 'on' after activation

SavedSearchUITests.swift:42  testSelectingSavedSearchAfterSessionFilterStaysActive
  XCTAssertTrue failed - Remote filter toggle should appear in the popover.
```

**These were invisible until this run.** The workflow piped xcodebuild through `tail -80`, which dropped the failing test names — the 2026-09-07 run reported the same "42 tests, 6 failures" and refused to say which. Fixed in dcd660e8; this task exists because that fix immediately produced names.

## The environment split is the whole story

| | OS | Xcode | Result |
|---|---|---|---|
| CI (`macos-latest`) | **26.6.2** | 26.6 | both fail, 3/3 attempts |
| Tart VM (`run-ui-tests-in-vm.sh`) | 15.7.3 | 26.4.1 | both pass |

Same commit, same tests. So this is a macOS-version behaviour difference, not flakiness — 3/3 attempts is deterministic.

## What is unresolved, and why it needs a human

Both assertions concern state XCUITest *observes* rather than logic the app computes:

1. A chip's accessibility `value` flipping `"off"` → `"on"` when clicked. macOS 26 may report a selected toggle differently (a different attribute, or `"1"`/`"0"`), in which case the control works and only the test's expectation is wrong. **Or** the chip genuinely no longer reports its state, which is a real VoiceOver regression on the newest macOS.
2. `filter.remote.remote` appearing in the Advanced-filters popover within 5s. Could be popover timing/presentation changes on macOS 26 — **or** the popover genuinely doesn't show that control there any more, which is a functional bug.

**Neither can be settled from this machine** (macOS 27 beta) or the VM (macOS 15). Nobody here has a macOS 26 box.

## The cheapest way to resolve it — 30 seconds by hand

On any Mac running the app, no tooling required:

1. Jobs screen → click **Advanced filters** in the toolbar. **Does a "Remote" toggle appear in the popover?**
2. Data Quality screen → click a filter chip. **Does it visibly become selected?**

If both behave correctly, these are test-environment artifacts and the fix is to the assertions (match how macOS 26 reports selection; give the popover a longer or more specific wait). If either misbehaves, it is a product bug on current macOS and matters far more than the test.

## Release relevance

The app targets macOS 15+, so macOS 26 users are real. Judge after the manual check above: an accessibility-reporting difference is not release-blocking; a popover that genuinely fails to show its controls is.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The manual check records whether each control actually works on current macOS, before any code changes
- [ ] #2 If the controls work, the assertions are corrected to match how macOS 26 reports selection and popover presentation
- [ ] #3 If either control is genuinely broken, the product bug is fixed and takes priority over the test
- [ ] #4 Both tests pass on the macos-latest runner and continue to pass in the macOS 15 VM
<!-- AC:END -->
