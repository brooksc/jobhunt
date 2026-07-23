---
id: TASK-628
title: Historical application report with unemployment-evidence CSV export
status: Done
assignee: []
created_date: '2026-07-22 21:55'
updated_date: '2026-07-23 04:23'
labels:
  - reporting
  - dashboard
  - applications
  - csv-export
  - compliance-support
dependencies: []
references:
  - >-
    https://esd.wa.gov/get-financial-help/unemployment-benefits/weekly-unemployment-claims/job-search-requirements
  - 'https://esd.wa.gov/sites/default/files/2024-11/ESD-job-search-log.pdf'
  - >-
    https://esd.wa.gov/get-financial-help/unemployment-benefits/weekly-unemployment-claims/how-file-your-weekly-claims
  - TASK-008
  - TASK-280
  - TASK-504
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Add a report that lists every retained job that has ever been marked Applied, regardless of its current workflow status. The report is intended to help users preserve evidence of employer contacts for unemployment-benefit job-search logs, initially aligned with Washington Employment Security Department guidance. Inclusion must come from authoritative application history, such as the first Applied transition and `appliedAt`, rather than filtering for current status == Applied. Jobs later moved to Interview, Offer, Rejected, Passed, Closed, Expired, or Archived must remain in the report. Present applications by date and Washington claim week (Sunday through Saturday), with date-range filtering and CSV export. Include the information JobHunt can substantiate and clearly flag missing fields instead of inventing them. Do not claim that the report proves eligibility or that a week satisfies requirements, because JobHunt may not contain other approved job-search activities and ESD makes the determination.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A discoverable Application History report lists every retained job that has an authoritative record of entering Applied status, independent of the job's current status.
- [ ] #2 A job remains in the report after moving from Applied to Interview, Offer, Rejected, Passed, Closed, Expired, Archived, or another later workflow state.
- [ ] #3 The application date uses the first authoritative Applied timestamp; the report does not substitute capture date, current-status update time, or export time.
- [ ] #4 Legacy records with an Applied history but no reliable application timestamp remain visible with a Missing application date warning and a way to enter or correct the date without rewriting unrelated history.
- [ ] #5 The report supports an all-time view and a custom inclusive date range, with deterministic sorting by application date and a stable secondary key.
- [ ] #6 Applications can be grouped by Washington claim week, defined as Sunday through Saturday, and each group shows only the number of application contacts recorded rather than asserting whether unemployment requirements were met.
- [ ] #7 Each row shows application date, company or employer, job title or reference number, source or application URL, contact method when recorded, contact type, application result or current outcome, current JobHunt status, and relevant application notes.
- [ ] #8 Users can record or correct optional evidence fields needed by the ESD employer-contact log, including contact method, employer website or email, phone, address, city, state, job reference number, and result, without changing extracted job facts.
- [ ] #9 The report identifies which ESD-oriented evidence fields are missing and never infers a contact method, address, result, or successful submission from a URL alone.
- [ ] #10 One job's first Applied transition produces one application-contact row; repeated idempotent Applied operations do not create duplicate rows or inflate weekly counts.
- [ ] #11 If JobHunt later supports an explicit second application to a genuinely distinct posting or requisition, it is represented by a distinct authoritative application record rather than inferred from repeated status changes.
- [ ] #12 CSV export includes the selected date range and contains application_date, claim_week_ending, activity_type, contact_type, contact_method, company, job_title, job_reference_number, employer_address, city, state, website_or_email, phone, source_url, application_result, current_status, notes, job_id, and job_number columns.
- [ ] #13 CSV values are UTF-8, correctly escaped, and protected using the project's existing spreadsheet-formula-injection policy.
- [ ] #14 CSV export uses the macOS save panel and reports cancellation or write failures accurately without creating an empty success file.
- [ ] #15 The report and export exclude resumes, full job descriptions, fit-analysis text, LLM data, and unrelated notes by default.
- [ ] #16 The UI links each report row back to the corresponding retained job and provides clear feedback when the source job no longer has a usable URL.
- [ ] #17 The report includes a concise notice that it is a recordkeeping aid, may not include all approved job-search activities, and does not determine benefit eligibility; it links to current Washington ESD guidance.
- [ ] #18 No claimant ID, Social Security number, or unemployment account credentials are requested or stored for this feature.
- [ ] #19 Focused tests cover historical inclusion after every later status, first-Applied timestamp selection, legacy missing dates, idempotent reapplication, Sunday/Saturday week boundaries, timezone behavior, filters, deterministic ordering, missing evidence, CSV columns and escaping, formula-injection protection, and export failures.
<!-- AC:END -->
