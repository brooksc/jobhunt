---
id: TASK-675
title: >-
  JSON-LD jobLocation is trusted over the board's own rendered location, so a
  US-remote role reads as Panamá
status: To Do
assignee: []
created_date: '2026-08-21 00:05'
updated_date: '2026-08-21 00:10'
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
- [ ] #1 A posting whose JSON-LD location contradicts the board's rendered location does not silently adopt the JSON-LD value
- [ ] #2 Netflix #961 and #960 re-extract to a US/remote location, and #961 meets criteria again
- [ ] #3 A wrong or missing structured location cannot by itself drive remoteType to a value that removes a job from criteria
- [ ] #4 Reddit #7944159's case still works: JSON-LD remains the location source when it is the only one
- [ ] #5 Tests cover disagreeing sources, an ambiguous two-letter country code, and a JSON-LD-only posting
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## The standalone canonical page does not help (checked 2026-08-20)

https://explore.jobs.netflix.net/careers/job/790316311096?microsite=netflix.com carries the SAME wrong JSON-LD (Panamá / addressCountry 'PA'), and the same correct embedded payload ('location': 'USA - Remote', 5 occurrences). So capturing the canonical job URL instead of the search URL fixes nothing — both pages carry both sources, and they disagree on both.

## The decisive finding: the capture was already right

Job #961's stored visibleText contains 'USA - Remote' FOUR times and never mentions Panamá. The only occurrence of Panamá anywhere in the capture is the line structuredLocationLines injected.

So this is not a capture problem and not a 'find a better source' problem. One injected line, labelled as plain 'Location:', outweighed four occurrences of the truth in the page's own text.

## Recommended fix (narrowest thing that works)

Make the JSON-LD location a FALLBACK rather than an override — which is exactly the intent it was written with. Reddit #7944159 needed it because the description carried no location at all; inject it only when that is still true:

- if the visible text already yields a location or a remote signal, don't inject the structured line at all
- when it is injected, label it as page metadata rather than as a bare authoritative 'Location:'
- optionally reject an addressCountry that is a bare two-letter code colliding with a US state abbreviation ('PA'), which is the specific artifact here

That keeps the Reddit case working, needs no vendor-specific scraping of Netflix's embedded JSON, and removes the only mechanism by which a wrong structured location can beat a correct page.
<!-- SECTION:NOTES:END -->
