---
id: TASK-192
title: 'Release: Move code signing entitlements out of build output paths'
status: Done
assignee: []
created_date: '2026-06-11 23:43'
updated_date: '2026-06-11 23:55'
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
- [x] #1 Code signing entitlement files live under a source-owned, non-generated path.
- [x] #2 Project.swift references the new entitlement paths for DMG and MAS configurations.
- [x] #3 Build/release documentation no longer treats required signing inputs as build artifacts.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Created config/entitlements/Jobhunt-DMG.entitlements and config/entitlements/Jobhunt-MAS.entitlements. Updated all four CODE_SIGN_ENTITLEMENTS entries and the dmgEntitlements/masEntitlements Path constants in Project.swift. config/ is tracked by git; the old build/ paths are gitignored build artifacts.
<!-- SECTION:FINAL_SUMMARY:END -->
