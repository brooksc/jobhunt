---
id: TASK-693
title: >-
  Extraction overwrites the board's authoritative location with the job
  description's office list
status: To Do
assignee: []
created_date: '2026-08-31 17:59'
updated_date: '2026-08-31 20:05'
labels: []
dependencies: []
priority: high
type: bug
ordinal: 67000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found while investigating job #1290 (2026-08-31). Discovery's board row carried the ATS's own location field — `"New York, New York, United States"` — which is a single, structured, authoritative statement of where the role is. Extraction then replaced it with a 10-city office list scraped from the job description prose (the "we have offices in …" paragraph), which is not the role's location at all.

We already hold the better data at ingest time and throw it away. Consequences beyond the display:

- **Gate A vs. the stored record disagree.** Gate A judges the board location; the badge and the requirements verdict judge the extracted one. A job can pass the gate on a clean location and then read as multi-city or on-site afterwards.
- **The arrangement rule and `LocationCriteria` both degrade** when the stored location is a marketing paragraph rather than a place.

Fix direction: carry `DiscoveredPosting.locationRaw` through `ingestCapture` and prefer it over the LLM's `location` for discovery-sourced jobs, or feed it to the extraction prompt as a constraint. Browser-extension captures have no equivalent field, so this must not regress them — the board location should win only when it exists.

Related: [[TASK-694]] — the arrangement half of the same "board row is better evidence" theme, in the opposite direction (there the body beats the board row).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A discovery-ingested job keeps the ATS board's location field rather than a city list scraped from the description body
- [ ] #2 Job #1290 shows 'New York, New York, United States' after re-extraction
- [ ] #3 Extension and MCP captures, which have no board location, are unaffected
- [ ] #4 Gate A and the stored location agree for discovery-sourced jobs
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: primary
created: 2026-08-31 20:05
---
**Concrete case, 2026-08-31 — job #1524, and it shows the cost is worse than a blank field.**

Sony Interactive Entertainment, "Senior Product Manager - Monetization", `gh:6011556004`. Fit score **90**. Salary **$168,900–$253,300**. Exactly the kind of role this app exists to surface.

- Greenhouse board row carried `locationRaw: "United States, San Mateo, CA"` — confirmed in the ledger AND in the preserved snapshot at `~/Documents/jobhunt-backups/board-locations-20260831.json`.
- The stored job has **no `location` and no `remoteType` at all**. The user confirms the location is clearly stated on the posting's web page; it is in the Greenhouse header, not the description body, so the LLM never saw it — extraction only gets the captured body text.
- Consequence: `meetsCriteria: false` and `requirements_verdict: not_stated`. `LocationCriteria` treats an absent remote type as on-site, so with On-site disallowed the job is badged as failing the user's criteria.

So the missing board location does not merely leave a field blank — it **actively mis-badges a 90-fit, well-paid job as not meeting criteria**, and now that the job-list warning line ships, it will be visibly labelled that way. This is the strongest argument yet for bucket A (the 183 rows where extraction produced no location and the board had one): those are not cosmetic gaps, they are wrong verdicts.

Note #1524 came in via discovery today, so this is ongoing, not historical.
---
<!-- COMMENTS:END -->
