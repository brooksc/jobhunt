---
id: TASK-237
title: >-
  Recovery: Replace ModelContainer fatalError with recoverable startup failure
  UI
status: Done
assignee: []
created_date: '2026-06-12 01:51'
updated_date: '2026-06-12 02:16'
labels:
  - diagnostics
  - recovery
  - persistence
dependencies: []
references:
  - app/JobhuntApp.swift
  - core/Models/ModelContainerFactory.swift
  - README.md
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
ModelContainer creation failure currently crashes the app with fatalError. Surface a recovery screen for store corruption, path, or permission failures with database location and safe next actions.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 ModelContainer initialization errors present a recoverable user-facing error state instead of crashing immediately.
- [ ] #2 The recovery UI shows the relevant data path and privacy-safe error summary.
- [ ] #3 Users can open the data folder, retry, and access documented backup/restore guidance.
- [ ] #4 A test or launch-mode harness covers the failure path where practical.
<!-- AC:END -->
