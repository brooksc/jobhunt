---
id: TASK-591
title: 'Jobs search: company and title autocomplete from existing data'
status: Done
assignee: []
created_date: '2026-07-02 21:52'
updated_date: '2026-08-09 23:05'
labels: []
dependencies: []
references:
  - 'app/Views/Jobs/JobsView.swift:54'
  - core/Models/SearchTokenID.swift
  - core/Models/SavedSearchCriteria.swift
modified_files:
  - core/Services/JobTextSuggestions.swift
  - app/Views/Jobs/JobSearchToken.swift
  - tests/CoreTests/JobTextSuggestionsTests.swift
priority: low
ordinal: 40000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Opportunity:** The search token system offers structured filters (status, salary, fit score, etc.) but freeform text doesn't suggest values from the user's own data. Typing "Goog" should suggest "Google" from jobs they've already captured.

**How to implement:**
1. In `JobsView` (or its search model), maintain a lazy-loaded `Set<String>` of unique company names and job titles from the current `allJobs` query — cheap given the ~few-hundred-job scale.
2. In the search field's `onSubmit`/`onChange`, if the current text doesn't match any token prefix, emit suggestions from the company/title sets filtered by prefix (case-insensitive).
3. Display suggestions in the existing token-suggestion dropdown (same `completions` mechanism already used for status/salary token suggestions in `JobSearchToken.swift:49–103`).
4. Selecting a suggestion inserts a freetext filter that matches `job.company == suggestion` or `job.title.contains(suggestion)`.

**Scope:** ~60–80 lines, no schema or model changes. The suggestion data falls out of the existing `allJobs` fetch.

**Parked — nice to have.**
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Typing a partial company name in the search field shows matching company names from existing jobs as suggestions
- [x] #2 Selecting a company suggestion filters the list to jobs at that company
- [x] #3 Same for job title prefix completion
- [x] #4 Suggestions update if a new job with a new company is added mid-session
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
`JobTextSuggestions.suggest(prefix:companies:titles:limit:)` in Core, rendered by the existing `JobSearchSuggestions` dropdown below the structured token suggestions (#1, #3) — those are exact and few, and burying them under a list of company names would make the token system harder to discover than it already is.

#2 Selecting a suggestion inserts plain text, which the existing `SavedSearchCriteria.textNumberMatch` already applies to `displayCompany` and `displayTitle`. Deliberately no new filter path: a dedicated company-equality filter could disagree with what typing the same string does.

#4 The source is a `@Query` over jobs rather than a cached `Set`, so a company captured mid-session is suggestable with no invalidation of our own. At a few hundred jobs the per-keystroke map+filter is imperceptible (see the scale convention in CLAUDE.md).

Two judgement calls beyond the task text: matching a prefix of any *word* as well as of the whole value (whole-string matching requires knowing how the name starts, which is what the user is trying not to remember), and a 2-character minimum (one character matches most of the corpus and buries the token suggestions sharing the dropdown). Case-insensitive dedup keeps the first spelling seen so the inserted text doesn't look like a typo of the user's own data.

7 tests. Gate: fast gate TEST SUCCEEDED, BUILD SUCCEEDED, swiftlint 0 violations in 322 files, swiftformat 0.61.1 clean.

not verified: (visual) — that the dropdown reads well with both suggestion families in it, and the click-to-complete interaction. Covered at the model level only.
<!-- SECTION:FINAL_SUMMARY:END -->
