---
id: TASK-443
title: 'Capture ingestion: Centralize URL validation and normalization'
status: Done
assignee: []
created_date: '2026-06-13 18:53'
updated_date: '2026-06-15 19:51'
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
- [x] #1 Captured job URLs are validated through one shared policy that requires expected schemes and rejects malformed values before persistence.
- [x] #2 Canonical URL values are normalized or rejected under the same policy when present.
- [x] #3 Server, MCP, add-by-URL, and extension capture ingestion paths use the same validation behavior.
- [x] #4 Validation failures return clear safe errors to clients and do not enqueue work.
- [x] #5 Add tests for valid HTTP/HTTPS URLs, unsupported schemes, malformed URLs, and whitespace/case normalization.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Added `URLNormalizer.validatedForIngestion(_:)` — one shared captured-job URL policy: trim, require an http/https scheme + non-empty host, lowercase scheme/host (RFC-safe) while preserving path/query/fragment, else throw `URLNormalizer.ValidationError` (empty/unsupportedScheme/malformed). Wired into both JobService ingestion paths before any persistence/enqueue: `ingestCapture` validates the URL (→ `JobServiceError.invalidURL`) and normalizes the canonical URL when present, dropping a malformed canonical rather than failing the whole capture (AC#2); `addJobByURL` validates instead of the lenient `URL(string:)` check. Server `/api/captures` and the MCP bridge both route through `ingestCapture`, so all ingestion paths share the one policy (AC#3). Invalid input throws a clear safe error (LocalizedError) and persists/enqueues nothing (AC#4, asserted by tests). AC#5: URLNormalizerTests (valid http/https, query/fragment preserved, whitespace + scheme/host case normalization, ftp/file/javascript/mailto rejected, schemeless, host-less) plus JobService integration tests (invalid url/scheme → nothing persisted/enqueued; malformed canonical dropped). Full fast gate (738 CoreTests + Server + MCP) green; app builds.
<!-- SECTION:FINAL_SUMMARY:END -->
