---
id: TASK-718
title: >-
  The rest of the screenshot tour still asserts nothing — TASK-716 only fixed
  the Settings tabs
status: To Do
assignee: []
created_date: '2026-09-05 02:24'
labels: []
dependencies: []
priority: medium
type: bug
ordinal: 103000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-716 fixed the Settings portion of `ScreenshotTests` — those captures now go through `captureSettingsTab(_:showing:as:)`, which asserts the window title changed *and* that a control unique to the pane is present, and refuses to write a PNG whose assertion failed.

**The other 13 tests in the same file were not converted** and remain `navigate(app, label:)` + `snap(app, name)` with no assertion of any kind:

```swift
func test01_Dashboard() {
    navigate(app, label: "Dashboard")
    snap(app, "01-dashboard")
}
```

If `navigate` silently fails — which is exactly what `clickSettingsTab` was doing, matching on an attribute that was always empty — the test captures whatever screen happened to be showing and passes. That is the identical failure TASK-716 was filed for, in the same file, found by grepping for test functions containing no assertion.

Affected: `test01_Dashboard`, `test03_JobsAllWithDetail`, `test07_JobsPursuingSidebar`, `test08_JobsAppliedSidebar`, `test09_JobsPassedSidebar`, `test10_NeedsAction`, `test11_SitesList`, `test12_SitesWithDetail`, `test13_Duplicates`, `test14_LLMQueue`, `test15_DataQuality`, plus `JobsScreenUITests.testSidebarPursuingFilters`.

## Fix

Give the non-Settings captures the same treatment: a `capture(screen:showing:as:)` helper that asserts a control unique to that screen is present before writing the PNG. `captureSettingsTab` is the working model — reuse its shape rather than inventing a second one.

**Verify the way TASK-716 was verified: look at the images, not the exit code.** A suite that goes green without the screenshots changing means the assertions were written loosely enough to pass.

## Not release-blocking

This is test infrastructure. The screens themselves work for a human — the marketing screenshots come from the same views and are visibly correct. The cost is that the tour cannot currently *prove* a navigation regression, not that one exists.

## Worth doing at the same time

A mechanical check for test functions containing no assertion would have caught both this and TASK-716. Two legitimate exceptions exist and must be allowed: `SchemaEvolutionTests.testSchemaV1StoredProperty*` (compile-time tripwires) and `NormalizationTests.testRepeatedParametersOnAnyHost` (the assertion is that it returns at all — these inputs used to abort the process). Both say so in comments, so an allowlist is honest rather than a fudge.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Every ScreenshotTests capture asserts a control unique to its screen before the PNG is written
- [ ] #2 The screenshots are inspected by eye and show the correct distinct screen, not just a green run
- [ ] #3 JobsScreenUITests.testSidebarPursuingFilters asserts the filter actually applied
- [ ] #4 A mechanical check flags a test function with no assertion, with a documented allowlist for the deliberate tripwires
<!-- AC:END -->
