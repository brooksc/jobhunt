---
id: TASK-705
title: >-
  Jobs naming a city with no arrangement word are bucketed "not stated", so they
  hide from the Doesn't-meet filter
status: To Do
assignee: []
created_date: '2026-08-31 20:27'
updated_date: '2026-09-04 19:56'
labels: []
dependencies: []
priority: medium
type: bug
ordinal: 79000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Reported by the user 2026-08-31: "I'm seeing a bunch of jobs like 1424 which are clearly NOT remote. Yet when I filter on Doesn't meet criteria these don't appear."

**Confirmed.** Job #1424 — "Staff Product Manager", location `"Lehi, Utah"`, `remoteType` NULL, `meetsCriteria` false, status `new`.

`JobFilterRules.criteriaBucket` (`core/Services/JobFilterRules.swift:54-61`):

```swift
if meetsCriteria { return .meets }
return switch remoteType {
case .unknown, .none: .notStated
case .remote, .hybrid, .onsite: .doesNotMeet
}
```

So a failing job with no arrangement lands in `.notStated`, invisible to the "Doesn't meet" chip. **49 such jobs are in New right now** (plus 148 archived, 62 duplicate, 9 expired, 3 applied, 1 rejected).

## The modeling flaw

`remoteType == nil` conflates two different things:
1. The posting says nothing about location *or* arrangement — genuinely unknown.
2. The posting names a specific city and simply never uses the word "remote" — effectively on-site.

Lehi, Utah is case 2. The location *is* stated; only the arrangement word is absent. Treating it as "not stated" is what hides it.

The existing comment defends the current behaviour ("a posting that never states its arrangement may still be remote-friendly, so nothing is archived automatically") and that reasoning is sound for case 1. It is wrong for case 2.

**We already solved this exact problem once today, one layer up.** `DiscoveryCriteria.passesArrangement` distinguishes the two with `namesSpecificPlace(_:)` — strike out country-level terms and the user's own allow-list, and if a place name survives, the posting is making an on-site statement. That rule was measured against 572 real swept rows. Reuse it rather than inventing a second heuristic; two rules that disagree about the same question is how the gate and the badge came to disagree in the first place.

## Three things to do

1. **Fix the bucketing** so a failing job whose location names a specific place is `.doesNotMeet`, not `.notStated`. Keep genuinely-unknown postings (no location, or country-only) in `.notStated` — the user explicitly still wants to review those.
2. **Let the user clear the backlog of 49.** Once they bucket correctly they are reachable by the existing filter + bulk archive, which may be sufficient — confirm the Jobs list supports multi-select archive from a filtered view. If it does, no new bulk action is needed; say so rather than building one.
3. **Prevent recurrence.** Gate A's arrangement rule already rejects these at sweep time for discovery, but #1424 predates it. Verify a #1424-shaped posting would now be rejected before ingest, and check whether the post-extraction path needs the same rule for captures that arrive by other routes.

Do **not** auto-archive anything as a side effect of the bucketing change — the user asked to find and archive them, which is their action to take, and silently moving 49 jobs out of New would be worse than the bug.

Related: [[TASK-694]] (arrangement re-check after hydration) and [[TASK-693]] (board location) both touch the same "what do we actually know about where this job is" question.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A failing job whose location names a specific place buckets as doesNotMeet, not notStated
- [ ] #2 A failing job with no location, or a country-only location, still buckets as notStated
- [ ] #3 The rule reuses DiscoveryCriteria's namesSpecificPlace logic rather than a second heuristic
- [ ] #4 Job #1424 appears under the Doesn't-meet filter
- [ ] #5 Nothing is auto-archived by this change
- [ ] #6 It is confirmed (and stated) whether the existing filter plus bulk archive is enough to clear the 49, or a new affordance is needed
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
created: 2026-09-04 19:56
---
Re-measured against the live store 2026-09-04, after TASK-708's `--repair-remote-types` run restored 223 erased work arrangements. **The scope shrank and the headline example is gone.**

**Job #1424 — the reported case — is fixed.** It now reads `remoteType = hybrid` with location `Lehi, Utah`, so `criteriaBucket` returns `.doesNotMeet` and it appears under the filter. It was only ever bucketed `.notStated` because the TASK-708 clamp had erased its arrangement; the bucketing rule never saw it.

Current counts:

| | jobs |
|---|---|
| `meetsCriteria=0` and no arrangement, all statuses | 333 |
| …of those, in New | 42 |
| …of those, **with a non-empty location** (this bug) | **22** |
| …of those, empty location (correctly `.notStated`) | 20 |

So the modeling flaw is real and still hides **22 jobs in New** — several Airbnb roles at "San Francisco, CA" among them — but it is no longer the 49-job problem the description describes, and it is not release-blocking.

The 20 with a genuinely empty location behave correctly and must keep doing so: the user explicitly still wants to review those.

Acceptance criterion #4 ("Job #1424 appears under the Doesn't-meet filter") is already satisfied by other means — do not use it as the test for this fix. Pick a current case from the 22 instead. Priority lowered High → Medium on that basis.
---
<!-- COMMENTS:END -->
