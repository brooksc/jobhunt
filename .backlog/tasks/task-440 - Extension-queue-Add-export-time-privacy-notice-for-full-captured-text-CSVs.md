---
id: TASK-440
title: 'Extension queue: Add export-time privacy notice for full captured text CSVs'
status: To Do
assignee: []
created_date: '2026-06-13 18:25'
labels:
  - audit
  - extension
  - privacy
  - ux
dependencies: []
references:
  - extension/status.html
  - extension/status.js
  - extension/export_csv.js
  - chromestore/PRIVACY.md
  - chromestore/store-listing.md
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Offline queue CSV export intentionally includes `selected_text`, `visible_text`, and `user_note`, but the queue page labels the action only as `Export CSV`. Users should get an explicit local reminder that exported files contain full captured page text and notes before creating a portable file.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The queue UI clearly states before export that CSV files include captured page text, selected text, URLs, and notes.
- [ ] #2 The export action preserves current CSV contents unless product policy intentionally changes.
- [ ] #3 Chrome Web Store privacy/store-listing copy remains consistent with the in-extension export notice.
- [ ] #4 Add a lightweight UI or string-level test that protects the export privacy copy from disappearing.
<!-- AC:END -->
