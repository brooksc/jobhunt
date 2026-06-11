---
id: TASK-140
title: 'Docs: Correct MAS release artifact and upload guidance'
status: To Do
assignee: []
created_date: '2026-06-11 03:40'
labels:
  - documentation
  - release
  - mas
dependencies: []
references:
  - README.md
  - .github/workflows/release-mas.yml
  - docs/MAS-VALIDATION.md
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
README currently lists the Mac App Store artifact as `.ipa`, but the current MAS workflow exports and uploads a `.pkg` for Transporter/App Store Connect delivery.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 README distribution table lists the MAS artifact as `.pkg`, not `.ipa`.
- [ ] #2 Docs describe the current upload path through Transporter or App Store Connect matching the CI artifact.
- [ ] #3 Release docs distinguish GitHub DMG download from MAS package delivery.
<!-- AC:END -->
