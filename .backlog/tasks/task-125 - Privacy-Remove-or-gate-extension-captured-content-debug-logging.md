---
id: TASK-125
title: 'Privacy: Remove or gate extension captured-content debug logging'
status: To Do
assignee: []
created_date: '2026-06-11 03:01'
labels:
  - privacy
  - extension
  - logging
dependencies: []
references:
  - extension/service_worker.js
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The Chrome extension service worker logs captured page excerpts and structured data, including visible text head/tail. These logs can expose sensitive job-page or user-entered content in browser developer tooling.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Captured visible text, selected text, structured data, and raw capture payloads are not logged in normal extension builds.
- [ ] #2 Any remaining diagnostic logging is controlled by an explicit development-only flag that defaults off.
- [ ] #3 Failure logs preserve enough operational detail without printing captured content.
- [ ] #4 Manual or automated checks confirm visible_text_head, visible_text_tail, and structured_data payload logs are removed or gated.
<!-- AC:END -->
