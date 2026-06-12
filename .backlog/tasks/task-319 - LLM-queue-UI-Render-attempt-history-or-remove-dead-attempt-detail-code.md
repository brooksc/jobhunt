---
id: TASK-319
title: 'LLM queue UI: Render attempt history or remove dead attempt-detail code'
status: Done
assignee: []
created_date: '2026-06-12 19:42'
updated_date: '2026-06-12 20:03'
labels:
  - audit
  - llm-queue
  - ui
dependencies: []
references:
  - app/Views/Queue/LLMQueueView.swift
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
expandedIDs and AttemptDetailView exist, but nothing toggles or renders them in LLMQueueView. Even after attempt linking is fixed, the current queue UI will not expose attempt history.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Queue rows expose linked attempt history in the UI, or unused expandedIDs/AttemptDetailView code is removed.
- [ ] #2 Attempt history display includes status, duration, requested/returned model, token/character counts, and error when available.
- [ ] #3 UI tests or preview coverage verify the attempt history state is reachable.
<!-- AC:END -->
