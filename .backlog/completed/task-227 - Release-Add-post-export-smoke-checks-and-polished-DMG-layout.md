---
id: TASK-227
title: 'Release: Add post-export smoke checks and polished DMG layout'
status: Done
assignee: []
created_date: '2026-06-12 01:32'
updated_date: '2026-06-12 02:21'
labels:
  - release
  - packaging
  - ci
dependencies: []
references:
  - .github/workflows/release-dmg.yml
  - README.md
  - LICENSE
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The release workflow creates a bare DMG directly from the exported app. Add post-export validation and, if desired for public distribution, a conventional DMG layout with Applications symlink/readme/license.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Release workflow verifies the exported app exists, is signed, and the stapled DMG validates before uploading.
- [ ] #2 DMG creation uses a staging directory rather than the app bundle alone.
- [ ] #3 The DMG includes an Applications symlink and any required license/readme material, or the decision to keep it minimal is documented.
- [ ] #4 Release docs describe the artifact smoke checks.
<!-- AC:END -->
