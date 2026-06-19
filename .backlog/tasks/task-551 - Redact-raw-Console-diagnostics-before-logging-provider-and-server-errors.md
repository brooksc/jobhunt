---
id: TASK-551
title: Redact raw Console diagnostics before logging provider and server errors
status: To Do
assignee: []
created_date: '2026-06-19 22:59'
labels:
  - audit
  - privacy
  - diagnostics
  - logging
dependencies: []
references:
  - 'server/swift/ServerErrors.swift:15'
  - 'core/LLM/ModelCatalog.swift:145'
modified_files:
  - server/swift/ServerErrors.swift
  - core/LLM/ModelCatalog.swift
  - core/Diagnostics/DiagnosticsRedactor.swift
  - tests/CoreTests/DiagnosticsRedactorTests.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Finding: several diagnostic log paths intentionally keep HTTP responses safe for clients but still print raw error details to Console. `safeServerError` returns a stable `internal_error` body, but it also prints the full `Error` object (`server/swift/ServerErrors.swift:15`). `ModelCatalog.get` logs the provider URL and the first 500 bytes of a failed model-list response body (`core/LLM/ModelCatalog.swift:145`). These are outside the `DiagnosticsRedactor` path used by Copy Diagnostics.

Why important: Console logs are commonly requested during support escalation and may be included in bug reports. Raw provider bodies or thrown server errors can contain file paths, endpoint query strings, request fragments, provider messages, or echoed tokens. The HTTP response boundary is safe, but the support/logging boundary is not consistently redacted.

Suggested implementation: introduce a small privacy-safe logging helper that runs free-form strings through `DiagnosticsRedactor` before `NSLog`/`print` use in support-relevant paths. Apply it to `safeServerError` and the model-catalog failure log. For model fetch failures, keep the existing safe key fingerprint but redact `url.absoluteString` and the body excerpt. Add tests around the helper or targeted unit tests that verify logged/composed strings do not retain file paths, URL query values, or named secret fields.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 `safeServerError` no longer writes unredacted free-form error text to Console.
- [ ] #2 Model catalog failure logging redacts URL query strings and provider response snippets before logging.
- [ ] #3 Tests or focused coverage demonstrate Console-oriented diagnostic strings redact the same classes of sensitive data as copied diagnostics.
<!-- AC:END -->
