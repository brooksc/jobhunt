---
id: TASK-073
title: 'HIG-11: Move SiteDetailView to NavigationSplitView detail column'
status: To Do
assignee: []
created_date: '2026-06-09 03:00'
labels:
  - hig
  - moderate
  - navigation
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
SitesPaneView uses HSplitView nested inside the NavigationSplitView content column, bypassing the detail column. Promote SiteDetailView to the detail column using router.selectedSiteID, consistent with how Jobs works.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 SiteDetailView rendered in NavigationSplitView detail column
- [ ] #2 HSplitView removed from SitesPaneView
- [ ] #3 router.selectedSiteID drives the detail column
<!-- AC:END -->
