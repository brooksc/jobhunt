---
id: TASK-365
title: >-
  Debug tab: Use lightweight count/stat queries instead of materializing whole
  tables
status: Done
assignee: []
created_date: '2026-06-12 22:03'
updated_date: '2026-06-15 19:40'
labels:
  - audit
  - performance
  - diagnostics
  - swiftdata
dependencies: []
references:
  - app/Views/Settings/DebugTab.swift
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
DebugTab queries all jobs, captures, resumes, sites, and LLM requests only to display counts and status summaries.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Debug stats use count/projection queries or a diagnostic service instead of loading entire tables into SwiftUI.
- [ ] #2 Job status, extraction status, and LLM queue counts remain accurate.
- [ ] #3 The support diagnostics path still works after replacing full-table @Query usage.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Closed as not-needed-at-scale (maintainer guidance; see CLAUDE.md "Don't over-optimize for scale this app won't reach"). DebugTab materializes a few hundred jobs/captures/resumes/sites/LLM requests purely to show counts — at the real scale (a few hundred rows) that is imperceptible and not worth count-query/projection complexity. The counts are already accurate (AC#2) and the diagnostics path works (AC#3). No change made; revisit only if a measured problem appears at much larger scale.
<!-- SECTION:FINAL_SUMMARY:END -->
