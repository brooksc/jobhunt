---
id: TASK-129
title: 'Privacy docs: Correct local storage path and queued-capture disclosure'
status: Done
assignee: []
created_date: '2026-06-11 03:01'
updated_date: '2026-06-11 20:30'
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

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Updated both PRIVACY.md and marketing/privacy.html:
- Corrected storage path from ~/.config/jobhunt/ to ~/Library/Application Support/Jobhunt/jobhunt.store
- Added MAS sandboxed path distinction (~/Library/Containers/.../jobhunt.store)
- Replaced "Everything stays on your machine" with local-first framing ("by default, all job data stays on your Mac")
- Added extension offline queue retention bounds: 7 days / 50 items, with contents disclosure (URL, title, selected text, visible text)
- Added custom remote OpenAI-compatible endpoint row to AI provider table with explicit consent requirement
- Added table styles to privacy.html for the new provider and path tables
<!-- SECTION:FINAL_SUMMARY:END -->
