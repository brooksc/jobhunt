---
id: TASK-233
title: 'Repo hygiene: Remove or formalize tracked generated release/build artifacts'
status: To Do
assignee: []
created_date: '2026-06-12 01:44'
labels:
  - repo-hygiene
  - release
  - supply-chain
dependencies: []
references:
  - .gitignore
  - build/
  - chromestore/
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Generated build/release files under build/ are tracked even though build/ is ignored. Decide whether these are canonical templates or generated artifacts, then either move them to a templates location or remove them from source control.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Tracked build/ artifacts are either removed from source control or moved/renamed as canonical templates.
- [ ] #2 Release workflows use canonical templates if templates are kept.
- [ ] #3 `.gitignore` and release docs match the chosen artifact ownership model.
- [ ] #4 A clean checkout can regenerate any removed generated files through documented commands.
<!-- AC:END -->
