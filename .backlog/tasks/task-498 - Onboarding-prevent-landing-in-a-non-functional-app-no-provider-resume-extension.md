---
id: TASK-498
title: >-
  Onboarding: prevent landing in a non-functional app (no provider / resume /
  extension)
status: To Do
assignee: []
created_date: '2026-06-18 22:32'
labels:
  - ux
  - onboarding
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
A new user can Skip every onboarding step and end up unable to extract (no AI provider), score (no resume), or capture (no extension) — with no persistent in-app affordance telling them they're not set up. (TASK-483 added a capture-time "no provider" notice, which partially helps the provider case.)

Scope: add a lightweight "you're not set up yet" path that survives skipping onboarding — e.g. a dismissible setup banner / checklist on the Dashboard (and/or Jobs empty state) showing the 3 gates (AI provider, résumé, extension) with deep links, that disappears once each is satisfied. Optionally gate the onboarding finish button to require at least an AI provider. Keep it non-nagging.

References: app/Views/Onboarding/**, app/Views/Dashboard/DashboardView.swift, app/Views/Jobs/JobsView.swift (empty state added in batch), Settings AI Provider + Resumes.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A user who skipped onboarding sees a persistent (dismissible) setup affordance until AI provider + résumé are configured
- [ ] #2 The affordance deep-links to AI Provider settings and Resumes
- [ ] #3 It disappears once the gates are satisfied; not shown to a fully-set-up user
<!-- AC:END -->
