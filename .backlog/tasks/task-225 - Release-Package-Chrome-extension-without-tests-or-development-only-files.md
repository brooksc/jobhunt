---
id: TASK-225
title: 'Release: Package Chrome extension without tests or development-only files'
status: To Do
assignee: []
created_date: '2026-06-12 01:32'
labels:
  - release
  - extension
  - packaging
dependencies: []
references:
  - scripts/package-extension.sh
  - extension/manifest.json
  - docs/chrome-web-store-review.md
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
scripts/package-extension.sh currently zips the full extension directory, which includes tests and package metadata. Build a minimal Chrome Web Store package containing only runtime extension files and icons.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Packaged extension zip excludes tests, package.json, and other development-only files.
- [ ] #2 The package script uses an explicit allowlist or staging directory so new files are deliberately included.
- [ ] #3 CI or the package script lists/validates zip contents before upload.
- [ ] #4 Chrome Web Store review docs reflect the packaging process.
<!-- AC:END -->
