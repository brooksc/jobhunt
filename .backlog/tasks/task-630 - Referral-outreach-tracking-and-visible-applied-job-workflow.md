---
id: TASK-630
title: Referral outreach tracking and visible applied-job workflow
status: Done
assignee: []
created_date: '2026-07-22 23:02'
updated_date: '2026-07-23 04:44'
labels:
  - referral
  - outreach
  - applications
  - job-list
  - workflow
dependencies: []
references:
  - TASK-626
  - TASK-615
  - TASK-623
  - app/Views/Jobs/JobsView.swift
  - app/Views/Detail/JobDetailView.swift
  - app/Views/Detail/JobPromptMenu.swift
  - core/Models/JobEvent.swift
  - core/Models/JobAction.swift
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Make referral outreach a visible, structured workflow for jobs the user has applied to. Referral progress is orthogonal to JobStatus: a job remains Applied, Interview, Offer, or another workflow status while its referral effort can be Needs outreach, Requested, Referred/forwarded, Declined, or Not pursuing. Track individual outreach attempts with the recipient identity or label, channel, timestamp, and optional note so the app can prevent accidental duplicate messages rather than relying on an easily missed free-form job note. Surface a compact referral indicator directly in each relevant job-list row and provide filtering for jobs that still need outreach. Integrate with the existing Request Referral prompt from TASK-626, but do not mark an outreach request as sent merely because a prompt was copied or an AI site was opened; require an explicit user confirmation.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Referral progress is stored independently from JobStatus and does not add Referral requested as a mutually exclusive job status.
- [ ] #2 Applied, Interview, and Offer jobs without a recorded referral decision are classified as Needs outreach; jobs outside the active application funnel do not receive a misleading action requirement.
- [ ] #3 The supported referral summary states are Needs outreach, Requested, Referred or resume forwarded, Declined, and Not pursuing, with clear user-facing language.
- [ ] #4 Recording a request captures at least a recipient name or identifying label and the request timestamp, with optional LinkedIn URL or other contact identifier, channel, and note.
- [ ] #5 A job can retain multiple referral outreach attempts so contacting a second person does not overwrite the first person's history.
- [ ] #6 Before saving an outreach attempt, JobHunt warns when the same normalized recipient name, LinkedIn URL, email, or other stable identifier has already been recorded for that job and shows the prior request date.
- [ ] #7 The duplicate warning requires deliberate confirmation to record another attempt but does not block legitimate follow-ups or a corrected record.
- [ ] #8 Each applicable job-list row displays a compact referral indicator that distinguishes Needs outreach, Requested, and Referred at a glance without requiring the detail panel or timeline to be opened.
- [ ] #9 The row indicator has a tooltip and VoiceOver label containing the summary state, most recent recipient when available, and request date.
- [ ] #10 Jobs can be filtered by referral summary state, including a one-action view of applied jobs that still Need outreach.
- [ ] #11 The job detail panel provides a prominent referral section showing the current summary, outreach-attempt history, recipient, channel, dates, notes, and actions to add, edit, or remove a mistaken attempt.
- [ ] #12 Changing referral progress creates an auditable timeline event with structured state and timestamp data rather than requiring UI code to parse display-note text.
- [ ] #13 The Request Referral prompt workflow from TASK-626 offers a Record as sent action after copy or external-open, but copying or opening alone never changes referral state.
- [ ] #14 Record as sent reuses any recipient context already entered for the prompt where practical, asks for a recipient identifying label if one is unavailable, and shows the duplicate-recipient warning before saving.
- [ ] #15 When a request is recorded, the user can optionally schedule a follow-up using the existing JobAction workflow without creating duplicate pending follow-ups.
- [ ] #16 Advancing or changing the job's main workflow status preserves referral history and its visible summary; archiving or closing the job removes it from Needs outreach while retaining recorded attempts.
- [ ] #17 The Dashboard daily-accomplishment data can count a newly recorded referral request as a user action without counting edits, retries, or duplicate records more than once.
- [ ] #18 The implementation does not depend on the vestigial Contact model or broaden into general-purpose CRM functionality unless an explicit design review concludes that model should remain supported.
- [ ] #19 Focused tests cover state derivation across job statuses, multiple recipients, duplicate recipient normalization and confirmation, explicit send recording, no state change on prompt copy/open, filtering, row summaries, history preservation, follow-up creation, timeline events, and accessibility labels.
<!-- AC:END -->
