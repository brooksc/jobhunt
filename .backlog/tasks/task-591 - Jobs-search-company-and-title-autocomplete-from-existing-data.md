---
id: TASK-591
title: 'Jobs search: company and title autocomplete from existing data'
status: To Do
assignee: []
created_date: '2026-07-02 21:52'
updated_date: '2026-07-21 22:59'
labels: []
dependencies: []
references:
  - 'app/Views/Jobs/JobsView.swift:54'
  - core/Models/SearchTokenID.swift
  - core/Models/SavedSearchCriteria.swift
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
- [ ] #1 Typing a partial company name in the search field shows matching company names from existing jobs as suggestions
- [ ] #2 Selecting a company suggestion filters the list to jobs at that company
- [ ] #3 Same for job title prefix completion
- [ ] #4 Suggestions update if a new job with a new company is added mid-session
<!-- AC:END -->
