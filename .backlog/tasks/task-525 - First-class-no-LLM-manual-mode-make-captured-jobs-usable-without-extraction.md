---
id: TASK-525
title: 'First-class no-LLM / manual mode: make captured jobs usable without extraction'
status: Done
assignee: []
created_date: '2026-06-19 04:45'
updated_date: '2026-06-19 21:58'
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
- [x] #1 A job with no extracted title displays its captured page title (and domain as a company hint) instead of "Untitled", consistently across Jobs list, detail header, Dashboard, Needs Action, and Duplicates
- [x] #2 The fallback title is used for sorting and search, not just display
- [x] #3 An un-extracted job in the detail inspector offers a discoverable path to enter company/title/location/salary manually (especially when no AI provider is configured)
- [x] #4 The fit ring/score is visually neutralized (not a perpetual empty placeholder) when there is no LLM or no active resume
- [x] #5 The fallback is display-only and does not overwrite extraction-owned fields (re-extraction still populates them normally)
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Made "no LLM / pre-extraction" a supported mode rather than a degraded-looking one.

- **Display fallbacks** (`Job.displayTitle`/`displayCompany`/`captureHost`, core/Models/Job+Display.swift, 9 unit tests): extracted value → captured page title → capture host → "Untitled". Computed at read time, so extraction-owned stored fields are never touched (AC#5) and AI users benefit too (jobs legible before the LLM finishes). Wired the four render sites: Jobs row, detail header, Dashboard ×2 (AC#1).
- **Sort & search** use the same fallbacks (AC#2): JobsSortLogic .title/.company cases → displayTitle/displayCompany; the cheap-field search array too — un-extracted jobs sort by page title and match a page-title/domain search instead of collapsing to the bottom / being unfindable.
- **Fit ring neutralized** when no AI provider or no active résumé (AC#4): added a `fitScoringAvailable` signal to the Jobs row and JobDetailView OverviewTabView — the row renders no ring and the detail header shows "Fit unavailable" instead of a forever-pending sparkle placeholder. Dashboard already only drew a ring when a score existed.
- **Discoverable manual entry** (AC#3): the inline editable Company/Title/Location/URL rows already existed; added a non-nagging hint above them (shown only when no AI provider is configured and the job is still empty) pointing to manual entry with a SettingsLink to set up AI.

Commits: 25d40c4 (display), 27a427f (sort/search), d624c6e (fit ring), c3dbc7e (manual entry). Build + fast gate green; CI green.
<!-- SECTION:FINAL_SUMMARY:END -->
