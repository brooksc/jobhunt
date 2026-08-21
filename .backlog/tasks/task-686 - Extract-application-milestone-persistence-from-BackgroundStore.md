---
id: TASK-686
title: Extract application-milestone persistence from BackgroundStore
status: To Do
assignee: []
created_date: '2026-08-21 20:41'
labels:
  - architecture
  - persistence
  - tech-debt
dependencies: []
references:
  - core/Services/BackgroundStore.swift
  - core/Models
priority: medium
type: enhancement
ordinal: 60000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
BackgroundStore is a broad change hub spanning unrelated domains. Reduce its regression radius with one bounded extraction for application milestones: referral attempts, interviews, offers, their timeline events, and related cleanup. Preserve existing data behavior and actor isolation while giving this workflow a cohesive persistence boundary.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Referral-attempt, interview, and offer persistence is owned by a cohesive boundary rather than BackgroundStore
- [ ] #2 Timeline-event creation, update, deduplication, and deletion remain transactionally consistent with their owning records
- [ ] #3 Existing callers use the new boundary without duplicating milestone persistence rules
- [ ] #4 No persisted schema or migration is required for this extraction
- [ ] #5 Existing milestone behavior remains compatible for the app, server, MCP, and migration tools
- [ ] #6 Automated tests cover create, update, delete, missing-job, deduplication, and rollback behavior for each extracted record type
<!-- AC:END -->
