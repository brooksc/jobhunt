---
id: TASK-694
title: >-
  Re-check work arrangement after hydration, to recover the ~7% of remote roles
  gate A rejects
status: To Do
assignee: []
created_date: '2026-08-31 18:00'
labels: []
dependencies: []
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
- [ ] #1 A posting whose board location names a city but whose body says 'Remote' is ingested rather than rejected
- [ ] #2 A posting that is genuinely on-site is still rejected before any LLM spend
- [ ] #3 Provisional hydrations are capped per sweep, separately from the ingest cap, so a large city-named board cannot cause thousands of fetches
- [ ] #4 DiscoveryCriteria.gateVersion is bumped so postings rejected under the strict rule are re-judged
- [ ] #5 The measured false-reject rate on the 14-job remote sample drops to zero
<!-- AC:END -->
