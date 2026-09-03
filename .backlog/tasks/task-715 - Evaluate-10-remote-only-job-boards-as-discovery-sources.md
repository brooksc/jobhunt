---
id: TASK-715
title: Evaluate 10 remote-only job boards as discovery sources
status: To Do
assignee: []
created_date: '2026-09-01 01:13'
labels: []
dependencies: []
priority: medium
type: spike
ordinal: 99000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From a newsletter the user received (Avarah Careers, 2026-06-14), listing remote job boards the author had visited as of 2026-06-01 but explicitly **not** vetted. All are fee-free to browse, though several require registration. URLs decoded from the tracking links rather than followed, so no click was registered:

| board | URL | claim |
|---|---|---|
| Flexa | https://flexa.careers/jobs | broad, across fields |
| Himalayas | https://himalayas.app/ | remote only, across industries |
| Jobspresso | https://jobspresso.co/ | remote tech |
| NoDesk | https://nodesk.co/ | tech and non-tech remote |
| Remote.co | http://remote.co/ | remote-friendly companies worldwide |
| Skip The Drive | https://www.skipthedrive.com/ | remote, no commute |
| Toptal | https://www.toptal.com/ | freelance-focused |
| TrueUp | https://trueup.io/ | remote tech roles |
| We Work Remotely | https://weworkremotely.com/ | large remote marketplace |
| WellFound | https://wellfound.com/ | large tech and non-tech |

## The important caveat: these are aggregators, not ATSs

The discovery sweep is built on `JobSource` adapters for **Greenhouse, Lever, Ashby and Workday** — vendors with public, unauthenticated JSON endpoints returning a whole board in one request. That is what makes gate A cheap: a 15,000-posting sweep costs CPU and one HTTP call per board.

These ten are aggregators. Most have no public API, many require registration, and several prohibit automated access in their terms. **Do not assume a `JobSource` adapter is the right shape**, and check each site's terms before writing one — this app is distributed on the Mac App Store, and a scraper that violates a site's terms is a liability the user does not need.

Note the codebase already treats aggregators as a distinct category: `JobSearchLinks.excludedAggregatorDomains` deliberately pushes LinkedIn, Indeed, Glassdoor and ZipRecruiter *out* of the "find on company site" search, on the reasoning that the company's own posting is what matters. Several of these boards are the same kind of thing.

## Two realistic paths, in order of effort

1. **Review sites (cheap, works today).** The app already has a prospecting/review list with a per-site interval — `mcp__jobhunt__add_site`, surfaced in the UI. Adding these as periodic review sites costs nothing to build and lets the user judge yield before anyone writes code. **Start here.** If a board never produces a capture worth keeping, that is the answer and no adapter is needed.
2. **A `JobSource` adapter, only where justified.** Warranted only for a board that (a) proves useful in step 1, (b) exposes a usable feed — several of these publish RSS, which would be a far simpler adapter than an HTML scraper — and (c) permits it. Evaluate individually; do not build ten.

## Fit against the user's actual criteria

Worth filtering before spending effort. The user searches for Program Manager / TPM / Product Manager at a $180k floor, remote, US. On that basis **Toptal is almost certainly irrelevant** — it is a freelance marketplace, not permanent roles. WellFound skews early-stage startup, where the salary floor will exclude most listings. TrueUp, We Work Remotely and Himalayas look the most plausible for senior US remote product roles.

Also check for overlap with what discovery already covers: many of these aggregate the same Greenhouse and Lever boards the sweep reads directly, in which case they add duplicates rather than reach. Measuring that overlap is part of step 1.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Each board is added as a review site and given at least one manual review pass
- [ ] #2 Yield is recorded per board: how many postings matched the user's criteria and were worth keeping
- [ ] #3 Overlap with sources discovery already covers directly (Greenhouse/Lever/Ashby/Workday) is measured
- [ ] #4 Each board's terms are checked before any automated access is written
- [ ] #5 A per-board decision is recorded: adapter, review-site only, or drop
<!-- AC:END -->
