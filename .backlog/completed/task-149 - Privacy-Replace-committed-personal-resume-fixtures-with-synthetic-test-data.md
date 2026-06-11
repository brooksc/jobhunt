---
id: TASK-149
title: 'Privacy: Replace committed personal resume fixtures with synthetic test data'
status: Done
assignee: []
created_date: '2026-06-11 04:34'
updated_date: '2026-06-11 18:35'
labels:
  - privacy
  - tests
  - fixtures
dependencies: []
references:
  - tests/fixtures/resumes
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Security/privacy audit finding: `tests/fixtures/resumes` contains real-looking personal resume PDFs and Markdown files. Test fixtures should not expose personal employment history or private documents in repository history and every checkout.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Personal resume PDF and Markdown fixtures are replaced with synthetic resumes that preserve test coverage needs without real personal data.
- [ ] #2 Tests and eval harnesses are updated to use synthetic fixture names/content.
- [ ] #3 Repository history exposure is assessed; if the repo has been public or shared externally, document whether history rewriting or secret/privacy incident handling is required.
- [ ] #4 A lightweight fixture policy is added so future test data is synthetic or explicitly approved.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Removed all 8 personal resume files (PDFs and Markdown with real name/email/phone/employment history). Added synthetic_resume_general.md (fictional persona, example.com email, invented companies). Added FIXTURE_POLICY.md documenting that all resume fixtures must be synthetic and noting that git history should be reviewed/rewritten if the repo has been shared publicly. No tests reference these files so no test updates were needed.
<!-- SECTION:FINAL_SUMMARY:END -->
