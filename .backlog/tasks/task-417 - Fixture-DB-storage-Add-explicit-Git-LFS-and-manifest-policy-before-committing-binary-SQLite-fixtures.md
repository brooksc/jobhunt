---
id: TASK-417
title: >-
  Fixture DB storage: Add explicit Git/LFS and manifest policy before committing
  binary SQLite fixtures
status: Done
assignee: []
created_date: '2026-06-13 03:22'
updated_date: '2026-06-15 18:43'
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
modified_files:
  - .gitattributes
  - tests/fixtures/jobhunt-test.manifest.json
  - scripts/build-fixture-db.sh
  - .github/workflows/swift-build.yml
  - docs/test-db-spec.md
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The fixture database plan proposes committing `tests/fixtures/jobhunt-test.sqlite` and mentions Git LFS if it grows beyond 5 MB, but there is no `.gitattributes` or committed manifest policy yet. Land a clear storage/review policy before introducing binary fixture databases so fixture changes remain reviewable and portable.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A `.gitattributes` policy exists for SQLite fixture files if they are committed directly or via Git LFS.
- [x] #2 The fixture generation process emits a deterministic JSON manifest alongside the SQLite fixture.
- [x] #3 Docs explain how reviewers should inspect fixture changes.
- [x] #4 CI validates that the manifest and SQLite fixture are in sync when fixture files are present.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Landed the fixture storage policy. .gitattributes marks tests/fixtures/*.sqlite as binary (committed directly to git — the fixture is 356KB, well under the 5MB LFS threshold the spec mentions) (AC#1). build-fixture-db.sh now emits tests/fixtures/jobhunt-test.manifest.json (sha256 + size + provenance) alongside the SQLite; generated it for the current fixture (AC#2). docs/test-db-spec.md adds a Storage policy section explaining reviewers inspect changes via the manifest diff + the FixtureSeeder/CoreTests-FixtureTests source of truth (AC#3). A new swift-build.yml "Verify fixture matches manifest" step recomputes the committed .sqlite sha256 and fails if it != the manifest, so they can't drift (AC#4). YAML + shell validated; sha matches.
<!-- SECTION:FINAL_SUMMARY:END -->
