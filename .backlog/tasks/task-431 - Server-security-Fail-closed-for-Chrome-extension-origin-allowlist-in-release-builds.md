---
id: TASK-431
title: >-
  Server security: Fail closed for Chrome extension origin allowlist in release
  builds
status: To Do
assignee: []
created_date: '2026-06-13 05:43'
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
