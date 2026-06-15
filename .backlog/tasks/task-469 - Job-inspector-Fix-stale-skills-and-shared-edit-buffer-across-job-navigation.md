---
id: TASK-469
title: 'Job inspector: Fix stale skills and shared edit buffer across job navigation'
status: To Do
assignee: []
created_date: '2026-06-15 03:38'
labels:
  - bug
  - app
  - ui
dependencies: []
references:
  - app/Views/Detail/JobDetailView.swift
  - app/Shell/ContentView.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Two view-identity hazards in the job inspector:

1. `OverviewTabView.skills` is `@State` populated only by `.onAppear { loadSkills() }` (JobDetailView.swift:389,448,788). The inspector reuses the same JobDetailView/OverviewTabView instance across jobs (no `.id(job.id)` in JobInspectorView; prev/next just swaps selectedJobIDs — ContentView.swift:247-252,305-311), so onAppear does not re-fire and the Skills section keeps showing (and may save back) the previously viewed job's skills. Fix: add `.id(job.id)` to JobDetailView in JobInspectorView, or reload skills via `.onChange(of: job.id)`.

2. All editable rows share a single `editText`/`editingField`/`editFocused` (JobDetailView.swift:704-738). Tapping the pencil on row B while row A is focused sets editText = value(B) and editingField = B, then A's `onChange(of: editFocused)` fires with focused == false and calls commitEdit comparing the now-overwritten editText (B's value) against A's value — persisting B's text into field A. Fix: commit the outgoing field before mutating shared edit state when starting a new edit, or key the edit buffer per-field.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Navigating prev/next between jobs in the inspector shows the correct job's skills
- [ ] #2 Switching editable rows mid-edit cannot write one field's text into another
- [ ] #3 In-progress edit buffers reset when the displayed job changes
<!-- AC:END -->
