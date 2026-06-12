---
id: TASK-346
title: 'CI: Add an automated AppUITests smoke lane'
status: To Do
assignee: []
created_date: '2026-06-12 20:39'
labels:
  - audit
  - tests
  - ci
  - ui-tests
dependencies: []
references:
  - tests/AppUITests
  - .github/workflows/swift-build.yml
  - .github/workflows/release-dmg.yml
  - .github/workflows/release-mas.yml
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The repository has 29 AppUITests, but PR and release workflows explicitly exclude them and there is no scheduled UI workflow. UI/navigation/settings/export regressions depend on manual execution.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A scheduled macOS workflow or lightweight PR smoke lane runs a focused AppUITests subset.
- [ ] #2 The lane publishes xcresult/screenshots on failure for diagnosis.
- [ ] #3 Release documentation identifies which UI lane must be green before tagging.
<!-- AC:END -->
