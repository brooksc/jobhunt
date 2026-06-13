---
id: TASK-436
title: 'Extension capture: Align Mark Site Reviewed payload with server contract'
status: To Do
assignee: []
created_date: '2026-06-13 18:25'
labels:
  - audit
  - extension
  - server
  - contract
dependencies: []
references:
  - extension/service_worker.js
  - server/swift/JobhuntServer.swift
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The Chrome extension's `markSiteReviewed` path builds a payload with `site_url`, `site_origin`, `next_review_at`, and `note`, while the Swift server's `/site-reviews` route decodes `url`, `page_title`, and `interval_days`. The context-menu action appears wired but should consistently fail validation because the payload and server request model do not match.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The extension and server agree on the request body shape for marking or creating site reviews.
- [ ] #2 The Mark Site Reviewed context-menu action succeeds against the Swift server for a valid tab URL.
- [ ] #3 Invalid or missing site-review inputs fail with a clear user-facing badge/status and a safe server error body.
- [ ] #4 Add a service-worker/server contract test that would fail if the extension payload keys drift from the server request model again.
<!-- AC:END -->
