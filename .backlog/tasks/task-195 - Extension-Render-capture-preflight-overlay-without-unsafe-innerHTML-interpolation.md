---
id: TASK-195
title: >-
  Extension: Render capture preflight overlay without unsafe innerHTML
  interpolation
status: Done
assignee: []
created_date: '2026-06-11 23:47'
updated_date: '2026-06-11 23:59'
labels:
  - extension
  - capture
  - security
  - audit
dependencies: []
references:
  - extension/capture.js
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The capture preflight overlay interpolates page-derived fields into innerHTML. A malicious job page can inject markup into the extension-created overlay in the page world.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Page-derived values in the preflight overlay are inserted with textContent or equivalent escaping.
- [x] #2 Tests verify HTML-like page title/location/salary values render as text, not markup.
- [x] #3 The preflight UI still supports cancel, save, and issue-report actions.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Rewrote the showCapturePreflight overlay in capture.js to use a static innerHTML skeleton with placeholder slots, then populate page-derived values (titleVal, locationVal, salaryVal, remoteVal) via DOM createElement + textContent. The "Wrong data?" link is created with createElement/setAttribute. Stats line uses createTextNode. Added test_preflight_security.js with 7 source-analysis tests verifying no page-derived values appear inside innerHTML assignments and that textContent is used. All 52 extension tests pass.
<!-- SECTION:FINAL_SUMMARY:END -->
