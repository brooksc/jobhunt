---
id: TASK-101
title: Clean up git hygiene for generated build artifacts
status: Done
assignee: []
created_date: '2026-06-10 07:49'
updated_date: '2026-06-11 01:38'
labels:
  - audit
  - repo-hygiene
dependencies: []
references:
  - .gitignore
  - build/
  - Derived/
  - Project.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Audit finding: repo-local `build/` and `Derived/` artifacts are untracked in the worktree, while `.gitignore` only covers some Xcode/Tuist outputs such as `DerivedData/`, `*.xcodeproj`, and `*.xcworkspace`. Decide which generated files are intentionally tracked and keep machine-local outputs out of normal `git status`.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Repo-local machine-generated build outputs no longer appear as untracked files after a normal local build/test cycle.
- [ ] #2 Any generated files that must remain tracked are documented or clearly exempted from ignore rules.
- [ ] #3 Ignore rules do not hide source files, project configuration, assets, or distribution files that should be reviewed.
- [ ] #4 A clean-status check after build/test shows only intentional source changes.
<!-- AC:END -->
