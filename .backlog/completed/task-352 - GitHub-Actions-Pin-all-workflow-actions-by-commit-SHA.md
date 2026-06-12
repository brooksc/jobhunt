---
id: TASK-352
title: 'GitHub Actions: Pin all workflow actions by commit SHA'
status: Done
assignee: []
created_date: '2026-06-12 20:43'
updated_date: '2026-06-12 21:53'
labels:
  - audit
  - supply-chain
  - github-actions
  - ci
dependencies: []
references:
  - .github/workflows/llm-eval.yml
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Most release/build workflows pin actions by SHA, but llm-eval.yml still uses moving tags for actions/checkout@v4 and actions/upload-artifact@v4. This scheduled workflow also receives LLM-related secrets.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 All GitHub Actions uses entries are pinned by full commit SHA.
- [ ] #2 Comments record the human-readable action version for maintainability.
- [ ] #3 A lightweight check or documented review rule prevents reintroducing moving action tags.
<!-- AC:END -->
