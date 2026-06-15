---
id: TASK-460
title: >-
  Job URLs: Centralize source, application, and availability-check URL
  precedence
status: Done
assignee: []
created_date: '2026-06-13 23:36'
updated_date: '2026-06-15 19:56'
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
- [x] #1 A shared URL policy/helper defines source URL, application URL, display URL, and availability-check URL precedence for a job.
- [x] #2 CSV export, MCP job projections, availability checking, and job detail actions use the shared policy instead of duplicating precedence inline.
- [x] #3 Existing intended behavior is documented by tests for jobs with application URL, canonical capture URL, raw capture URL, and missing URLs.
- [x] #4 No user-facing surface regresses to opening or exporting an empty URL when a valid fallback exists.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Related to but distinct from TASK-443 (centralize URL *validation/normalization* at ingestion — input policy). This task is about URL *precedence selection* across output surfaces (export/display/availability). Both should live in one shared URL helper module; 460 can build on the normalization primitives from 443. Kept separate intentionally.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Added `JobURLPolicy` (core) defining job-URL precedence once: sourceURL = canonical ?? captureURL; applicationURL & availabilityCheckURL = applicationURL ?? canonical ?? captureURL; displayURL = canonical ?? captureURL ?? applicationURL. All helpers skip nil and blank/whitespace values so an empty field never shadows a usable fallback (AC#4). Replaced the inline precedence in ExportService (source_url), the MCP JobListRecord/JobDetailRecord projections (sourceURL — now canonical-aware; previously raw captureURL only), AvailabilityChecker (both eligibility passes), and JobDetailView (the four Source/Open-source/captureDomain display sites → displayURL; the Apply action → applicationURL). Raw diagnostic rows still show capture.url/canonicalURL verbatim. AC#3: JobURLPolicyTests cover application-URL / canonical / raw-capture / missing precedence, blank-skipping, and the Job-relationship conveniences (incl. availability == application precedence). Full CoreTests (762) green; app builds. Note: MCP `sourceURL` now returns the canonical URL when present (previously the raw capture URL) — an intentional alignment to the shared policy.
<!-- SECTION:FINAL_SUMMARY:END -->
