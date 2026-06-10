---
id: TASK-088
title: 'Fix SitesView: newly added sites invisible; AddSiteSheet URL validation'
status: To Do
assignee: []
created_date: '2026-06-10 07:31'
labels:
  - bug
  - ui-audit
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
HIGH: Sites created via AddSiteSheet have `state = .notReviewed` and `nextReviewAt = nil`. No section in SitesView matches this combination (Overdue/Due Soon require non-nil `nextReviewAt`; Reviewed requires `.reviewed` state; Excluded requires `.exclude`). New sites silently vanish. Fix: add a "New" or "Not Yet Reviewed" section, or set an initial nextReviewAt.

MEDIUM: AddSiteSheet has no URL format validation — any non-empty string passes, creating sites with meaningless origins. Fix: validate URL with `URL(string:)` and require a valid http/https scheme before allowing submit.

LOW: `isAdding` never reset to `false` on success path — if dismiss fails, Add button stays permanently disabled. Fix: reset on both success and failure.

Files: `app/Views/Sites/SitesView.swift`, `app/Views/Sites/AddSiteSheet.swift`
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Newly added sites appear in the list immediately after creation
- [ ] #2 Submitting an invalid URL shows an inline error rather than creating a broken site
- [ ] #3 isAdding is always reset after submit attempt (success or failure)
<!-- AC:END -->
