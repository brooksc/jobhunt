---
id: TASK-034
title: 'SwiftData model layer: @Model types, SchemaV1, ModelContainer, MigrationPlan'
status: In Progress
assignee:
  - claude
created_date: '2026-06-07 22:43'
updated_date: '2026-06-08 01:41'
labels:
  - swift-rewrite
  - core
  - data
milestone: m-1
dependencies:
  - TASK-033
documentation:
  - swift-plan.md
  - server/db.js
  - server/export.js
priority: high
ordinal: 1100
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Goal: Define the complete persistence schema as SwiftData `@Model` types in JobhuntCore, matching the 13-table legacy SQLite data model 1:1, plus the versioned schema + container plumbing every service and screen reads through.

## Read first
- swift-plan.md §6.1 (full table→@Model mapping table), §6.2 (concurrency model), §6.4 (schema evolution), §1 (legacy schema overview).
- Legacy server/db.js — the authoritative schema (CREATE TABLE statements, columns, types, indexes, FKs, settings defaults). This is the source of truth for fields; read it thoroughly.
- server/export.js (CSV columns) to confirm which Job fields must persist.

## Implement (in core/Models/)
- One `@Model final class` per entity in §6.1: Capture, Job, JobEvent, SiteReview, DuplicateDecision, Setting, JobAction, DataQualityReview, Site, Resume, JobFitScore, LLMRequest, LLMRequestAttempt, Contact, CoverLetter.
- Model the relationships with `@Relationship` (e.g. Job↔Capture, Job→events/actions/contacts/coverLetters/fitScores, Resume→fitScores) with correct delete rules. Keep legacy integer keys as stored properties where the extension/CSV/MCP rely on them (especially `jobNumber` unique, capture `rawHash`/`cleanedHash`, site `origin`).
- Preserve JSON blob fields verbatim as String (extractedJSON, fitScoreJSON, structuredDataJSON, manualOverridesJSON).
- Add `#Unique` / `#Index` macros for jobNumber, rawHash, cleanedHash, site origin, and the (status, createdAt) query pattern on LLMRequest.
- Enums for status, extractionStatus, fitStatus, remoteType, site state, llm request type/status — with raw values matching the legacy string values exactly (parity for extension/MCP/CSV).
- Define `SchemaV1: VersionedSchema` listing all models and a `JobhuntMigrationPlan: SchemaMigrationPlan` (single stage for now) per §6.4.
- Provide a `ModelContainerFactory` helper: production container (on-disk, app data location) and an in-memory container for tests.
- Do NOT add settings business logic or the ModelActor here (separate task). Just the Setting model + the SETTINGS_DEFAULTS key list as a static reference (port from db.js).

## Dependencies
Depends on task-033 (project scaffold provides JobhuntCore target). All Core services, the server, and UI screens depend on this task.

## Tests (CoreTests)
- Insert/fetch round-trip for each model; relationship integrity; cascade deletes; uniqueness constraint enforcement (duplicate jobNumber / rawHash rejected).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 All 15 @Model types from §6.1 exist with fields matching server/db.js columns (types, nullability)
- [ ] #2 Relationships and delete rules modeled; legacy integer keys (jobNumber, hashes, origin) retained as properties
- [ ] #3 Enum raw values byte-match legacy string values (status/extractionStatus/remoteType/etc.)
- [ ] #4 SchemaV1 VersionedSchema + MigrationPlan defined; ModelContainerFactory provides on-disk and in-memory containers
- [ ] #5 CoreTests: round-trip + relationship + cascade + uniqueness tests pass for every model
- [ ] #6 JobhuntCore builds clean under Swift 6 strict concurrency (models Sendable-safe)
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
Files to create in core/Models/:
- Enums.swift: JobStatus, ExtractionStatus, FitStatus, RemoteType, SiteState, LLMRequestType, LLMRequestStatus
- Capture.swift, Job.swift, JobEvent.swift, SiteReview.swift, DuplicateDecision.swift
- Setting.swift (+ SettingsKeys enum), JobAction.swift, DataQualityReview.swift, Site.swift
- Resume.swift, JobFitScore.swift, LLMRequest.swift, LLMRequestAttempt.swift
- Contact.swift, CoverLetter.swift
- Schema.swift: SchemaV1 VersionedSchema + JobhuntMigrationPlan
- ModelContainerFactory.swift: on-disk (app data dir) and in-memory containers

Tests in Tests/CoreTests/:
- ModelRoundTripTests.swift: insert/fetch/relationship/cascade/uniqueness per model
<!-- SECTION:PLAN:END -->
