---
id: TASK-244
title: 'Resume management: Stop swallowing add/update/delete persistence errors'
status: Done
assignee: []
created_date: '2026-06-12 02:02'
updated_date: '2026-06-12 02:25'
labels:
  - resumes
  - error-handling
  - recovery
dependencies: []
references:
  - app/Views/Settings/ResumesTab.swift
  - core/Services/ResumeService.swift
  - tests/CoreTests/ResumeServiceTests.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
ResumesTab uses try? for add, update, and delete operations. If persistence fails, the UI dismisses or proceeds without visible feedback. Surface these errors and avoid dismissing edit UI until save succeeds.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Resume add/update/delete failures are displayed to the user.
- [ ] #2 Edit sheets do not dismiss until save succeeds or the user cancels.
- [ ] #3 Delete failures leave the resume visible and report the error.
- [ ] #4 Focused tests or UI checks cover at least one failed resume persistence path.
<!-- AC:END -->
