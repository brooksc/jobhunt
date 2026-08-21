---
id: TASK-685
title: >-
  Centralize availability-run orchestration across manual and scheduled entry
  points
status: To Do
assignee: []
created_date: '2026-08-21 20:41'
labels:
  - architecture
  - availability
  - tech-debt
dependencies:
  - TASK-673.01
  - TASK-674.01
  - TASK-674.02
  - TASK-681
references:
  - app/Views/Jobs/JobsView.swift
  - app/Views/Settings/SettingsTab.swift
  - app/Shell/AppServices.swift
  - core/Services/AvailabilityChecker.swift
priority: high
type: enhancement
ordinal: 59000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Availability checks currently produce different persistence, retry-backlog, timestamp, and reporting side effects depending on whether the run starts from Jobs, Settings, or the scheduled runtime. Establish one application-level operation with a consistent completion contract so every entry point applies the same confirmed outcomes and deferred-work handling. Preserve confirm-first behavior and keep presentation concerns in the caller.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Jobs, Settings, and scheduled availability runs use the same orchestration contract
- [ ] #2 Every completed run persists all reached-job outcomes exactly once
- [ ] #3 Every completed run transfers deferred or unverified work to the retry backlog using the same rules
- [ ] #4 Cancellation and skipped runs do not persist outcomes or advance the last-check timestamp
- [ ] #5 User-visible all-clear reporting occurs only when every planned job was conclusively checked
- [ ] #6 Automated tests cover parity across all three entry points, cancellation, partial runs, and skipped runs
<!-- AC:END -->
