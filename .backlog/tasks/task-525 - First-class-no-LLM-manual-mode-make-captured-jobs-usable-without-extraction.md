---
id: TASK-525
title: 'First-class no-LLM / manual mode: make captured jobs usable without extraction'
status: To Do
assignee: []
created_date: '2026-06-19 04:45'
labels:
  - ux
  - llm
  - jobs
dependencies:
  - TASK-498
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Without an AI provider configured (or before extraction runs), the app is still a competent *manual* job tracker — capture+save with full raw text, manual field entry, the full status pipeline, notes/reminders/ratings, search (incl. raw text), hash-based dedup, HTTP availability auto-expiry, CSV export, backup/restore are all LLM-free. But the UI is designed assuming AI, so the no-LLM state looks broken: every job renders as "Untitled" with empty company/salary and a dead fit ring, and there's no guidance to fill details in manually.

Goal: make "no LLM" a deliberately supported mode rather than an accidental degraded state.

Scope:
1. **Title/company fallback.** Jobs render `job.title ?? "Untitled"` with no fallback, even though `capture.pageTitle` + URL/domain exist (Sites already fall back to pageTitle — SiteDetailView.swift:30 — Jobs don't). Fall back to the captured page title for display, and use it for sorting/searching too; use the capture domain as a company hint. This helps AI users as well (jobs are legible before extraction finishes). Decide whether to persist a fallback or compute it at display time (display-time avoids muddying extraction-owned fields).
2. **Discoverable manual entry.** On a job that hasn't been (and won't be) extracted, surface a clear "No AI configured — add details" affordance that jumps to the editable fields, rather than leaving the inspector looking empty.
3. **Neutralize the dead fit ring** when there's no LLM/active resume (don't show an empty score placeholder as if a score is pending forever).
4. Optional: a one-time/dismissible note that the app works as a manual tracker without AI (ties into onboarding TASK-498).

Verify each surface: JobsView row (JobsView.swift:914), JobDetailView header (:163), Dashboard (:173/:234), Needs Action, LLM Queue, Duplicates — all currently use `title ?? "Untitled"`/"—".

References: app/Views/Jobs/JobsView.swift, app/Views/Detail/JobDetailView.swift, app/Views/Components/FitRingView.swift, app/Views/Dashboard/DashboardView.swift, core/Models/Job.swift, core/Models/Capture.swift.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A job with no extracted title displays its captured page title (and domain as a company hint) instead of "Untitled", consistently across Jobs list, detail header, Dashboard, Needs Action, and Duplicates
- [ ] #2 The fallback title is used for sorting and search, not just display
- [ ] #3 An un-extracted job in the detail inspector offers a discoverable path to enter company/title/location/salary manually (especially when no AI provider is configured)
- [ ] #4 The fit ring/score is visually neutralized (not a perpetual empty placeholder) when there is no LLM or no active resume
- [ ] #5 The fallback is display-only and does not overwrite extraction-owned fields (re-extraction still populates them normally)
<!-- AC:END -->
