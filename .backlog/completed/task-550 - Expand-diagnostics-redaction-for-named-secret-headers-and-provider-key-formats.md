---
id: TASK-550
title: Expand diagnostics redaction for named secret headers and provider key formats
status: Done
assignee: []
created_date: '2026-06-19 22:59'
updated_date: '2026-06-26 00:50'
labels:
  - audit
  - privacy
  - diagnostics
dependencies: []
references:
  - 'core/Diagnostics/DiagnosticsRedactor.swift:19'
  - 'app/Views/Settings/DebugTab.swift:205'
  - 'app/Views/Settings/DebugTab.swift:212'
modified_files:
  - core/Diagnostics/DiagnosticsRedactor.swift
  - tests/CoreTests/DiagnosticsRedactorTests.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Finding: `DiagnosticsRedactor.redact` is the central guard for copied support diagnostics, but its secret matching currently covers only Bearer tokens, `sk-` keys, and Google `AIza` keys (`core/Diagnostics/DiagnosticsRedactor.swift:19`). `DebugTab.buildDiagnosticsText` relies on this helper for server errors and recent toast errors before placing diagnostics on the pasteboard (`app/Views/Settings/DebugTab.swift:205`, `app/Views/Settings/DebugTab.swift:212`). That leaves plausible leaks when arbitrary `localizedDescription` strings contain named secret headers or fields such as `x-api-key: ...`, `api-key=...`, `Authorization: Basic ...`, `api_key: ...`, or provider-specific non-`sk-` token formats.

Why important: diagnostics are explicitly designed to be copied out of the app for support. The current implementation is best-effort, but the API boundary accepts free-form provider, URLSession, SwiftData, and keychain error text. A small redaction gap can turn a support bundle into a secret disclosure.

Suggested implementation: extend `DiagnosticsRedactor` with case-insensitive patterns for common named secret fields/headers (`authorization`, `x-api-key`, `api-key`, `api_key`, `token`, `access_token`, `refresh_token`, `client_secret`) in both `name: value` and `name=value` forms. Preserve the field name where useful and replace only the value. Add regression tests in `DiagnosticsRedactorTests` for named headers, query-like fragments outside full URLs, and non-OpenAI provider token examples. Keep benign text preservation covered so the redactor does not make diagnostics unreadable.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Copied diagnostics redact named secret fields and headers in colon and equals forms.
- [x] #2 Existing redaction cases for file paths, URL query strings, Bearer tokens, `sk-` keys, and `AIza` keys continue to pass.
- [x] #3 Regression tests prove benign HTTP/status text remains intact.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
DiagnosticsRedactor now redacts named secret fields/headers (authorization, x-api-key, api[-_]key, access_token, refresh_token, client_secret, token) in both `name: value` and `name=value` forms (case-insensitive, field name preserved, value stops at structural delimiters incl. `&`), plus full `Basic <base64>` credentials (base64 charset added to the scheme-prefix pattern). Existing file-path/URL-query/Bearer/sk-/AIza cases still pass; benign HTTP/status text verified intact. Tests: DiagnosticsRedactorTests (named colon+equals forms, Basic auth, benign HTTP). Commit 456ec97.
<!-- SECTION:FINAL_SUMMARY:END -->
