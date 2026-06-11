---
id: TASK-187
title: 'Release: Package and publish the Chrome extension with app releases'
status: To Do
assignee: []
created_date: '2026-06-11 23:40'
labels:
  - audit
  - release
  - extension
  - ci
dependencies: []
references:
  - scripts/package-extension.sh
  - .github/workflows/release-dmg.yml
  - .github/workflows/release-mas.yml
  - extension/manifest.json
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The browser extension is core to the capture workflow and has a packaging script, but tag release workflows only publish the DMG and MAS pkg. Add extension packaging to the release process and define whether the Chrome Web Store upload is automated, attached to GitHub Releases, or documented as a required manual step.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Release workflow produces a versioned extension zip or explicitly invokes a documented Chrome Web Store publication step.
- [ ] #2 The packaged extension version matches the app release version policy.
- [ ] #3 Release documentation lists the extension artifact/publication step and owner.
<!-- AC:END -->
