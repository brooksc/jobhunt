---
id: TASK-367
title: 'Job lookup: Replace all-capture URL scan with indexed/predicate lookup'
status: To Do
assignee: []
created_date: '2026-06-12 22:03'
labels:
  - audit
  - performance
  - server
  - swiftdata
dependencies: []
references:
  - core/Services/JobService.swift
  - core/Models/Capture.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
findJobNumber(byURL:) fetches every Capture and searches in memory for a matching URL. This is a hot extension/server lookup path that should scale with indexed or predicate-based URL fields.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 URL and canonical URL lookup use normalized predicate-friendly fields with fetch limits.
- [ ] #2 The lookup handles existing URL/canonical matching behavior without regressions.
- [ ] #3 Tests cover duplicate/legacy URL cases and large capture history.
<!-- AC:END -->
