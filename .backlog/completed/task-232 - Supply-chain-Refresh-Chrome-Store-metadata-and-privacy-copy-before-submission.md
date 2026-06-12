---
id: TASK-232
title: 'Supply chain: Refresh Chrome Store metadata and privacy copy before submission'
status: Done
assignee: []
created_date: '2026-06-12 01:43'
updated_date: '2026-06-12 02:16'
labels:
  - supply-chain
  - chrome-store
  - docs
  - privacy
dependencies:
  - TASK-219
references:
  - chromestore/store-listing.md
  - chromestore/PRIVACY.md
  - extension/manifest.json
  - PRIVACY.md
  - docs/chrome-web-store-review.md
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Chrome Store submission metadata is stale: chromestore/store-listing.md lists an old version and says no data leaves the device, which conflicts with optional cloud LLM behavior and Greenhouse enrichment findings. Update the submission materials to match current behavior.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Chrome Store listing version matches extension/manifest.json or avoids duplicating the version manually.
- [ ] #2 Privacy copy reflects optional cloud/remote LLM behavior and any Greenhouse enrichment behavior chosen by the privacy task.
- [ ] #3 Permission justifications match the current manifest and runtime behavior.
- [ ] #4 Submission docs are checked as part of the release checklist.
<!-- AC:END -->
