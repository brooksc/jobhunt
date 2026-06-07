---
id: TASK-046
title: 'JobService + SiteService: capture ingestion, job/site workflows, CSV export'
status: To Do
assignee: []
created_date: '2026-06-07 22:47'
labels:
  - swift-rewrite
  - core
  - service
milestone: m-1
dependencies:
  - TASK-034
  - TASK-036
  - TASK-038
  - TASK-044
documentation:
  - swift-plan.md
  - server/api.js
  - server/db.js
  - server/export.js
  - tests/integration/api.test.js
  - tests/unit/export.test.js
priority: high
ordinal: 2300
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Goal: Port the domain orchestration the UI and HTTP server both call — capture ingestion (the heart of the app), job lifecycle mutations, site workflows, follow-up actions, contacts/cover letters, and CSV export. This collapses most of the legacy 38-route api.js into in-process Swift service methods (the UI calls these directly; only the extension endpoints stay HTTP — separate task).

## Read first
- swift-plan.md §7 (capture pipeline + what stays HTTP), §2 (in-process service layer), §9 (Export), §6.1 (all models), §10.2/§10.3 (UI actions these back).
- Legacy server/api.js — the route handlers' BUSINESS LOGIC (not the HTTP routing): POST /captures ingestion (validate → clean → hash → dedup → create job w/ auto job_number → enqueue extraction), /site-reviews + /api/sites CRUD + review scheduling (next_review_at, state machine), job status/notes/archive/delete/opened/read/rating/skills, bulk status / bulk llm / reset-extraction / data-quality-reviewed, actions (create/complete/snooze), contacts CRUD, cover-letter generate/delete, duplicates/decision.
- server/db.js (query helpers), server/export.js (CSV 19 columns).

## Implement (core/Services/JobService.swift, SiteService.swift, ExportService.swift)
- `JobService.ingestCapture(payload)` → returns (capture_id, job_number, duplicate) exactly matching the extension contract response; sets duplicate_of via DuplicateDetector; auto-enqueues extraction via the QueueActor (task-044).
- Job mutations: updateFields, setStatus (single+bulk), addNote, archive, delete, markOpened/Read, setRating, updateSkills, createAction/complete/snooze, contacts CRUD, generateCoverLetter (via engine) / delete, dataQualityReviewed add/clear, bulk reset-extraction, bulk enqueue LLM (extract/fit/missing-fields, incl. by job-number #N parsing).
- `SiteService`: upsert from site-review, CRUD, markReviewed (set last/next review), state transitions (not_reviewed/reviewed/exclude), interval scheduling.
- `ExportService.jobsCSV()` — port export.js (19 columns, RFC-4180 escaping). UI saves via NSSavePanel; provide the CSV string + a convenience writer.
- All writes through the BackgroundStore actor; emit relevant domain events (job-added) for badge/notification.

## Dependencies
Depends on task-034 (models), task-036 (cleaning/hash), task-038 (DuplicateDetector), task-044 (QueueActor enqueue + cover-letter generation). Consumed by the HTTP server (task O) and most screens.

## Tests (CoreTests/ServerTests) — port api.test.js business cases
- Capture ingestion: new job created with correct job_number + response shape; duplicate capture returns duplicate=true and links duplicate_of; validation rejects missing url/title/text. Bulk status/llm; action snooze/complete; site review scheduling; CSV column parity (port export.test.js). Use in-memory container + stub provider.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 ingestCapture matches the extension contract response (capture_id, job_number, duplicate) and auto-enqueues extraction
- [ ] #2 Duplicate captures link duplicate_of and return duplicate=true; invalid captures (missing url/title/text) rejected
- [ ] #3 Full job mutation surface implemented (status/bulk/notes/archive/delete/opened/read/rating/skills/actions/contacts/cover-letters/dq-review/bulk-llm incl #N parsing)
- [ ] #4 SiteService upsert + CRUD + review scheduling + state machine reproduce api.js behavior
- [ ] #5 ExportService CSV matches export.js columns + RFC-4180 escaping (ported export.test.js passes)
- [ ] #6 Ported api.test.js business cases pass on in-memory container with stub provider
<!-- AC:END -->
