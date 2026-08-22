---
id: TASK-503
title: Sites review workflow clarity + Data Quality inline fixes
status: To Do
assignee: []
created_date: '2026-06-18 23:06'
updated_date: '2026-08-22 22:49'
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
- [x] #1 Sites: inline Mark-Reviewed + clearer cadence affordance + re-enable for excluded sites
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

**2026-08-22 — AC #1 done.** The Sites row now carries the actions rather than the detail pane:

- **Mark Reviewed** inline on every row. Opening the detail pane to record "yes, I swept this" was most of the work of the interaction being recorded.
- **An explainer under the Overdue section** — what overdue means and that reviewing restarts the clock. A red "Overdue 6d" with no context reads as an error rather than the nudge it is.
- **Re-enable** on an excluded row. Exclude was a one-way door: nothing in the UI could undo it.

All three use `SiteService` methods that already existed (`markReviewed`, `setSiteState`) — this was purely a missing affordance, not missing capability. A double-click can't enqueue the work twice.

Not done, and deliberately: the wider redesign of the screen around due/not-due that the design note contemplates. These are the three concrete affordances the acceptance criterion actually lists.

not verified: (visual) — the row layout with the new button, and the footer wording in place, have not been seen rendered.

**#2 (Data Quality inline fixes) remains open** and, per the design note, is a separate concern that should be split out rather than designed here.
<!-- SECTION:NOTES:END -->
