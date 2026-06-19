---
id: TASK-498
title: >-
  Onboarding: prevent landing in a non-functional app (no provider / resume /
  extension)
status: Done
assignee: []
created_date: '2026-06-18 22:32'
updated_date: '2026-06-19 22:14'
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
- [x] #1 A user who skipped onboarding sees a persistent (dismissible) setup affordance until AI provider + résumé are configured
- [x] #2 The affordance deep-links to AI Provider settings and Resumes
- [x] #3 It disappears once the gates are satisfied; not shown to a fully-set-up user
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Added SetupChecklistCard — a first-run setup affordance that survives skipping onboarding.

- Three gated rows with deep links: AI provider → ⌘, Settings LLM tab (router.settingsTab=.llm + openSettings); Résumé → Resumes sidebar section; Browser extension → Help. Each shows a green check + strikethrough once satisfied (AC#1, AC#2).
- "Extension connected" has no dedicated signal, so the presence of any Capture is used as the proxy (captures only exist once the extension has reached the app).
- Auto-hides once an AI provider AND a résumé are configured, so a fully-set-up user never sees it (AC#3). Dismissible for the session via a new in-memory `Router.setupChecklistDismissed` — returns next launch while setup is still incomplete ("persistent until configured").
- Placed on the Dashboard (superseding the narrower orange AIConfigBanner, which was removed — the AIConfig readiness alias stays; file renamed AIConfigBanner.swift → AIConfig.swift) and the Jobs empty state.

Did not implement the optional "gate the onboarding Finish button on an AI provider" — the persistent checklist covers the skip case without blocking finish. Commit 4ea6c88. Build + fast gate + CI green.
<!-- SECTION:FINAL_SUMMARY:END -->
