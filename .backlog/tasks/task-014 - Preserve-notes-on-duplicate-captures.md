---
id: TASK-014
title: Preserve notes on duplicate captures
status: Done
assignee: []
created_date: '2026-05-27 05:24'
updated_date: '2026-05-27 05:25'
labels:
  - m2-extension
  - notes
  - server
dependencies:
  - TASK-003
  - TASK-006
modified_files:
  - src/jobhunt/db.py
  - tests/test_db.py
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
When a user saves a job with a note and the capture is detected as a duplicate, preserve the note instead of dropping it. Duplicate capture notes should be recorded against the existing job timeline so users can add context after a job has already been saved.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A duplicate capture with a non-empty user_note creates a note_added event for the existing job
- [x] #2 A duplicate capture without a note does not create an extra note event
- [x] #3 The capture response still returns duplicate true with the existing capture_id
- [x] #4 Focused tests cover duplicate capture with note and duplicate capture without note
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Confirmed the user's duplicate note was not stored because insert_capture returned early on raw_hash duplicates. Fixed duplicate handling so non-empty user_note creates a note_added event on the existing job while duplicate captures without notes do not create extra events.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Duplicate captures now preserve notes by writing a note_added event against the existing job timeline. The API still returns duplicate true with the existing capture_id. Added focused tests for duplicate-with-note and duplicate-without-note behavior.
<!-- SECTION:FINAL_SUMMARY:END -->
