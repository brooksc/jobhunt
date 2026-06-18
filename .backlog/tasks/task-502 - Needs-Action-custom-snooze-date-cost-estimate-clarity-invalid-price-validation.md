---
id: TASK-502
title: >-
  Needs Action: custom snooze date + cost-estimate clarity + invalid-price
  validation
status: To Do
assignee: []
created_date: '2026-06-18 23:06'
labels:
  - ux
  - settings
  - needs-action
dependencies: []
priority: low
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
- [ ] #1 Snooze menu has a Custom date option (DatePicker)
- [ ] #2 Cost estimate shows help text clarifying it's an average / not a bill
- [ ] #3 Invalid cost-price input shows an inline error and isn't silently dropped
<!-- AC:END -->
