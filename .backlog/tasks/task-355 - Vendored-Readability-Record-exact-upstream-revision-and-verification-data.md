---
id: TASK-355
title: 'Vendored Readability: Record exact upstream revision and verification data'
status: Done
assignee: []
created_date: '2026-06-12 20:43'
updated_date: '2026-06-12 21:53'
labels:
  - audit
  - supply-chain
  - third-party
  - extension
dependencies: []
references:
  - extension/Readability.js
  - THIRD_PARTY_NOTICES.md
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
extension/Readability.js is vendored and has license attribution, but THIRD_PARTY_NOTICES.md does not record the exact upstream commit/tag/hash used. Future security or license reviews cannot verify the vendored file against upstream precisely.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Third-party notices record the exact upstream commit/tag or release for Readability.js.
- [ ] #2 The vendored file includes or is accompanied by a checksum/source verification note.
- [ ] #3 The update procedure for vendored third-party browser code is documented.
<!-- AC:END -->
