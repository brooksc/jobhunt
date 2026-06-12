---
id: TASK-337
title: 'Privacy docs: Align Greenhouse external request disclosure across surfaces'
status: Done
assignee: []
created_date: '2026-06-12 20:26'
updated_date: '2026-06-12 20:58'
labels:
  - audit
  - privacy
  - extension
  - docs
dependencies: []
references:
  - extension/capture.js
  - marketing/privacy.html
  - PRIVACY.md
  - chromestore/PRIVACY.md
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The extension fetches Greenhouse public job data from boards-api.greenhouse.io during capture, but marketing/privacy.html says the extension sends nothing to external servers, and chromestore/PRIVACY.md describes Greenhouse enrichment as a Mac app feature. Align all privacy surfaces with the actual extension behavior.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Marketing, app, and Chrome Store privacy text consistently disclose the Greenhouse public API request performed by the extension.
- [ ] #2 The disclosure states when it happens, what identifier/data is sent, and that credentials/personal data are not included.
- [ ] #3 A lightweight docs check or review checklist prevents future privacy text drift across surfaces.
<!-- AC:END -->
