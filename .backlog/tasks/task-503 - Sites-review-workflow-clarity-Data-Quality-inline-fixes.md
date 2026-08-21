---
id: TASK-503
title: Sites review workflow clarity + Data Quality inline fixes
status: To Do
assignee: []
created_date: '2026-06-18 23:06'
updated_date: '2026-08-21 02:24'
labels:
  - ux
  - sites
  - data-quality
dependencies: []
priority: medium
ordinal: 5000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Two punted review areas to think through later:

#16 — Sites review cadence is unclear: "Overdue 6d" with no inline "Mark Reviewed" (must open the detail), no explanation that reviewing resets the clock, and "Exclude" has no re-enable. Improve: inline Mark-Reviewed action in the row, a one-line explainer when sites are overdue, a clearer "Check every N days" affordance, and a Re-enable button for excluded sites.

#17 — Data Quality lists issues you can't fix inline (e.g. "Missing company" with no field to type it; only re-extract — which re-fails on a dead source URL — or mark-reviewed which just hides it). Add quick-fix affordances: inline edit for missing fields, and surface the extraction error + a manual-entry path when re-extraction isn't viable.

References: app/Views/Sites/SitesView.swift, app/Views/Sites/SiteDetailView.swift, core/Services/SiteService.swift, app/Views/Quality/DataQualityView.swift.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Sites: inline Mark-Reviewed + clearer cadence affordance + re-enable for excluded sites
- [ ] #2 Data Quality: at least the common missing-field issues can be fixed inline (or via a clear manual-entry path)
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## The design question is answered (user, 2026-08-20)

The Sites screen is a **scan log with a reminder**, not a data-quality surface:

> 'a way to bookmark what sites I should and have scanned. e.g. I was on Netflix today, went through all the relevant jobs and I wanted to mark it as done. The intent is it would give me a reminder after 30d to maybe check the site again.'

So the object is a *site I periodically sweep*, and the two verbs are **mark swept** and **remind me when it's due again**. The existing siteReviewIntervalDays setting is already that interval; the screen should be built around due/not-due rather than around review workflow abstractions.

Reported alongside: the user could not find the mark-reviewed action **in Brave**. The extension does implement it (markSiteReviewed, with a payload-contract test against the Swift server), so the question is where it is surfaced and whether it is reachable in a Chromium browser that isn't Chrome — worth confirming before redesigning the screen, since 'mark this site done from the browser I'm already in' is the core interaction of the feature as described.

Data-quality inline fixes were bundled into this task's original scope; on the description above they are a separate concern and should be split rather than designed in.
<!-- SECTION:NOTES:END -->
