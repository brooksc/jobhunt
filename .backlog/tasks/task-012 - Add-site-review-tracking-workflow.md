---
id: TASK-012
title: Add site review tracking workflow
status: Done
assignee: []
created_date: '2026-05-27 04:58'
updated_date: '2026-05-27 05:20'
labels:
  - m2-extension
  - m4-export-workflow
  - site-review
  - server
  - extension
dependencies:
  - TASK-003
  - TASK-004
modified_files:
  - src/jobhunt/models.py
  - src/jobhunt/db.py
  - src/jobhunt/api.py
  - extension/service_worker.js
  - tests/test_site_reviews.py
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Add a workflow for marking the current site or careers page as fully reviewed without capturing a specific job. This helps track which job boards company career pages or search pages have already been checked and when they should be checked again.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The database stores site review records with site_url site_origin page_title reviewed_at optional next_review_at note and created_at
- [x] #2 The local API exposes POST /site-reviews and validates a schema_version 1 payload
- [x] #3 The extension provides a secondary context menu action named Mark site reviewed
- [x] #4 Using the context menu action sends the current page URL origin title and reviewed timestamp to the local API
- [x] #5 The workflow does not interfere with one-click job capture
- [x] #6 Focused tests cover API persistence for site reviews and payload validation
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
Add site review support in three pieces: Pydantic request/response models, SQLite table/helper plus API endpoint, and extension context menu action that sends the current tab URL origin title and reviewed timestamp. Cover server behavior with focused tests and keep one-click capture unchanged.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Implemented site_reviews persistence and POST /site-reviews. Added Mark site reviewed context menu action that builds a review payload from the current tab and posts it to the local API. Verified with tests and a smoke server on port 8766. The already-running server on port 8765 returned 404 because it predates this code and must be restarted before the extension can call the new endpoint.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Added site review tracking. The server stores reviewed sites with URL origin title reviewed_at optional next_review_at note and created_at, exposes POST /site-reviews, and validates the schema_version 1 payload. The Chrome extension now registers a Mark site reviewed context menu action that posts the current tab metadata without affecting one-click job capture.
<!-- SECTION:FINAL_SUMMARY:END -->
