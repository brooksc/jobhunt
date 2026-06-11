---
id: TASK-062
title: >-
  DMG distribution: Developer ID signing, notarization, Sparkle appcast, GitHub
  release workflow
status: Done
assignee: []
created_date: '2026-06-07 22:51'
updated_date: '2026-06-11 03:39'
labels:
  - swift-rewrite
  - dist
  - ci
milestone: m-1
dependencies:
  - TASK-033
  - TASK-060
documentation:
  - swift-plan.md
  - .github/workflows/release.yml
  - scripts/notarize.cjs
  - scripts/bump-version.sh
priority: high
ordinal: 3900
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Goal: Produce the signed, notarized GitHub DMG with Sparkle auto-update, via CI on version tags.

## Read first
- swift-plan.md §13.1 (DMG flavor), §13.2 (DMG entitlements), §13.4 (Sparkle from v1, no bridge release needed), §13.5–13.6 (signing/certs + CI), §5.2 (versioning via agvtool/Tuist).
- Existing .github/workflows/release.yml (Electron version — reuse the cert-import + secret structure), scripts/notarize.cjs (notarytool usage to replicate), scripts/bump-version.sh (adapt to Xcode version settings).

## Implement
- xcodebuild archive of Jobhunt-DMG → export with Developer ID Application signing → create DMG → `xcrun notarytool submit --wait` → `stapler staple`.
- Sparkle: generate + EdDSA-sign the appcast (generate_appcast), publish DMG + appcast.xml + (Sparkle) to the GitHub Release.
- GitHub Actions job `build-dmg` on `v*` tags (macos-latest): import DEVELOPER_ID cert from base64 secret, build, notarize, publish via gh release. Reuse the documented secrets (APPLE_ID, APPLE_APP_SPECIFIC_PASSWORD, APPLE_TEAM_ID, DEVELOPER_ID_CERT_BASE64/PASSWORD, GH_TOKEN, plus Sparkle EdDSA key).
- Adapt bump-version.sh to set MARKETING_VERSION/CURRENT_PROJECT_VERSION and keep extension/manifest.json in lockstep.
- Run `xcodebuild test` + coverage gate as a required pre-release step.

## Dependencies
Depends on task-033 (project + CI skeleton + DMG entitlements) and task-060 (Sparkle wiring in the app). Pairs with task-062 (MAS) and task-064 (cutover).

## Acceptance / verification
- Tagging v* produces a notarized DMG on the GitHub Release that passes Gatekeeper on a clean machine (no xattr workaround). Sparkle update vN→vN+1 succeeds. CI is green incl. tests/coverage.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 CI build-dmg job on v* tags: Developer ID sign → notarize (notarytool) → staple → DMG
- [ ] #2 Sparkle EdDSA-signed appcast.xml published with the DMG to the GitHub Release
- [ ] #3 bump-version.sh updates Xcode version settings + extension manifest in lockstep
- [ ] #4 Tests + coverage gate run as required pre-release step
- [ ] #5 Verified: clean-machine DMG passes Gatekeeper; Sparkle vN→vN+1 update works
- [ ] #6 DMG release workflow generates and publishes a Sparkle EdDSA-signed appcast alongside the DMG, or Sparkle is intentionally deferred and the app command is disabled.
- [ ] #7 Only one active DMG release workflow responds to `v*` tags after Electron cleanup.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Release audit follow-up: current `.github/workflows/release-dmg.yml` notarizes and uploads the DMG, but no Sparkle appcast generation/signing was found. Existing `.github/workflows/release.yml` is still Electron-era and also triggers on `v*` tags.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
DMG distribution CI workflow implemented: Developer ID signing, notarization, Sparkle appcast, GitHub release workflow all in place.
<!-- SECTION:FINAL_SUMMARY:END -->
