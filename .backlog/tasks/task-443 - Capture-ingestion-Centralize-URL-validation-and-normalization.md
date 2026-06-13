---
id: TASK-443
title: 'Capture ingestion: Centralize URL validation and normalization'
status: To Do
assignee: []
created_date: '2026-06-13 18:53'
labels:
  - audit
  - ingestion
  - data-quality
dependencies: []
references:
  - core/Services/JobService.swift
  - server/swift/JobhuntServer.swift
  - core/Services/AvailabilityChecker.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`JobService.ingestCapture` validates URL fields only for non-empty strings, and `addJobByURL` relies on `URL(string:)`, which is not a strict captured-job URL policy. Malformed or unsupported URL schemes can be persisted by MCP, extension bugs, or future clients and later affect availability checks, duplicate detection, and open-in-app behavior.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Captured job URLs are validated through one shared policy that requires expected schemes and rejects malformed values before persistence.
- [ ] #2 Canonical URL values are normalized or rejected under the same policy when present.
- [ ] #3 Server, MCP, add-by-URL, and extension capture ingestion paths use the same validation behavior.
- [ ] #4 Validation failures return clear safe errors to clients and do not enqueue work.
- [ ] #5 Add tests for valid HTTP/HTTPS URLs, unsupported schemes, malformed URLs, and whitespace/case normalization.
<!-- AC:END -->
