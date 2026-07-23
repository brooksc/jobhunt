---
id: TASK-644
title: 'Referral request lifecycle: 4 states, per-state dates, N/A, dashboard nudges'
status: Done
assignee: []
created_date: '2026-07-23 17:02'
updated_date: '2026-07-23 17:09'
labels:
  - referrals
  - workflow
  - ux
  - dashboard
dependencies: []
references:
  - core/Services/ReferralTracking.swift
  - core/Models/ReferralAttempt.swift
  - core/Services/BackgroundStore.swift
  - app/Views/Referral/ReferralViews.swift
  - app/Views/Referral/ReferralAttemptEditor.swift
  - core/Services/DashboardMetrics.swift
  - app/Views/Dashboard
modified_files:
  - core/Services/ReferralTracking.swift
  - core/Models/ReferralAttempt.swift
  - core/Services/BackgroundStore.swift
  - app/Views/Referral/ReferralViews.swift
  - app/Views/Referral/ReferralAttemptEditor.swift
  - app/Views/Dashboard/DashboardReferralCard.swift
  - app/Views/Dashboard/DashboardView.swift
  - app/Views/Jobs/JobsView.swift
  - app/Shell/Router.swift
  - tests/CoreTests/ReferralTrackingTests.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Evolve the TASK-630 referral tracking into an explicit per-request lifecycle so the user can distinguish asking someone from that person actually submitting the referral, track multiple parallel requests, and get reminded to follow up.

Per-request states (each stamps its own date; user can revert to a prior state to fix mistakes): Requested → Responded (they agreed, no evidence yet) → Submitted (confirmed in the company's system), or Declined. Job-level "N/A — no referral possible" marker covers both "I chose not to pursue" and "no contact to ask," and suppresses the needs-outreach nudge. Recipient name + optional link are free text.

Phase 1 (DONE, commit 0351a7f): core model (ReferralOutcome 4 states + N/A, per-state optional dates on ReferralAttempt, backward-compatible raw values), normalizedDates/stateDate pure helpers with revert-clears-later semantics, editor with status picker + per-state timeline, badge/summary for new states, N/A rename in store + UI, unit tests.

Phase 2 (THIS): dashboard discovery + follow-up nudges — surface "applied but no referral requested yet" (funnel status, no request, not N/A) as a one-click count wired to the existing needsReferralOutreach Jobs filter; surface stale requests ("requested N days ago, follow up?" and "responded but not submitted M days"). Default thresholds hard-coded (Requested→no response 4 days; Responded→not submitted 7 days).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A referral request tracks 4 states (Requested/Responded/Submitted/Declined), each with its own date, and the user can revert to an earlier state which clears the later dates
- [x] #2 Multiple parallel requests per job are supported; the job's rolled-up referral badge shows the best state (submitted > responded > requested > declined)
- [x] #3 A job-level N/A marker (no referral possible) suppresses the needs-outreach nudge and covers both 'chose not to' and 'no contact'
- [x] #4 Raw values remain backward-compatible so referral requests recorded under TASK-630 still decode (submitted=referred, N/A=not_pursuing)
- [x] #5 The dashboard surfaces jobs that are applied (in-funnel) with no referral request yet and not N/A, as a one-click way to find them (wired to the existing needsReferralOutreach Jobs filter)
- [x] #6 The dashboard surfaces stale requests as follow-up reminders: Requested with no response after 4 days, and Responded but not Submitted after 7 days
- [x] #7 Pure lifecycle helpers (state precedence, per-state date normalization, follow-up staleness) are unit tested
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Shipped in two commits.

**Phase 1 — 4-state lifecycle (0351a7f):** ReferralOutcome is now Requested → Responded → Submitted (or Declined), plus a job-level N/A marker (folds the old "not pursuing"; covers both "chose not to" and "no contact"). ReferralAttempt gained optional respondedAt/submittedAt/declinedAt (lightweight SwiftData migration). Raw values stay backward-compatible (submitted="referred", N/A="not_pursuing"). Editor: status picker + per-state timeline; reverting to an earlier state clears later dates via the pure ReferralTracking.normalizedDates helper. Summary rollup across parallel requests: submitted > responded > requested > declined.

**Phase 2 — dashboard discovery + nudges (5b00c88):** DashboardReferralCard (self-contained, renders nothing when empty) surfaces (a) "N applied — no referral requested yet" → one click opens Jobs pre-filtered to needs-outreach via a new one-shot Router.focusReferralOutreach flag JobsView consumes; and (b) stale-request follow-ups ("Requested Nd ago — no response, follow up?" / "Responded Nd ago — awaiting submission"), most-overdue first. Thresholds are ReferralTracking.followUp defaults (no-response 4d; responded-not-submitted 7d); a recent response supersedes an older request to another contact.

Pure helpers (summary precedence, normalizedDates, stateDate, followUp, legacy raw-value decoding) unit-tested in ReferralTrackingTests (18 tests). Full fast gate green; app builds + launches.

Not done (optional, deferred): user-configurable thresholds — hard-coded sensible defaults for v1, as planned. UI-level tests for the editor/dashboard (app module) are not covered; the derivations they call are.
<!-- SECTION:FINAL_SUMMARY:END -->
