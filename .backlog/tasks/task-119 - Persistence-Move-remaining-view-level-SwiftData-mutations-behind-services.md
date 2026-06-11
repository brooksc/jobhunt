---
id: TASK-119
title: 'Persistence: Move remaining view-level SwiftData mutations behind services'
status: Done
assignee: []
created_date: '2026-06-11 02:47'
updated_date: '2026-06-11 03:25'
labels:
  - persistence
  - swiftui
  - swiftdata
  - architecture
dependencies: []
references:
  - app/Views/Settings/ResumesTab.swift
  - app/Views/Duplicates/DuplicatesView.swift
  - app/Views/Settings/SettingsTab.swift
  - app/Views/Jobs/SaveSearchSheet.swift
  - app/Shell/Sidebar.swift
modified_files:
  - core/Services/ResumeService.swift
  - core/Services/JobService.swift
  - app/Shell/AppServices.swift
  - app/Views/Settings/ResumesTab.swift
  - app/Views/Duplicates/DuplicatesView.swift
  - app/Views/Settings/SettingsTab.swift
  - app/Views/Jobs/SaveSearchSheet.swift
  - app/Shell/Sidebar.swift
  - tests/CoreTests/ResumeServiceTests.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Several SwiftUI views still mutate SwiftData directly: resume create/edit/delete/activate, duplicate unmark/delete, availability mark-expired, saved-search insert/delete, and related direct `modelContext.save()` calls. Move these operations behind focused Core service methods so UI screens do not own persistence invariants such as one active resume, duplicate cleanup behavior, and saved-search persistence.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Resume create, edit, delete, and activate operations are routed through a Core service boundary
- [ ] #2 Saved search create/delete operations explicitly persist through a service boundary and do not rely on implicit autosave
- [ ] #3 Duplicate unmark/delete operations are routed through a service boundary with clear behavior for related data
- [ ] #4 Availability mark-expired writes are routed through a service method rather than direct view mutation
- [ ] #5 Focused tests cover the service behavior for at least resume activation, saved-search persistence, and duplicate unmark/delete
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Created ResumeService actor in Core (addResume, updateResume, deleteResume with active-promotion, setActiveResume). Added unmarkDuplicate, markExpired, insertSavedSearch, deleteSavedSearch to JobService. Added resumeService to AppServices. Updated ResumesTab, DuplicatesView, SettingsTab, SaveSearchSheet, and Sidebar to use service methods instead of direct modelContext mutations. Added ResumeServiceTests (6 tests), SavedSearchServiceTests (2 tests), and DuplicateUnmarkTests (3 tests).
<!-- SECTION:FINAL_SUMMARY:END -->
