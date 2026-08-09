---
id: TASK-502
title: >-
  Needs Action: custom snooze date + cost-estimate clarity + invalid-price
  validation
status: Done
assignee: []
created_date: '2026-06-18 23:06'
updated_date: '2026-08-09 23:09'
labels:
  - ux
  - settings
  - needs-action
dependencies: []
modified_files:
  - core/Services/PriceInput.swift
  - core/Services/SnoozeDefaults.swift
  - app/Views/Settings/SettingsView.swift
  - app/Views/Needs/NeedsActionView.swift
  - tests/CoreTests/PriceInputAndSnoozeTests.swift
priority: low
ordinal: 21000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Bundle of smaller punted review items:

#11 — Snooze only offers fixed intervals (3d/1w/2w/1mo); add a "Custom date…" option opening a DatePicker (NeedsActionView.swift snooze menu).

#15 — LLM Cost Estimate is opaque: based on hidden assumptions (≈8K-char descriptions, fixed overhead). Add help text explaining the estimate is an average ("actual cost depends on model + résumé size; check your provider's pricing"), and validate the Cost-Pricing input fields — typing a non-number silently drops the value with no error; show a red "enter a number" and don't lose focus state.

References: app/Views/Needs/NeedsActionView.swift, app/Views/Settings/SettingsView.swift (Cost Pricing / Cost Estimate), core/.../CostEstimator.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Snooze menu has a Custom date option (DatePicker)
- [x] #2 Cost estimate shows help text clarifying it's an average / not a bill
- [x] #3 Invalid cost-price input shows an inline error and isn't silently dropped
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
#1 "Custom date…" opens a graphical DatePicker popover on the snooze menu. It converts to a day count via `SnoozeDefaults.days(until:)` and calls the existing `onSnooze(days:)` rather than adding a second write path that could drift from the fixed intervals. Counted by calendar day, not elapsed hours — picking tomorrow morning at 11pm is 0.6 days and would truncate to 0, snoozing the action to right now. Past dates floor to 1 rather than erroring.

#2 The estimate section now says it's an average over an assumed description length and the entered prices, and points at the provider's dashboard for actual charges.

#3 `PriceInput.parse` returns the value or a reason (`notANumber` / `negative`), shown inline under the field; `savePrices()` writes only what parses, so the typed text stays on screen under its error and the stored price is left alone. Blank is valid-but-absent, not an error — clearing a field is normal mid-edit and flagging it would put a red error under whichever field the user is working in. Also rejects `inf`, which parses as a Double and would render as a nonsense estimate.

10 tests. Gate: fast gate TEST SUCCEEDED, BUILD SUCCEEDED, swiftlint 0 violations in 325 files, swiftformat 0.61.1 clean.

not verified: (visual) — popover sizing/placement and the inline error's appearance in the Settings form. Model-level behaviour is tested.
<!-- SECTION:FINAL_SUMMARY:END -->
