---
id: TASK-281
title: 'Application workflow: Make Apply action update job workflow state'
status: To Do
assignee: []
created_date: '2026-06-12 03:36'
labels:
  - audit
  - application-workflow
  - status
  - follow-up
dependencies: []
references:
  - app/Views/Detail/JobDetailView.swift
  - core/Services/JobService.swift
  - core/Settings/SettingsStore.swift
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The detail Apply button is a plain Link, so opening it does not mark the job applied, create an event, or schedule a follow-up. Add an explicit workflow action or confirmation that records the application lifecycle state.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Using the primary Apply workflow can mark the job as applied and create an application event.
- [ ] #2 The workflow can schedule a default follow-up using the configured interval or explicitly ask the user to opt out.
- [ ] #3 Users can still open the source/apply URL without changing status when needed.
<!-- AC:END -->
