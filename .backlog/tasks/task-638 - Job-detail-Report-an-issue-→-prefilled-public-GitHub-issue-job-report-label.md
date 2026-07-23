---
id: TASK-638
title: >-
  Job detail: "Report an issue" → prefilled public GitHub issue (job-report
  label)
status: Done
assignee: []
created_date: '2026-07-23 01:44'
labels:
  - job-detail
  - feedback
  - github
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
End users need a way to report a problem with a job's captured/parsed data that reaches the maintainer (not just a local log). The job detail now has a "Report an issue" button that builds a curated PUBLIC context report (source URL, parsed company/title/location/salary/remote/employment/seniority, extraction model+status, description length+hash, app+OS version, job #) — deliberately excluding résumé, personal info, notes, and fit — copies it to the clipboard, and opens a prefilled GitHub new-issue URL on the public brooksc/jobhunt repo with the `job-report` label, falling back to a blank issue when the prefilled URL exceeds the length budget. A .github/ISSUE_TEMPLATE/job-report.md provides structure for manual filing. Maintainers track reports via `gh issue list --label job-report`. GitHub-only by decision (account/privacy friction punted; report data is public JD info).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Job detail has a Report an issue action that opens a prefilled GitHub issue with title, body, and job-report label
- [ ] #2 The report includes only curated public fields (URL, parsed values, versions) and excludes resume/personal/notes/fit
- [ ] #3 The full report is copied to the clipboard, with a blank-issue fallback when the prefilled URL is too long
- [ ] #4 A stable marker + job-report label make reports programmatically trackable
- [ ] #5 Focused tests cover context inclusion, redaction, prefill URL, and oversized fallback
<!-- AC:END -->
