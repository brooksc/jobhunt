---
id: TASK-440
title: 'Extension queue: Add export-time privacy notice for full captured text CSVs'
status: Done
assignee: []
created_date: '2026-06-13 18:25'
updated_date: '2026-06-17 04:35'
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
- [x] #1 The queue UI clearly states before export that CSV files include captured page text, selected text, URLs, and notes.
- [x] #2 The export action preserves current CSV contents unless product policy intentionally changes.
- [x] #3 Chrome Web Store privacy/store-listing copy remains consistent with the in-extension export notice.
- [x] #4 Add a lightweight UI or string-level test that protects the export privacy copy from disappearing.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Added a persistent privacy notice (`#export-privacy`) under the queue-page actions stating that exported CSVs include the full captured page text, selected text, job URL, and notes (AC#1) — shown before the user exports. CSV contents are unchanged (AC#2). PRIVACY.md gained a matching "CSV export" paragraph so the Chrome Web Store privacy copy stays consistent with the in-extension notice (AC#3). AC#4: a node --test (tests/test_export_privacy.js, wired into the test script) asserts both the status-page notice element + key phrases and PRIVACY.md's CSV coverage, so the privacy copy can't silently disappear. Full extension suite (71) green. Verified via the JS/string test suite + review (can't load the extension in a browser here).
<!-- SECTION:FINAL_SUMMARY:END -->
