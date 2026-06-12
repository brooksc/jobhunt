---
id: TASK-303
title: 'Sites: Create SiteReview history for manual mark-reviewed actions'
status: Done
assignee: []
created_date: '2026-06-12 05:01'
updated_date: '2026-06-12 05:27'
labels:
  - audit
  - sites
  - history
dependencies: []
references:
  - core/Services/SiteService.swift
  - app/Views/Sites/SiteDetailView.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Extension/HTTP site review creates a SiteReview record, but manual Mark Reviewed only updates the Site row. Review history is incomplete depending on the entry point used.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Manual mark-reviewed actions create a SiteReview history record consistent with extension/HTTP reviews.
- [ ] #2 Site lastReviewedAt, nextReviewAt, state, and review history stay consistent after manual review.
- [ ] #3 Add tests covering manual mark-reviewed history creation.
<!-- AC:END -->
