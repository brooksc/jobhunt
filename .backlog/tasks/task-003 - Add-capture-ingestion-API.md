---
id: TASK-003
title: Add capture ingestion API
status: Done
assignee: []
created_date: '2026-05-27 04:35'
updated_date: '2026-05-27 04:44'
labels:
  - m1-foundation
  - server
  - api
dependencies:
  - TASK-002
modified_files:
  - src/jobhunt/api.py
  - src/jobhunt/models.py
  - src/jobhunt/db.py
  - tests/test_api.py
  - tests/test_db.py
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Implement the local API endpoint that receives raw job captures from the Chrome extension. The endpoint should validate the payload persist a new capture create a cleaned job description create the associated saved job and return duplicate status when the same capture already exists.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 `POST /captures` accepts the schema_version 1 capture payload described in spec.md
- [x] #2 A valid new capture creates one captures row one jobs row with status saved and one captured event
- [x] #3 Submitting the same capture twice returns ok true duplicate true with the existing capture_id
- [x] #4 Invalid payloads return a clear client error without writing partial data
- [x] #5 Focused API tests cover successful capture duplicate capture and invalid payload behavior
- [x] #6 Capture ingestion stores a cleaned_description derived from selected text JSON-LD description or visible text
- [x] #7 Capture ingestion computes cleaned_hash and uses it to identify duplicate candidates across different URLs without discarding the new capture
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Implemented `POST /captures` with Pydantic validation and SQLite persistence. Valid captures create capture job and event rows, raw duplicates return the existing capture ID, invalid payloads are rejected, and cleaned descriptions/hashes are persisted for duplicate candidates.
<!-- SECTION:FINAL_SUMMARY:END -->
