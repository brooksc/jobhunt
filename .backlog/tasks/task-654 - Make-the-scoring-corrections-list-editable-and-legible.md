---
id: TASK-654
title: Make the scoring-corrections list editable and legible
status: To Do
assignee: []
created_date: '2026-08-01 19:49'
labels:
  - fit-scoring
  - ui
dependencies: []
references:
  - app/Views/Settings/ScoringFeedbackSettings.swift
  - core/Services/ScoringFeedback.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## What exists

Settings → Jobs → **Scoring Corrections** already lists every correction with its phrase, kind ("I do have this" / "I don't have this" / "This isn't a real requirement" / "Wrong for this job only"), the job it was flagged from, and any note. A trash icon deletes it and recomputes affected scores immediately.

## What's missing

- **No edit.** A phrase that turns out too broad ("electrical" matching "partner with electrical teams") can only be deleted and re-created, losing the note and the original job context.
- **No separation of positive from negative.** "I do have this" and "I don't have this" have opposite effects on every score but sit in one undifferentiated list. As the list grows past a handful this becomes hard to reason about.
- **No sense of blast radius.** A correction silently affects every job whose requirements contain the phrase. Nothing shows how many that currently is, so an over-broad rule is invisible until a score looks wrong.
- **No link back to the source job**, so the context that motivated the correction can't be revisited.
- **`createdAt` is stored but never displayed**, so there's no way to tell a stale correction from a fresh one — relevant after a résumé update, when "I don't have this" may no longer be true.

## Why it matters

The correction list is the durable record of what the app has learned. A flag silently changing scoring forever is a mystery six weeks later; the list is what makes it inspectable, and right now it's inspectable but not maintainable.

## Notes

Corrections live as JSON in the `scoring_feedback` setting (no schema migration). Editing is a matter of writing the array back — `SettingsStore.scoringFeedback` already round-trips. Match counts would come from running `[ScoringFeedback].verdict(forRequirement:jobNumber:)` across stored assessments, which is cheap at this app's scale.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 An existing correction's phrase, kind and note can be edited in place, preserving its id and source job
- [ ] #2 Positive and negative corrections are visually distinguishable at a glance
- [ ] #3 Each entry shows how many jobs it currently matches, so an over-broad phrase is visible before it does damage
- [ ] #4 Each entry shows when it was created and links back to the job it came from
- [ ] #5 Editing or deleting recomputes affected scores immediately, as saving already does
<!-- AC:END -->
