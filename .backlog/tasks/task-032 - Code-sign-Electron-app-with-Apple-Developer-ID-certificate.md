---
id: TASK-032
title: Code sign Electron app with Apple Developer ID certificate
status: To Do
assignee: []
created_date: '2026-06-07 00:50'
labels:
  - electron
  - distribution
  - signing
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Set up proper macOS code signing so users can open the DMG without the xattr workaround. Apple Developer Program enrollment is complete.

## Steps

1. Generate a CSR via openssl
2. Submit CSR to Apple via App Store Connect API (or fastlane cert) to get a Developer ID Application certificate
3. Install the .p12 into the login keychain
4. Remove `CSC_IDENTITY_AUTO_DISCOVERY=false` from `scripts/rebuild-and-launch.sh`
5. Wire up `@electron/notarize` in `build/notarize.js` using an App Store Connect API key
6. Verify a signed DMG opens without Gatekeeper warnings

## Options discussed
- **fastlane cert** (quickest — Ruby, handles CSR + API + install)
- **Node.js script** using App Store Connect REST API directly (no Ruby dependency)
- **Manual portal UI** then configure electron-builder

## Decisions needed
- fastlane vs Node.js script vs manual
- DMG-only or also MAS (Mac App Store)?
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Signed DMG opens on a clean Mac without xattr or Gatekeeper bypass
- [ ] #2 Notarization ticket stapled to the DMG
- [ ] #3 CSC_IDENTITY_AUTO_DISCOVERY=false removed from rebuild script
- [ ] #4 CI release workflow signs and notarizes automatically
<!-- AC:END -->
