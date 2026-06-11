---
id: TASK-195
title: >-
  Extension: Render capture preflight overlay without unsafe innerHTML
  interpolation
status: To Do
assignee: []
created_date: '2026-06-11 23:47'
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
- [ ] #1 Page-derived values in the preflight overlay are inserted with textContent or equivalent escaping.
- [ ] #2 Tests verify HTML-like page title/location/salary values render as text, not markup.
- [ ] #3 The preflight UI still supports cancel, save, and issue-report actions.
<!-- AC:END -->
