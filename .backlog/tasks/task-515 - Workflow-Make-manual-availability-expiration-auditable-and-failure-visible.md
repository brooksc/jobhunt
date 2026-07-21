---
id: TASK-515
title: 'Workflow: Make manual availability expiration auditable and failure-visible'
status: To Do
assignee: []
created_date: '2026-06-19 01:31'
updated_date: '2026-07-21 22:59'
labels:
  - workflow
  - availability
  - auditability
dependencies: []
references:
  - app/ContentView.swift
  - app/Views/Settings/SettingsTab.swift
  - core/Services/JobService.swift
  - core/Services/AvailabilityChecker.swift
  - tests/CoreTests/JobServiceTests.swift
priority: medium
ordinal: 9000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Finding: Manual availability checks in `ContentView` and `SettingsTab` ask the user to confirm gone postings, then call `JobService.markExpired`. That service bulk-updates `Job.status` directly without the status-change `JobEvent` that `setStatus` records. The Settings path also uses `try?` and immediately reports success, so a failure can be silently presented as "marked expired".

Why this matters: Expiration is a terminal workflow decision. Users need the job timeline to explain why a job became expired, and the app should not report success if the confirmed status change failed.

Suggested implementation: Route manual expiration through the same status-event path as other status changes, or have `markExpired` record explicit status/availability events for each job. Update Settings availability confirmation to await the result and surface errors like the toolbar path already does.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Manually confirming expired jobs records an auditable event for each affected job, consistent with other status changes or with clear availability-specific context.
- [ ] #2 The Settings availability confirmation path does not swallow `markExpired` failures and does not show a success message before the operation succeeds.
- [ ] #3 The toolbar/service-menu manual availability path keeps its existing success/error feedback behavior.
- [ ] #4 Bulk expiration remains safe for multiple jobs and preserves duplicate/status invariants handled by normal status changes where relevant.
- [ ] #5 Focused tests cover `JobService.markExpired` event creation and at least one failure-visible UI/service path where practical.
<!-- AC:END -->
