---
id: TASK-129
title: 'Privacy docs: Correct local storage path and queued-capture disclosure'
status: To Do
assignee: []
created_date: '2026-06-11 03:01'
updated_date: '2026-06-11 04:34'
labels:
  - privacy
  - documentation
  - storage
dependencies: []
references:
  - PRIVACY.md
  - core/Models/ModelContainerFactory.swift
  - extension/retry_queue.js
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
PRIVACY.md still refers to the legacy ~/.config/jobhunt path while the SwiftData production store uses Application Support. The privacy docs should also disclose extension offline queue retention once bounded retention is implemented.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 PRIVACY.md lists the current production data location under Application Support for normal app storage.
- [ ] #2 Docs distinguish sandboxed MAS storage from unsandboxed DMG storage where paths differ.
- [ ] #3 Docs describe extension offline queued captures, what data they may contain, and how users can clear them.
- [ ] #4 Storage-path text is checked against ModelContainerFactory behavior before the task is completed.
- [ ] #5 Marketing/privacy copy removes absolute claims that everything always stays on-device and clearly distinguishes local-first default behavior from user-configured cloud or remote custom LLM providers.
- [ ] #6 Privacy docs disclose that remote custom OpenAI-compatible endpoints can receive job text and resume text when configured.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Security/privacy audit addendum: `marketing/privacy.html` currently states that everything stays on the user's machine, then later discloses optional cloud LLM processing. Privacy docs and marketing copy should consistently describe the app as local-first, not local-only, and should include custom remote provider behavior.
<!-- SECTION:NOTES:END -->
