---
id: TASK-357
title: 'Diagnostics: Redact support bundle error fields before copying'
status: Done
assignee: []
created_date: '2026-06-12 21:47'
updated_date: '2026-06-15 05:48'
labels:
  - audit
  - privacy
  - diagnostics
dependencies: []
references:
  - app/Views/Settings/DebugTab.swift
  - app/Views/Components/ToastView.swift
modified_files:
  - core/Diagnostics/DiagnosticsRedactor.swift
  - app/Views/Settings/DebugTab.swift
  - tests/CoreTests/DiagnosticsRedactorTests.swift
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The Debug tab labels Copy Diagnostics as privacy-safe, but the generated bundle includes serverError and recent ToastStore error messages verbatim. Those strings come from arbitrary localizedDescription values and can include file paths, URLs, provider details, or future user/job text.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Support diagnostics pass all error fields through a central redaction or safe-error formatter before copying.
- [x] #2 Regression tests prove diagnostics do not include local paths, tokens, raw provider bodies, URLs requiring redaction, or raw job/resume text.
- [x] #3 The Debug tab copy/help text accurately describes the privacy boundary.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
The recent-toast-errors already went through redaction, but appServices.serverError was interpolated verbatim into the diagnostics bundle. Centralized the redaction regexes into a testable JobhuntCore type (DiagnosticsRedactor.redact) — previously a private func in the DebugTab view — and routed BOTH serverError and recentErrors through it (AC#1). Added CoreTests proving file paths (/Users,/var,/private,/tmp), URL query strings, and Bearer/OpenAI(sk-)/Google(AIza) keys are redacted while benign text is untouched (AC#2). Diagnostics never include raw job/resume text (buildDiagnosticsText only emits system info, counts, and redacted error strings). Updated the Copy Diagnostics help text to accurately describe the best-effort redaction and to advise reviewing before sharing (AC#3).
<!-- SECTION:FINAL_SUMMARY:END -->
