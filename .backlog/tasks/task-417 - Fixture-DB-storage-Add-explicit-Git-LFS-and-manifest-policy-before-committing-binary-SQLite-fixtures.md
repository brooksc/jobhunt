---
id: TASK-417
title: >-
  Fixture DB storage: Add explicit Git/LFS and manifest policy before committing
  binary SQLite fixtures
status: To Do
assignee: []
created_date: '2026-06-13 03:22'
labels:
  - audit
  - repo-hygiene
  - tests
  - fixtures
  - git
dependencies: []
references:
  - docs/test-db-spec.md
  - .gitignore
  - tests/fixtures
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The fixture database plan proposes committing `tests/fixtures/jobhunt-test.sqlite` and mentions Git LFS if it grows beyond 5 MB, but there is no `.gitattributes` or committed manifest policy yet. Land a clear storage/review policy before introducing binary fixture databases so fixture changes remain reviewable and portable.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A `.gitattributes` policy exists for SQLite fixture files if they are committed directly or via Git LFS.
- [ ] #2 The fixture generation process emits a deterministic JSON manifest alongside the SQLite fixture.
- [ ] #3 Docs explain how reviewers should inspect fixture changes.
- [ ] #4 CI validates that the manifest and SQLite fixture are in sync when fixture files are present.
<!-- AC:END -->
