---
id: TASK-460
title: >-
  Job URLs: Centralize source, application, and availability-check URL
  precedence
status: To Do
assignee: []
created_date: '2026-06-13 23:36'
updated_date: '2026-06-14 00:19'
labels:
  - url-handling
  - reporting
  - automation
dependencies: []
references:
  - core/Services/ExportService.swift
  - core/Models/Projections.swift
  - core/Services/AvailabilityChecker.swift
  - app/Views/Detail/JobDetailView.swift
  - tests/CoreTests/JobServiceTests.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Different surfaces choose different URL precedence for the same job. CSV export uses `capture.canonicalURL ?? capture.url`, MCP projections expose `capture.url`, availability checking uses `applicationURL ?? canonicalURL ?? url`, and job detail actions sometimes prefer `capture.url` and sometimes `applicationURL`. URL precedence should be centralized so UI, export, MCP, and automation behave predictably.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A shared URL policy/helper defines source URL, application URL, display URL, and availability-check URL precedence for a job.
- [ ] #2 CSV export, MCP job projections, availability checking, and job detail actions use the shared policy instead of duplicating precedence inline.
- [ ] #3 Existing intended behavior is documented by tests for jobs with application URL, canonical capture URL, raw capture URL, and missing URLs.
- [ ] #4 No user-facing surface regresses to opening or exporting an empty URL when a valid fallback exists.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Related to but distinct from TASK-443 (centralize URL *validation/normalization* at ingestion — input policy). This task is about URL *precedence selection* across output surfaces (export/display/availability). Both should live in one shared URL helper module; 460 can build on the normalization primitives from 443. Kept separate intentionally.
<!-- SECTION:NOTES:END -->
