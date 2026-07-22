---
id: DRAFT-001
title: 'Won''t Do: Detect application confirmation pages and auto-record Applied'
status: Draft
assignee: []
created_date: '2026-07-22 20:59'
labels:
  - wont-do
  - product-direction
  - browser-extension
dependencies: []
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Decision record: do not pursue automatic application-confirmation detection right now. The deferred direction would let browser integrations recognize a successful ATS submission and mark the matching JobHunt record Applied without manual action. Preserve this card for reconsideration; URL-based manual/Codex workflows remain separate.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A future implementation would require an explicit user-controlled confirmation before changing a job to Applied.
- [ ] #2 Detection would fail safely on ambiguous jobs and would not infer success from merely opening an application form.
<!-- AC:END -->
