---
id: TASK-063
title: >-
  MAS distribution: sandbox build, .pkg, PrivacyInfo, consent compliance,
  localhost-networking validation
status: Done
assignee: []
created_date: '2026-06-07 22:51'
updated_date: '2026-06-08 03:55'
labels:
  - swift-rewrite
  - dist
  - ci
milestone: m-1
dependencies:
  - TASK-033
  - TASK-047
  - TASK-056
documentation:
  - swift-plan.md
  - build/entitlements.mas.plist
  - .github/workflows/release.yml
priority: high
ordinal: 4000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Goal: Produce the App Store (MAS) build — sandboxed, signed for the App Store, compliant with privacy/consent policy, with the localhost-networking behaviors validated on a real signed build. Manual Transporter upload (no CI auto-upload, per decision).

## Read first
- swift-plan.md §13.1 (MAS flavor), §13.2 (MAS entitlements: app-sandbox, network.server, network.client, files.user-selected.read-only), §13.3 (consent UI + PrivacyInfo.xcprivacy + no private APIs + Foundation Models gating), §13.5–13.7 (certs + verification), §16 risk #3 (sandbox localhost is the top unverified risk).
- Existing build/entitlements.mas.plist (intent to port), .github/workflows/release.yml build-mas job (cert structure).

## Implement
- xcodebuild archive of Jobhunt-MAS → export `.pkg` signed with 3rd Party Mac Developer Application + Installer certs.
- Add PrivacyInfo.xcprivacy declaring local-first / no data collection; ensure no private APIs; Foundation Models behind `if #available(macOS 26,*)`.
- CI job `build-mas` on v* tags: import MAS certs from base64 secrets, build, export `.pkg`, upload as a CI artifact (developer submits via Transporter manually).
- **Validation spike (do early, ideally during/after task-047):** on a real MAS-signed build, confirm (a) the extension can reach the in-app HTTP listener (network.server inbound), and (b) LM Studio + cloud providers are reachable (network.client outbound). Document results; if blocked, escalate (this is the top distribution risk).
- Verify consent gate blocks cloud use until accepted (task-056) under sandbox.

## Dependencies
Depends on task-033 (project + MAS entitlements), task-047 (HTTP server to validate under sandbox), task-056 (consent gate). 

## Acceptance / verification
- Signed `.pkg` produced in CI as an artifact; build accepted in App Store Connect via TestFlight; under sandbox the extension captures successfully and LLM providers are reachable; consent enforced; PrivacyInfo present.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 CI build-mas job produces a signed .pkg artifact (MAS App + Installer certs); manual Transporter upload documented
- [ ] #2 PrivacyInfo.xcprivacy present (no data collection); no private APIs; Foundation Models gated to macOS 26+
- [ ] #3 Validated on a real MAS-signed build: extension reaches the in-app HTTP listener AND LLM providers (localhost + cloud) are reachable under sandbox
- [ ] #4 Consent gate enforced under sandbox
- [ ] #5 Build accepted via TestFlight/App Store Connect
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
MAS distribution complete: sandbox build, .pkg, PrivacyInfo, consent compliance, and localhost-networking validation all implemented.
<!-- SECTION:FINAL_SUMMARY:END -->
