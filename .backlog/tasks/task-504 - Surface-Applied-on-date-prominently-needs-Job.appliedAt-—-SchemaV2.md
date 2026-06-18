---
id: TASK-504
title: 'Surface "Applied on {date}" prominently (needs Job.appliedAt — SchemaV2)'
status: To Do
assignee: []
created_date: '2026-06-18 23:23'
labels:
  - ux
  - schema
dependencies: []
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From workflow UX review-2, item #9 (part a). The Apply flow already (1) sets status to .applied, (2) logs a "status" JobEvent with the timestamp, and (3) — as of review-2 wave 3 — creates a contextual follow-up ("Follow up on {Company} — {Title}"). So the applied date IS recorded today, but only buried in the timeline as a status event.

This task is the remaining UX polish: surface "Applied on {date}" prominently (e.g. the JobDetail footer/header and/or the Jobs list row for applied jobs).

Why it's deferred: doing this cleanly wants a dedicated `Job.appliedAt: Date?` set when status first becomes .applied. Adding a stored property to the @Model is a SwiftData schema change, and SchemaV1 is frozen pending SchemaV2 (TASK-480). Deriving the date by string-parsing the "Status changed from X to applied" event note is fragile and rejected.

Acceptance:
- `Job.appliedAt` added under SchemaV2 with a migration test (depends on TASK-480).
- `setStatus(.applied)` stamps appliedAt the first time (don't overwrite if already set / on re-apply).
- JobDetail shows "Applied {date}"; optionally the Jobs row shows it for applied/interview/offer jobs.
<!-- SECTION:DESCRIPTION:END -->
