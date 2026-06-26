---
id: TASK-553
title: >-
  Render Debug tab recent errors with the same redaction used for copied
  diagnostics
status: Done
assignee: []
created_date: '2026-06-19 23:00'
updated_date: '2026-06-26 00:50'
labels:
  - audit
  - privacy
  - diagnostics
  - ui
dependencies: []
references:
  - 'app/Views/Settings/DebugTab.swift:141'
  - 'app/Views/Settings/DebugTab.swift:212'
  - 'app/Views/Components/ToastView.swift:22'
modified_files:
  - app/Views/Settings/DebugTab.swift
  - app/Views/Components/ToastView.swift
  - tests/CoreTests/DiagnosticsRedactorTests.swift
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Finding: copied diagnostics redacts recent toast errors before placing them on the pasteboard (`app/Views/Settings/DebugTab.swift:212`), but the on-screen Recent Errors section renders the raw `record.message` (`app/Views/Settings/DebugTab.swift:141`). `ToastStore` stores whatever error text callers pass, including many `error.localizedDescription` values (`app/Views/Components/ToastView.swift:22`).

Why important: the Debug tab is a support surface. Even if Copy Diagnostics is redacted, users may screenshot the tab, screen-share it, or manually copy visible text when seeking help. Raw localized errors can include local file paths, URL query strings, or provider fragments. The lower-risk local display does not need to expose more than the copied diagnostics path.

Suggested implementation: render `DiagnosticsRedactor.redact(record.message)` in the Recent Errors section, or store both raw and redacted forms if the raw message is still needed elsewhere. Prefer redacting at display time to keep existing toast behavior unchanged. Add a focused UI/helper test if the section formatting is extracted; otherwise rely on `DiagnosticsRedactorTests` plus a small helper around recent-error formatting.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The Debug tab Recent Errors section no longer displays unredacted file paths, URL query strings, or recognized secret tokens.
- [x] #2 Toast popups continue to show their existing user-facing messages during normal app use.
- [x] #3 Copied diagnostics and on-screen recent-error formatting use the same redaction behavior for sensitive classes.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
The Debug tab's on-screen Recent Errors section now renders DiagnosticsRedactor.redact(record.message), matching the Copy Diagnostics path — so a screenshot/screen-share can't leak file paths, URL queries, or tokens. Toast popups during normal use are unchanged (redaction is display-time only, in the Debug tab). Commit 456ec97.
<!-- SECTION:FINAL_SUMMARY:END -->
