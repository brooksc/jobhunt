---
id: TASK-436
title: 'Extension capture: Align Mark Site Reviewed payload with server contract'
status: Done
assignee: []
created_date: '2026-06-13 18:25'
updated_date: '2026-06-15 06:11'
labels:
  - audit
  - extension
  - server
  - contract
dependencies: []
references:
  - extension/service_worker.js
  - server/swift/JobhuntServer.swift
modified_files:
  - extension/tests/test_service_worker_contract.js
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The Chrome extension's `markSiteReviewed` path builds a payload with `site_url`, `site_origin`, `next_review_at`, and `note`, while the Swift server's `/site-reviews` route decodes `url`, `page_title`, and `interval_days`. The context-menu action appears wired but should consistently fail validation because the payload and server request model do not match.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The extension and server agree on the request body shape for marking or creating site reviews.
- [x] #2 The Mark Site Reviewed context-menu action succeeds against the Swift server for a valid tab URL.
- [x] #3 Invalid or missing site-review inputs fail with a clear user-facing badge/status and a safe server error body.
- [x] #4 Add a service-worker/server contract test that would fail if the extension payload keys drift from the server request model again.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Investigated: the contract already matches in current code. The server's SiteReviewRequest decoder (JobhuntServer.swift:56) was updated to accept BOTH the extension shape (site_url/site_origin/page_title/reviewed_at/next_review_at/note, with resolvedURL preferring site_url) and the legacy url/interval_days shape — every key buildSiteReviewPayload emits maps to a CodingKey, and schema_version is harmlessly ignored (AC#1). AC#2/#3 already hold: the extension shows a REV/ERR badge and the server uses safeServerError; the server-side test testSiteReview_acceptsExtensionPayload covers acceptance and there's validation for missing url. The real gap was AC#4 (drift guard on the extension side): added a service-worker contract test that captures the contextMenus.onClicked listener, fires the Mark-Site-Reviewed menu item, intercepts the /site-reviews POST, and asserts every payload key is in the server SiteReviewRequest key set (or the allowed extension-only schema_version) and that site_url is present. It fails if the extension payload keys drift from the server model again. Full extension suite green (63/63).
<!-- SECTION:FINAL_SUMMARY:END -->
