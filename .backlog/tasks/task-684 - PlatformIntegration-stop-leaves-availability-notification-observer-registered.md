---
id: TASK-684
title: PlatformIntegration stop leaves availability notification observer registered
status: Done
assignee: []
created_date: '2026-08-21 20:26'
updated_date: '2026-08-22 03:43'
labels:
  - bug
  - notifications
  - lifecycle
  - macos
dependencies: []
references:
  - TASK-429
  - app/Platform/PlatformIntegration.swift
modified_files:
  - app/Platform/PlatformIntegration.swift
priority: low
type: bug
ordinal: 58000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Lifecycle regression found during the 2026-08-21 code review. PlatformIntegration registers both availability notification observers at start, but stop removes only one. The remaining observer can fire while integration is stopped, and a later restart adds a duplicate registration so one event invokes the handler more than once.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Stopping PlatformIntegration removes the jobs-maybe-unavailable observer
- [ ] #2 No availability notification callback runs while PlatformIntegration is stopped
- [ ] #3 A stop followed by start registers exactly one callback for each availability notification
- [ ] #4 Repeated stop and start cycles do not accumulate observers
- [ ] #5 Focused lifecycle coverage posts the notification before stop, while stopped, and after restart
<!-- AC:END -->
