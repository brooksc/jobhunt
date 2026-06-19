---
id: TASK-526
title: >-
  Concurrency: keep live SwiftData models inside the BackgroundStore actor
  boundary
status: In Progress
assignee: []
created_date: '2026-06-19 04:45'
updated_date: '2026-06-19 05:26'
labels:
  - audit
  - concurrency
  - swiftdata
  - architecture
dependencies: []
references:
  - core/Services/BackgroundStore.swift
  - core/Services/JobService.swift
  - core/LLM/QueueActor.swift
  - core/Services/SiteService.swift
  - server/swift/MCPBridgeRoutes.swift
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Finding: `BackgroundStore.fetch` returns live SwiftData `@Model` instances to other actors and callers. `JobService`, `QueueActor`, `SiteService`, MCP route helpers, and tests then read those objects outside the `@ModelActor`, sometimes across additional awaits and sometimes pass them back into later store calls for relationships such as `event.job`, `attempt.request`, or `attempt.job`.

Why this matters: SwiftData model instances are context-bound mutable objects. Letting them escape the store actor makes the real persistence boundary ambiguous: callers can observe stale data after an await, attach relationships with objects fetched earlier, or add new code that mutates model instances outside the store actor. Strict concurrency warnings can be papered over by SwiftData/import behavior, but the architectural invariant is still weak.

Suggested implementation: introduce store APIs that return Sendable projections for reads and scoped store-actor operations for relationship creation/mutation. Convert high-risk flows first: `JobService` note/action/contact creation, `QueueActor` attempt linking, and MCP resolution. Keep direct live-model fetch available only for tests or clearly documented internal use if needed.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Production service APIs no longer need to carry live `Job`, `LLMRequest`, `Resume`, or `Site` model instances across actor boundaries for common read/mutation flows.
- [ ] #2 Queue attempt creation links request/job relationships inside a single `BackgroundStore` operation using IDs, not previously-fetched live model references.
- [ ] #3 JobService child-record creation links records to jobs inside a store-scoped operation using IDs.
- [ ] #4 Read paths that cross actors return Sendable projections or scalar snapshots instead of live SwiftData models where practical.
- [ ] #5 Focused tests cover the converted queue attempt-linking and JobService child-record creation paths.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Progress (Claude, opus-4.8) — commit af37f17: the HOT-PATH processors are fixed, which was the dangerous part. processExtractRequest/processFitRequest no longer hold any live @Model: added BackgroundStore.extractionSnapshot(forJobID:), fitInputs(forJobID:resumeID:) (Sendable snapshots built on the store actor), recordAttempt(requestID:jobID:...) (creates+links the attempt on the store actor), and requestStatus(id:) (Sendable status for the cancelled-while-running guards). Removed the off-actor lazy-relationship reads (job.capture?.url) and relationship mutations (attempt.job = job). Verified by the MockLLM end-to-end pipeline + fit tests (all green).

REMAINING (smaller follow-up): enqueue() does `req.job = job` off-actor, and enqueueFit() hands [Job]/Resume to insertFitBatch. These run mostly store-side and have subtle kick/dedup behavior (see the addJobByURL kick comment in JobService), so I deliberately left them out of the pre-release change to bound regression risk. To finish: add store.insertRequests(jobIDs:mode:)->Bool and store.insertFitBatch(jobIDs:resumeID:) that fetch+link inside the actor, and have enqueue/enqueueFit pass ids only. Low risk to the running app (these are insert paths, immediately persisted) but should be done to fully close the boundary.
<!-- SECTION:NOTES:END -->
