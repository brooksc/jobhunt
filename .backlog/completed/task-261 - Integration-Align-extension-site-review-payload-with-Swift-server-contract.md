---
id: TASK-261
title: 'Integration: Align extension site-review payload with Swift server contract'
status: Done
assignee: []
created_date: '2026-06-12 02:56'
updated_date: '2026-06-12 03:13'
labels:
  - audit
  - integration
  - extension
  - server
dependencies: []
references:
  - extension/service_worker.js
  - server/swift/JobhuntServer.swift
  - tests/ServerTests/JobhuntServerTests.swift
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The extension `Mark site reviewed` flow sends `site_url`, `site_origin`, `reviewed_at`, `next_review_at`, and `note`, but the Swift server decodes `url`, `page_title`, and `interval_days`. Server tests currently use the server-shaped payload rather than the real extension-shaped payload, so this contract drift can ship unnoticed.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The extension and Swift server agree on one site-review request schema, or the server explicitly supports both legacy and current field names.
- [ ] #2 A server contract test posts the exact payload shape emitted by `buildSiteReviewPayload`.
- [ ] #3 The extension `Mark site reviewed` flow succeeds against the Swift server and persists the intended `Site`/`SiteReview` data.
<!-- AC:END -->
