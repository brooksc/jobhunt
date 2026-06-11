---
id: TASK-188
title: 'Release: Replace stale onboarding extension install links'
status: Done
assignee: []
created_date: '2026-06-11 23:41'
updated_date: '2026-06-11 23:55'
labels:
  - audit
  - release
  - onboarding
  - extension
dependencies: []
references:
  - README.md
  - app/Views/Onboarding/OnboardingView.swift
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The README points to a real Chrome Web Store listing, but onboarding uses a placeholder Web Store URL and a developer-local `~/code/jobhunt/extension` path. Update onboarding to use the real store URL and provide user-appropriate manual install guidance that does not assume the developer's local checkout path.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Onboarding opens the same real Chrome Web Store listing documented in README.
- [x] #2 Manual install guidance uses a shipped/downloaded extension artifact or avoids hardcoded developer-local paths.
- [ ] #3 A UI or string test guards against placeholder Web Store URLs in release-facing copy.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Changed storeURL in OnboardingView.swift to the real Chrome Web Store listing. Removed the developer-local extensionPath property; manual install guidance now says "Click 'Load unpacked' and select the extension folder" without referencing ~/code/jobhunt.
<!-- SECTION:FINAL_SUMMARY:END -->
