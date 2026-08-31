---
id: TASK-693
title: >-
  Extraction overwrites the board's authoritative location with the job
  description's office list
status: To Do
assignee: []
created_date: '2026-08-31 17:59'
updated_date: '2026-08-31 18:00'
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
