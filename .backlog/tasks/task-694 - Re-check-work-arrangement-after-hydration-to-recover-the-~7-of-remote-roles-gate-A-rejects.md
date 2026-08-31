---
id: TASK-694
title: >-
  Re-check work arrangement after hydration, to recover the ~7% of remote roles
  gate A rejects
status: Done
assignee: []
created_date: '2026-08-31 18:00'
updated_date: '2026-08-31 23:04'
labels: []
dependencies: []
modified_files:
  - core/Services/DiscoveryCriteria.swift
  - core/Services/DiscoverySweeper.swift
  - app/Views/Settings/SearchSettingsTab.swift
  - tests/CoreTests/DiscoveryCriteriaTests.swift
  - tests/CoreTests/DiscoverySweeperTests.swift
  - docs/auto-search-spec.md
priority: high
type: enhancement
ordinal: 68000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The arrangement rule added to gate A (2026-08-31) rejects a posting whose board location names a specific place when neither title nor location says "remote". Measured on 572 real swept rows it removes ~47% of the sweep, which is the point — but it is the one rule in `DiscoveryCriteria` that rejects on absent data, and it has a known false-reject case.

Measured on 14 known-remote discovered jobs, 13 survive. The one that doesn't:

```
Palo Alto, California, United States   → REJECT   (genuinely remote; "remote" appears only in the description body)
```

Roughly **7% of remote roles**. Because the rejection happens before hydration, the body is never fetched, so nothing downstream can recover it — the loss is silent and permanent, which is exactly the failure mode the rest of gate A is written to avoid.

The asymmetry to exploit: `DiscoverySweeper.hydrateAndIngest` already fetches the body, and `DiscoveryCriteria.evaluateHydrated` already re-applies the salary floor there for the identical reason (the board row doesn't carry the data). Arrangement should get the same second look.

Proposed shape: gate A stops rejecting outright on arrangement and instead marks the posting *provisional*; hydration proceeds; `evaluateHydrated` then decides on the body, where "Remote" is nearly always stated explicitly. Cost is one HTTP GET per provisional posting — no LLM spend, which is what the gate actually protects. Needs a bound so a board of 3,000 city-named postings doesn't become 3,000 fetches: cap provisional hydrations per sweep separately from `DiscoveryCaps.perSweep`.

Requires a `DiscoveryCriteria.gateVersion` bump (currently 3) so postings already rejected under the strict rule are re-judged.

Until this lands, the user's escape hatch is Settings → Jobs → tick **Allow Onsite**, which disables the arrangement rule entirely and restores geography-only gating.

Related: [[TASK-693]] — the board row being better evidence than the description is the same theme, in the opposite direction.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A posting whose board location names a city but whose body says 'Remote' is ingested rather than rejected
- [x] #2 A posting that is genuinely on-site is still rejected before any LLM spend
- [x] #3 Provisional hydrations are capped per sweep, separately from the ingest cap, so a large city-named board cannot cause thousands of fetches
- [x] #4 DiscoveryCriteria.gateVersion is bumped so postings rejected under the strict rule are re-judged
- [x] #5 The measured false-reject rate on the 14-job remote sample drops to zero
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Gate A no longer rejects on an unstated work arrangement. `DiscoveryVerdict` gains a `.provisional` case: a posting whose board row names a city and says nothing about arrangement proceeds to hydration and is judged on its body by `evaluateHydrated(body:provisionalArrangement:)`, before any extraction or fit score. `gateVersion` 3 → 4, so everything already rejected under the strict rule is re-judged.

**The brief's premise was wrong and this is the substantive finding.** Reusing the existing `remoteMarker` on a body does not work: it requires "remote" to be followed by end-of-string or punctuation (right for a title or location token, where the alternative is "Remote Sensing Program Manager"), and description prose says it as an adjective — "all roles are remote unless otherwise specified", "this is a fully remote position", "Remote Work" as a heading. Measured over the 1,265 stored jobs that carry both an arrangement and a body, the strict marker fires on only 48% of the 1,033 remote ones and **misses the exact `Palo Alto, California, United States` posting this task is about** (job #1200, Acryl Data, `gh:5186170007`, whose body reads "All roles are remote unless otherwise specified"). So the fix needed a prose-shaped `bodySignalsRemote` alongside — reusing `remoteMarker`/`remoteNegation` as terms rather than restating them, with the token rule left untouched as the single definition of the location form. It reaches 69% recall while firing on **0 of the 53 on-site bodies**. Six on-site false positives came from denials the board-row negation can't see ("not eligible for remote work", "remote work options are not available"); a clause-bounded body negation removes all six and costs 1 point of recall.

`DiscoveryCaps.provisionalPerSweep` defaults to 25, drawn from whatever `perSweep` leaves unused — so a sweep makes no more requests than before, and an outright match is never displaced by a speculative one. Overflow is reported as `SweepResult.provisionalTruncatedByCap`, deliberately not folded into `truncatedByCap`, which holds a board open and would have pinned a market pass to the first city-named board it met.

Fast gate green (CoreTests/ServerTests/MCPTests), warnings at baseline 33, swiftlint/swiftformat clean, check-docs failure is the pre-existing retired-stack one. No LLM or API call was made; all measurement came from read-only sqlite3 over the live store.
<!-- SECTION:FINAL_SUMMARY:END -->
