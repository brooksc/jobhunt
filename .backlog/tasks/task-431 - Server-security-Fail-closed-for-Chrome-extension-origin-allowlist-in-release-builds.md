---
id: TASK-431
title: >-
  Server security: Fail closed for Chrome extension origin allowlist in release
  builds
status: In Progress
assignee:
  - claude
created_date: '2026-06-13 05:43'
updated_date: '2026-06-15 00:27'
labels:
  - audit
  - server
  - security
  - extension
dependencies: []
references:
  - server/swift/JobhuntServer.swift
  - tests/ServerTests/JobhuntServerTests.swift
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The local server's extension route authorization currently treats an empty `allowedExtensionOrigins` set as development mode and permits any `chrome-extension://` origin. Tests intentionally document that arbitrary extension origins may succeed while the allowlist is empty. This means capture, site review, job lookup, and focus routes trust a forgeable Origin header from any installed Chrome extension until a production extension ID is configured.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Release/production builds reject all `chrome-extension://` origins unless an explicit approved extension origin is configured.
- [ ] #2 Permissive extension-origin behavior, if still needed for development, is gated behind an explicit debug/development flag that cannot silently ship in release builds.
- [ ] #3 Server tests assert that arbitrary unapproved Chrome extension origins receive 403 and no reflected CORS headers in production-mode configuration.
- [ ] #4 Documentation identifies where the approved Chrome Web Store extension ID is configured and how development IDs are handled.
- [ ] #5 Existing approved-extension capture, site review, job lookup, and focus flows continue to work when the configured origin matches.
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
Make the Chrome-extension origin allowlist fail closed in release.

- Replace the static `allowedExtensionOrigins` + empty-set permit-all with configurable instance settings injected via `init`:
  - `allowedExtensionOrigins: Set<String>` (default = published CWS origin `chrome-extension://jekcbebhfeidkpapienoflbcaeeknlch`, from the onboarding store URL).
  - `allowArbitraryExtensionOrigins: Bool` (default `true` only under `#if DEBUG`, `false` in release) — permits locally-loaded unpacked dev extensions (different ID) in debug only.
- Extract a pure, testable `static func isApprovedExtensionOrigin(_:allowlist:allowArbitrary:)`; the instance method delegates to it. CORS reflection + route 403 already key off `isAllowedExtensionOrigin`, so fail-closed automatically yields 403 + no CORS for unapproved origins.
- Tests: `makeTestServer` passes `allowArbitraryExtensionOrigins: true` so existing tests stay green regardless of DEBUG. Add: unit tests of `isApprovedExtensionOrigin` (both modes); an integration test with a production-mode server (allowArbitrary=false) asserting arbitrary origin → 403 + no CORS (AC #3) and the approved origin → reflected CORS (AC #5).
- Update the doc comment to state where the CWS ID is configured and how dev IDs are handled (AC #4).

Note/assumption: `jekcbebhfeidkpapienoflbcaeeknlch` is taken from the onboarding Chrome Web Store URL as the published extension ID — flag for confirmation.
<!-- SECTION:PLAN:END -->
