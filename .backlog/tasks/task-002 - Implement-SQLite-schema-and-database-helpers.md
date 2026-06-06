---
id: TASK-002
title: Implement SQLite schema and database helpers
status: Done
assignee: []
created_date: '2026-05-27 04:35'
updated_date: '2026-05-27 04:44'
labels:
  - m1-foundation
  - database
dependencies:
  - TASK-001
modified_files:
  - src/jobhunt/db.py
  - src/jobhunt/cleaning.py
  - src/jobhunt/models.py
  - tests/test_db.py
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Add durable local SQLite storage for raw captures jobs and events. This supports the local-first architecture in spec.md and gives later API extraction and export tasks a stable persistence layer.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The service creates or initializes a SQLite database in a local data path suitable for development
- [x] #2 The database contains captures jobs and events tables matching the MVP fields in spec.md
- [x] #3 Database helpers can create a capture job and captured event in one transaction
- [x] #4 Duplicate raw_hash values are rejected or reported without corrupting existing data
- [x] #5 Focused tests cover schema initialization insertion and duplicate handling
- [x] #6 The captures table stores cleaned_description and cleaned_hash alongside raw capture fields
- [x] #7 Database helpers compute or persist enough data to support future cross-source duplicate detection from cleaned descriptions
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Implemented SQLite initialization and capture insertion helpers. The schema creates captures jobs and events, stores cleaned_description and cleaned_hash, handles raw duplicate captures, and marks cross-source cleaned-hash duplicate candidates.
<!-- SECTION:FINAL_SUMMARY:END -->
