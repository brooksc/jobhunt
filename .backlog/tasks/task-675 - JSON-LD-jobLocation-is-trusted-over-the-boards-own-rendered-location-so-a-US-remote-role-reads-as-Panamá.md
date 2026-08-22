---
id: TASK-675
title: >-
  JSON-LD jobLocation is trusted over the board's own rendered location, so a
  US-remote role reads as Panamá
status: Done
assignee: []
created_date: '2026-08-21 00:05'
updated_date: '2026-08-22 19:22'
labels:
  - extraction
  - normalization
  - bug
  - scoring
dependencies: []
priority: high
ordinal: 46000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Reported as "Netflix jobs aren't parsing properly". Separate from the crash fixed alongside it (repeated query parameter trapping Dictionary(uniqueKeysWithValues:)) — this one produces a wrong answer rather than a crash, and it silently removes jobs from consideration.

## What happens

Netflix job #961, 'Technical Program Manager - Hawkins Design System', $290,000–$460,000, is stored as:

    location   = Panamá, Provincia de Panamá,PA
    remoteType = unknown
    meetsCriteria = 0        <-- filtered OUT of the user's criteria

The real posting is 'USA - Remote'.

## Why

The page publishes TWO location sources that disagree:

1. JSON-LD (ld+json): jobLocation = {addressLocality: 'Panamá', addressRegion: 'Provincia de Panamá,PA', addressCountry: {name: 'PA'}} — an upstream geocoding artifact; 'PA' is being read as Panama. VERIFIED live with curl against explore.jobs.netflix.net, independent of the app, so the bad value is genuinely Netflix's.
2. The board's own embedded payload, which is what the UI renders and what a human sees: "location": "USA - Remote", "locations": ["USA - Remote"].

Cleaning.structuredLocationLines (added for Reddit #7944159, where JSON-LD was the ONLY location signal) injects source 1 into the cleaned description as a 'Location:' line — confirmed present at line 55 of #961's cleanedDescription. The model then faithfully reports Panamá, and nothing downstream can tell it was wrong.

## Why it matters more than one bad field

remoteType lands on 'unknown', and LocationCriteria treats unknown as on-site, which then requires a preferred-location match. 'Panamá' doesn't match, so meetsCriteria goes to 0 and the job drops out of the filtered view. This is exactly the failure mode behind 'I may have archived jobs I'm actually a good fit for' — the job scored 65 and pays $290k+.

Only 2 jobs currently carry this specific string, but the class is general: any board whose JSON-LD jobLocation is wrong or stale overrides better evidence on the same page.

## Directions (not yet decided)

- Prefer the page's rendered/embedded location when it disagrees with JSON-LD, or feed BOTH to the model as labelled, competing evidence rather than one authoritative 'Location:' line.
- Sanity-check jobLocation before injecting it: a two-letter addressCountry that is also a US state abbreviation ('PA'), or a country that contradicts every other location signal on the page, is more likely a geocoding artifact than a fact.
- Never let a structured-data location alone drive remoteType to a value that removes a job from criteria — an inference that can only lose jobs should be the weakest signal, not the strongest.
- Related: the stored title is the generic 'Technical Program Manager' while the JSON-LD carries the specific 'Technical Program Manager - Hawkins Design System'. The better title is present and unused.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A posting whose JSON-LD location contradicts the board's rendered location does not silently adopt the JSON-LD value
- [x] #2 Netflix #961 and #960 re-extract to a US/remote location, and #961 meets criteria again
- [x] #3 A wrong or missing structured location cannot by itself drive remoteType to a value that removes a job from criteria
- [x] #4 Reddit #7944159's case still works: JSON-LD remains the location source when it is the only one
- [x] #5 Tests cover disagreeing sources, an ambiguous two-letter country code, and a JSON-LD-only posting
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Fixed and VERIFIED on the real jobs. #961 went Panamá / unknown / meetsCriteria 0 -> 'USA - Remote' / remote / meetsCriteria 1; #960 went a Panamá-contaminated list -> 'United States'.

It took three attempts, and only re-running the actual jobs caught the first two:
1. Made the structured location a fallback — suppressed only when the ASSEMBLED body named a location. #961's substantial JSON-LD description is promoted OVER the page text, so the body named nothing and the bogus line still went in.
2. Consulted the visible text too, and carried the page's own phrase across. Still wrong: the gate deciding 'does the body already say where this is?' matched 'Design Platform, Engineering' with a bare Word,Capitalised pattern, so BOTH the metadata line and the page's phrase were suppressed and the job ended with no location at all — which LocationCriteria reads as on-site.
3. Constrained the region half to a 2-letter code, a spelled-out US state (from the shared stateNameToAbbrev table) or a named country. JobsView had already learned this exact lesson; the first version was a looser copy of it.

Note for anyone re-verifying: cleanedDescription is computed at CAPTURE time, so re-running extraction alone replays the stale text. JobhuntMigrator --reclean (app quit, store backed up first) is required before the fix is visible on existing jobs.

not verified: nothing outstanding.
<!-- SECTION:NOTES:END -->
