---
id: TASK-365
title: >-
  Debug tab: Use lightweight count/stat queries instead of materializing whole
  tables
status: To Do
assignee: []
created_date: '2026-06-12 22:03'
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
