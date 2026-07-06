---
id: TASK-601
title: >-
  mas: confirmation-gated auto-delivery to App Store Connect + document curated
  MAS flow
status: Done
assignee: []
created_date: '2026-07-06 22:41'
labels:
  - mas
  - ci
  - release
dependencies: []
modified_files:
  - .github/workflows/release-mas.yml
  - docs/release-process.md
  - CLAUDE.md
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Automate the tedious part of MAS publishing (delivering the .pkg to App Store Connect) while keeping it a curated, manually-confirmed channel — the user wants to be selective about what ships to the App Store, so delivery must NEVER be automatic.

release-mas.yml now:
- Adds a workflow_dispatch boolean input `upload_to_app_store_connect` (default false).
- Adds an "Upload to App Store Connect" step (`xcrun altool --upload-app`, reusing the existing APPLE_ID + APPLE_APP_SPECIFIC_PASSWORD secrets — no new secret) gated on `github.event_name == 'workflow_dispatch' && inputs.upload_to_app_store_connect`. A tag build, or a dispatch with the box unchecked, only builds the .pkg artifact.
- Never auto-submits for review (that stays a manual App Store Connect step).
- Makes the artifact upload `if: always()` so the .pkg is retained even if delivery fails (Transporter fallback).

Docs:
- release-process.md §5 rewritten: explicit "MAS delivery is manual and curated" callout, a 4-step flow (build → validate → deliver-on-confirmation → submit-by-hand), and a step to paste the reviewer/testing notes from docs/app-store-metadata.md ("App Review notes") into App Store Connect each submission.
- CLAUDE.md: standing rule — never deliver to the Mac App Store without the user's explicit per-release confirmation.</description>
<parameter name="acceptanceCriteria">["A tag build or an unchecked dispatch run produces the .pkg artifact and does NOT upload to App Store Connect", "A workflow_dispatch run with upload_to_app_store_connect checked uploads the .pkg via altool using existing secrets", "The workflow never auto-submits for review; the .pkg artifact is retained even if upload fails", "release-process.md §5 documents the curated flow + the reviewer-notes step; CLAUDE.md records the confirm-before-MAS rule", "release-mas.yml is valid YAML"]
<!-- SECTION:DESCRIPTION:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
MAS .pkg delivery to App Store Connect is now a confirmation-gated workflow_dispatch step (upload_to_app_store_connect checkbox) using altool + existing Apple secrets; tags/unchecked runs only build the artifact, and the workflow never auto-submits for review. Documented the curated MAS flow (build → validate → deliver-on-confirmation → submit-by-hand + reviewer notes from app-store-metadata.md) in release-process.md §5 and recorded the confirm-before-MAS rule in CLAUDE.md.
<!-- SECTION:FINAL_SUMMARY:END -->
