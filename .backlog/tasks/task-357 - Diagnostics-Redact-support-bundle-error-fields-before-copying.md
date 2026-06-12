---
id: TASK-357
title: 'Diagnostics: Redact support bundle error fields before copying'
status: To Do
assignee: []
created_date: '2026-06-12 21:47'
labels:
  - audit
  - privacy
  - diagnostics
dependencies: []
references:
  - app/Views/Settings/DebugTab.swift
  - app/Views/Components/ToastView.swift
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The Debug tab labels Copy Diagnostics as privacy-safe, but the generated bundle includes serverError and recent ToastStore error messages verbatim. Those strings come from arbitrary localizedDescription values and can include file paths, URLs, provider details, or future user/job text.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Support diagnostics pass all error fields through a central redaction or safe-error formatter before copying.
- [ ] #2 Regression tests prove diagnostics do not include local paths, tokens, raw provider bodies, URLs requiring redaction, or raw job/resume text.
- [ ] #3 The Debug tab copy/help text accurately describes the privacy boundary.
<!-- AC:END -->
