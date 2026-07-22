---
id: DRAFT-006
title: 'Won''t Do: Import from external job trackers'
status: Draft
assignee: []
created_date: '2026-07-22 20:59'
labels:
  - wont-do
  - product-direction
  - import
dependencies: []
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Decision record: do not pursue a general migration/import feature right now. The deferred direction would import jobs and workflow history from common CSV exports while previewing matches, preserving provenance, and avoiding duplicates. This does not preclude a narrow live discovery adapter for a specific scanner.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A future implementation would preview creates, updates, ambiguous matches, and skipped rows before commit.
- [ ] #2 Retries would not duplicate jobs or workflow-history events.
<!-- AC:END -->
