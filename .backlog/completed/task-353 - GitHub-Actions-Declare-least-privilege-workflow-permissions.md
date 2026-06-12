---
id: TASK-353
title: 'GitHub Actions: Declare least-privilege workflow permissions'
status: Done
assignee: []
created_date: '2026-06-12 20:43'
updated_date: '2026-06-12 21:53'
labels:
  - audit
  - supply-chain
  - github-actions
  - permissions
dependencies: []
references:
  - .github/workflows/release-dmg.yml
  - .github/workflows/release-mas.yml
  - .github/workflows/swift-build.yml
  - .github/workflows/llm-eval.yml
  - .github/workflows/version-parity.yml
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Workflows do not declare top-level or job-level permissions. Release jobs use GITHUB_TOKEN and other jobs perform checkout/artifact operations under GitHub defaults instead of explicit least privilege.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Each workflow declares minimal required permissions at workflow or job level.
- [ ] #2 Release upload jobs grant contents: write only where needed.
- [ ] #3 Build/test/eval jobs use read-only contents permissions unless a stronger permission is justified.
<!-- AC:END -->
