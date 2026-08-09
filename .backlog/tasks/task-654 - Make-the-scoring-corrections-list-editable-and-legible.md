---
id: TASK-654
title: Make the scoring-corrections list editable and legible
status: Done
assignee: []
created_date: '2026-08-01 19:49'
updated_date: '2026-08-09 22:52'
labels:
  - fit-scoring
  - ui
dependencies: []
references:
  - app/Views/Settings/ScoringFeedbackSettings.swift
  - core/Services/ScoringFeedback.swift
modified_files:
  - core/Services/ScoringFeedback.swift
  - core/Settings/SettingsStore.swift
  - app/Views/Settings/ScoringFeedbackSettings.swift
  - app/Views/Settings/SettingsTab.swift
  - tests/CoreTests/ScoringFeedbackTests.swift
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
- [x] #1 An existing correction's phrase, kind and note can be edited in place, preserving its id and source job
- [x] #2 Positive and negative corrections are visually distinguishable at a glance
- [x] #3 Each entry shows how many jobs it currently matches, so an over-broad phrase is visible before it does damage
- [x] #4 Each entry shows when it was created and links back to the job it came from
- [x] #5 Editing or deleting recomputes affected scores immediately, as saving already does
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
#1 `ScoringFeedback.updating(phrase:kind:note:)` returns a copy with the editable fields replaced and `id`, `jobNumber` and `createdAt` carried over; a `ScoringFeedbackEditor` sheet edits phrase/kind/note with the existing `rejectionReason` shown live and Save disabled while it's non-nil. `SettingsStore.updateScoringFeedback` replaces in place — deliberately preserving array position, since `verdict(forRequirement:jobNumber:)` returns on the first `neverCredit` it meets and re-appending would silently change which rule wins when two match.

#2 New `Kind.Polarity` (credits / penalises / neutral) drives a coloured glyph per row, so the two kinds with opposite effects are distinguishable without reading the label.

#3 Was already shipped — `matchCountLabel` shows the live match count and calls out a correction matching nothing. Left as-is.

#4 Each row shows the creation date and, where there is a source job, a `jobhunt://jobs/N` link. Settings is its own window, so the existing deep-link handler in `PlatformIntegration` is the right route rather than reaching for the main window's router.

#5 `saveFeedbackEdit` calls `recomputeAllFitScores()` and refreshes match counts, mirroring `removeFeedback`.

5 tests added (`ScoringFeedbackEditingTests`). Gate: fast gate TEST SUCCEEDED, app target BUILD SUCCEEDED, swiftlint 0 violations, swiftformat 0.61.1 clean.

not verified: (visual) — row layout with the new glyph/date/link at real Settings widths, and the editor sheet's appearance. No screen access was taken; behaviour is covered at the model level.
<!-- SECTION:FINAL_SUMMARY:END -->
