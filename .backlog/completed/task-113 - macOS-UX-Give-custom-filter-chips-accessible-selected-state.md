---
id: TASK-113
title: 'macOS UX: Give custom filter chips accessible selected state'
status: Done
assignee: []
created_date: '2026-06-11 02:24'
updated_date: '2026-06-11 03:10'
labels:
  - ux
  - macos
  - accessibility
  - filters
dependencies: []
references:
  - app/Views/Jobs/JobsView.swift
  - app/Views/Quality/DataQualityView.swift
modified_files:
  - app/Views/Jobs/JobsView.swift
  - app/Views/Quality/DataQualityView.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Jobs and Data Quality filters use plain buttons styled as chips. Their selected state is conveyed mainly through color, weight, and background styling, which is weaker than native controls for VoiceOver and keyboard users. Replace these with native controls where practical, or add explicit accessibility labels, values, and selected-state semantics.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Jobs filter chips expose active/inactive state through VoiceOver, not color alone
- [ ] #2 Data Quality issue filter chips expose active/inactive state through VoiceOver, not color alone
- [ ] #3 Keyboard users can move through and activate filter options predictably
- [ ] #4 Where native `Toggle`, `Picker`, or segmented controls fit the interaction, they are preferred over plain styled buttons
- [ ] #5 Focused tests or accessibility inspection notes cover at least one Jobs filter and one Data Quality filter
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Added `.accessibilityAddTraits(active ? .isSelected : [])` and `.accessibilityValue(active ? "on" : "off")` to all filter chip buttons in JobsView (remoteToggle, fitScoreChip, ratingChip, salaryChip, recentChip) and DataQualityView (filterChip). VoiceOver now announces selected state rather than relying on color alone.
<!-- SECTION:FINAL_SUMMARY:END -->
