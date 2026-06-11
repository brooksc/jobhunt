---
id: TASK-190
title: 'Release: Wire or remove the DMG Check for Updates menu item'
status: To Do
assignee: []
created_date: '2026-06-11 23:42'
labels:
  - audit
  - release
  - updates
  - ux
dependencies: []
references:
  - app/JobhuntApp.swift
  - app/Platform/SparkleUpdater.swift
  - .github/workflows/release-dmg.yml
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
DMG builds expose a Check for Updates menu item, but `SparkleUpdater.checkForUpdates()` only logs a stub. Either integrate Sparkle/appcast support end to end or hide/remove the menu item until update checking actually works.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The Check for Updates command performs a real update check in DMG builds, or the command is not visible in release builds.
- [ ] #2 If Sparkle is wired, release automation produces/signs the required appcast artifacts.
- [ ] #3 Tests or build-time checks prevent shipping a visible no-op updater command.
<!-- AC:END -->
