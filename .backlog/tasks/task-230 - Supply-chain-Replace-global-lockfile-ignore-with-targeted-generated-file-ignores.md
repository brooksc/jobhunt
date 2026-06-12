---
id: TASK-230
title: >-
  Supply chain: Replace global lockfile ignore with targeted generated-file
  ignores
status: Done
assignee: []
created_date: '2026-06-12 01:42'
updated_date: '2026-06-12 02:16'
labels:
  - supply-chain
  - repo-hygiene
dependencies: []
references:
  - .gitignore
  - extension/package.json
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
.gitignore ignores all `*.lock` files, which can hide future package manager lockfiles that should be reviewed and committed. Replace the broad pattern with targeted ignores for known local/generated lockfiles only.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 `.gitignore` no longer ignores every `*.lock` file globally.
- [ ] #2 Expected dependency lockfiles are either committed or explicitly documented as intentionally absent.
- [ ] #3 Any local-only lockfile ignores are targeted by path/name.
- [ ] #4 CI or docs make clear which lockfiles are required for reproducible builds.
<!-- AC:END -->
