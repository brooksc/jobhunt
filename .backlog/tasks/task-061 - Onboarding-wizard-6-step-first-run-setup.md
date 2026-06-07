---
id: TASK-061
title: 'Onboarding wizard: 6-step first-run setup'
status: To Do
assignee: []
created_date: '2026-06-07 22:51'
labels:
  - swift-rewrite
  - ui
  - screen
milestone: m-1
dependencies:
  - TASK-045
  - TASK-035
  - TASK-042
  - TASK-056
documentation:
  - swift-plan.md
  - static/onboarding.jsx
priority: medium
ordinal: 3800
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Goal: Port the 6-step onboarding wizard shown on first run / incomplete settings.

## Read first
- swift-plan.md §10.2 (onboarding listed under screens) and §3 of the frontend (onboarding flow), §13.3 (consent during provider step).
- Legacy static/onboarding.jsx (576 lines) — steps: 1 Welcome (+ demo mode), 2 Chrome extension (link + manual fallback), 3 AI provider (choose + configure + test + fetch models), 4 Location preferences (+ toggles), 5 Resume upload (+ active), 6 Finish (recap). Step dots, back/continue/skip, provider consent dialog.

## Implement (app/Views/Onboarding/)
- A 6-step wizard reusing Settings components (provider config/test from task-056, consent modal, resume import) and SettingsStore; demo-mode entry (task-040); persists completion; shows on first launch / when settings incomplete.

## Dependencies
Depends on task-045 (shell/components), task-035 (settings), task-042 (provider test/model fetch), task-056 (reuse provider/consent/resume UI). 

## Tests (AppUITests)
- Full flow completes and persists; skip paths work; provider step tests connection + records consent; demo-mode entry from step 1.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 6 steps reproduce onboarding.jsx (Welcome/Extension/Provider/Location/Resume/Finish) with step dots + back/continue/skip
- [ ] #2 Provider step configures + tests + fetches models + records consent
- [ ] #3 Demo-mode entry from Welcome; completion persists and gates first-run display
- [ ] #4 XCUITest covers full-flow completion and skip paths
<!-- AC:END -->
