---
id: TASK-672
title: 'Post-v1.4.0 code review: seven defects in the backlog-run features'
status: Done
assignee: []
created_date: '2026-08-20 19:10'
labels:
  - bug
  - review
  - scoring
dependencies: []
priority: high
ordinal: 43000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Review of the 99 commits between v1.4.0 and the end of the 2026-08 backlog run. Everything compiled, the fast gate was green, and the features were present — but seven defects were live in the shipped code, three of them silently changing what the user sees.

1. RemoteGeography treated two-letter state abbreviations as whole-word US signals, so "Remote in Europe" (Indiana), "Remote — LATAM or EMEA" (Oregon) and "Rio de Janeiro" (Delaware) all classified as eligible and defeated the TASK-651 geography filter. Confirmed by running the classifier before fixing.
2. Same file: normalizeForMatch turns an accented letter into a space, splitting the word ("México" -> "m xico"), so every accented entry in the token list (Bogotá, Medellín, Kraków, Zürich, São Paulo) was unreachable.
3. PromptTemplateRenderer validated padded tokens ({{ job.title }}) but rendered them literally, copying the raw token to the clipboard without reporting it missing; the per-variable replace also substituted into already-substituted text.
4. The recap reminder loop re-derived its own hour test, leaving the tested RecapReminderSchedule unused and firing once per launch in the evening.
5. Spotlight indexing had no opt-out and Clear Spotlight Index was undone by the next launch; deletions outside the Jobs/Detail views left permanent stale hits.
6. SeniorityNormalizer rule order let a modifier decide the band: "Associate Director" -> entry, "Senior Staff Engineer" -> senior, both fed to experience_level scoring.
7. Extension: the auto-launch cooldown lived in an MV3 service-worker variable that Chrome evicts on roughly the cooldown's own timescale, and the scheme-handoff tab was left open.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 RemoteGeography no longer reads connector words as US locations, with the three observed strings pinned by tests
- [ ] #2 Accented place names classify the same as their ASCII spellings
- [ ] #3 Padded prompt tokens render, and substituted values are not rescanned for tokens
- [ ] #4 The recap reminder fires from RecapReminderSchedule, once per scheduled instant
- [ ] #5 Spotlight indexing can be turned off and stays off; the launch pass replaces rather than adds
- [ ] #6 Compound seniority titles keep their own band
- [ ] #7 The extension's launch cooldown survives a service-worker restart
<!-- AC:END -->
