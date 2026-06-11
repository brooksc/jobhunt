---
id: TASK-192
title: 'Release: Move code signing entitlements out of build output paths'
status: To Do
assignee: []
created_date: '2026-06-11 23:43'
labels:
  - audit
  - release
  - codesigning
  - maintenance
dependencies: []
references:
  - Project.swift
  - build/Jobhunt-DMG.entitlements
  - build/Jobhunt-MAS.entitlements
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`Project.swift` references tracked entitlement files under `build/`, which is also used for generated build output. Move entitlements to a source-owned directory such as `config/entitlements/` or `app/Entitlements/` so cleanup scripts and developer expectations do not risk deleting required signing inputs.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Code signing entitlement files live under a source-owned, non-generated path.
- [ ] #2 Project.swift references the new entitlement paths for DMG and MAS configurations.
- [ ] #3 Build/release documentation no longer treats required signing inputs as build artifacts.
<!-- AC:END -->
