---
id: TASK-231
title: 'Supply chain: Add third-party notice handling for vendored Readability code'
status: Done
assignee: []
created_date: '2026-06-12 01:43'
updated_date: '2026-06-12 02:16'
labels:
  - supply-chain
  - license
  - extension
dependencies: []
references:
  - extension/Readability.js
  - LICENSE
  - scripts/package-extension.sh
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
extension/Readability.js is Apache-licensed third-party code. Add explicit third-party notice/license handling so source and packaged extension distributions preserve the required attribution clearly.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A THIRD_PARTY_NOTICES or equivalent file records Readability/Arc90 Apache 2.0 attribution.
- [ ] #2 The Apache 2.0 license text or a compliant reference is included where distribution requires it.
- [ ] #3 Extension packaging preserves the third-party notice or otherwise satisfies attribution requirements.
- [ ] #4 Contributor docs explain how to add future vendored code.
<!-- AC:END -->
