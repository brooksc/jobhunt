---
id: TASK-284
title: 'Cover letters: Implement or remove the persisted cover-letter workflow surface'
status: Done
assignee: []
created_date: '2026-06-12 03:36'
updated_date: '2026-06-12 03:58'
labels:
  - audit
  - cover-letter
  - application-workflow
  - ux
dependencies: []
references:
  - core/Models/CoverLetter.swift
  - core/Services/JobService.swift
  - app/Views/Detail/JobDetailView.swift
modified_files:
  - app/Views/Detail/JobDetailView.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
CoverLetter is in the schema and JobService can delete records, but there is no creation/update UI or service path; the visible tailoring button only shows a placeholder. Either implement cover-letter/tailoring creation or remove/defer the model and UI surface until it is real.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Users can create, edit, view, and delete cover letters for a job, or the placeholder UI/schema surface is removed/deferred behind an explicit feature flag.
- [ ] #2 Cover-letter records include provenance such as resume/model/instructions when generated.
- [ ] #3 Tests cover the chosen create/update/delete workflow.
<!-- AC:END -->
