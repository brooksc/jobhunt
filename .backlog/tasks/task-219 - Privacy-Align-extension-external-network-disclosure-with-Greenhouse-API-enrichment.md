---
id: TASK-219
title: >-
  Privacy: Align extension external-network disclosure with Greenhouse API
  enrichment
status: To Do
assignee: []
created_date: '2026-06-12 01:05'
labels:
  - privacy
  - extension
  - docs
dependencies: []
references:
  - PRIVACY.md
  - marketing/privacy.html
  - extension/capture.js
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The privacy policy says the extension sends nothing to external servers, but capture.js may call Greenhouse's public boards API for Greenhouse postings. Update the disclosure and/or make the enrichment opt-in or disableable.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Privacy documentation accurately describes the Greenhouse API enrichment request or the request is removed/disabled by default.
- [ ] #2 Marketing privacy page is updated consistently with PRIVACY.md.
- [ ] #3 The extension UI or docs clarify what identifiers are sent when Greenhouse enrichment is used.
- [ ] #4 Tests or review checks cover the chosen behavior where practical.
<!-- AC:END -->
