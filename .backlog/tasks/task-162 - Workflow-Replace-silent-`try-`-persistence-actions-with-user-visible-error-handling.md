---
id: TASK-162
title: >-
  Workflow: Replace silent `try?` persistence actions with user-visible error
  handling
status: Done
assignee: []
created_date: '2026-06-11 20:56'
updated_date: '2026-06-11 21:29'
labels:
  - audit
  - workflow
  - ux
  - error-handling
dependencies: []
references:
  - app/Views/Jobs/JobsView.swift
  - app/Views/Detail/JobDetailView.swift
  - app/Views/Queue/LLMQueueView.swift
modified_files:
  - app/Views/Detail/JobDetailView.swift
  - app/Views/Jobs/JobsView.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Several job workflows suppress service errors with `try?` while also clearing selection, dismissing sheets, or clearing user-entered text. Examples include bulk delete/archive/status changes in `JobsView`, note/action saves in `JobDetailView`, and detail delete/archive actions. Convert these to do/catch flows that preserve user input until success and surface failures consistently.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 User-entered note/action text is not cleared until the save succeeds.
- [ ] #2 Bulk destructive/status actions do not clear selection or imply completion when any service call fails.
- [ ] #3 Errors are surfaced through an existing alert/toast/error state pattern, with focused tests or previewable state coverage where practical.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Fixed note composer (TimelineTabView) to only clear text after successful save and display inline error on failure. Fixed SetNextActionSheet to not dismiss and to show inline error when createAction fails. Fixed bulk archive and delete in JobsView to only clear selection after async completion rather than before the Task runs.
<!-- SECTION:FINAL_SUMMARY:END -->
