---
id: TASK-189
title: 'Release: Keep extension payload version in sync with manifest'
status: Done
assignee: []
created_date: '2026-06-11 23:41'
updated_date: '2026-06-11 23:55'
labels:
  - audit
  - release
  - extension
  - versioning
dependencies: []
references:
  - extension/manifest.json
  - extension/capture.js
  - scripts/bump-version.sh
  - extension/tests
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The extension manifest is versioned independently, but capture payloads currently report a hard-coded `extension_version` that is out of sync with `manifest.json`. Replace the hard-coded value with `chrome.runtime.getManifest().version` or a build-time injected value, and add a test so future releases cannot drift.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Captured payloads report the extension manifest version or a single generated version source.
- [x] #2 The version bump process updates every version source or fails if any drift is detected.
- [x] #3 Extension tests cover payload version synchronization.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
capture.js now reads `chrome.runtime.getManifest().version` (with a fallback to "unknown" when chrome is unavailable). Added extension/tests/test_capture_version.js with 4 tests: no hardcoded version, uses getManifest, valid semver, simulated version matches manifest. Test added to package.json test script.
<!-- SECTION:FINAL_SUMMARY:END -->
