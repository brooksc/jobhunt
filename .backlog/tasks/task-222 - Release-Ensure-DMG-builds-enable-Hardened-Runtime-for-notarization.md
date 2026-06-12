---
id: TASK-222
title: 'Release: Ensure DMG builds enable Hardened Runtime for notarization'
status: Done
assignee: []
created_date: '2026-06-12 01:32'
updated_date: '2026-06-12 02:08'
labels:
  - release
  - macos
  - signing
dependencies: []
references:
  - Project.swift
  - config/entitlements/Jobhunt-DMG.entitlements
  - .github/workflows/release-dmg.yml
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The DMG entitlements plist includes a hardened-runtime-looking key, but Hardened Runtime should be enabled through build/signing settings. Make the Developer ID release path explicitly enable Hardened Runtime and verify the notarized artifact reports the expected runtime option.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Release-DMG builds set the appropriate Xcode signing/build setting for Hardened Runtime.
- [ ] #2 The invalid or misleading hardened-runtime entitlement key is removed or documented if intentionally retained.
- [ ] #3 CI verifies the exported app or DMG signature includes Hardened Runtime before notarization/release upload.
- [ ] #4 Developer release docs mention how to confirm Hardened Runtime locally.
<!-- AC:END -->
