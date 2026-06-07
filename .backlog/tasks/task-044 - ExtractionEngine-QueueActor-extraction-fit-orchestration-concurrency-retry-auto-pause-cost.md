---
id: TASK-044
title: >-
  ExtractionEngine + QueueActor: extraction/fit orchestration, concurrency,
  retry, auto-pause, cost
status: To Do
assignee: []
created_date: '2026-06-07 22:46'
labels:
  - swift-rewrite
  - core
  - llm
milestone: m-1
dependencies:
  - TASK-034
  - TASK-036
  - TASK-037
  - TASK-039
  - TASK-042
documentation:
  - swift-plan.md
  - server/extract.js
  - server/db.js
  - tests/integration/concurrency.test.js
  - tests/integration/cost.test.js
priority: high
ordinal: 2100
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Goal: Port the extraction/fit-scoring orchestration — the persistent request queue with per-provider concurrency, retry/backoff, auto-pause, attempt logging, domain events, and token/cost accounting. This is the engine that ties providers + normalization + fit scoring + the DB together.

## Read first
- swift-plan.md §8.6 (the queue), §8.7 (cost & pricing), §8.1–8.5 (engine context), §6.2 (ModelActor), §10.8 (LLM Queue screen expectations), §10.5 (events → notifications).
- Legacy server/extract.js — the full queue lifecycle: enqueue, pop/process, status transitions (queued→running→succeeded/failed), per-provider concurrency, 429 exponential backoff + rotation-pool pause, **auto-pause after 2 consecutive failures**, OpenRouter free-model rotation timing, attempt-history writes (model requested/returned, durations, response preview, prompt/response chars), and the process events jobhunt:job-ready / job-unavailable / ai-processing-complete / queue-auto-paused.
- server/db.js — llm_requests / llm_request_attempts helpers (enqueue, requeueRunningRequests on launch, counts, cancel/reset).
- tests/integration/concurrency.test.js, tests/integration/cost.test.js.

## Implement (core/LLM/ExtractionEngine.swift, QueueActor.swift, CostEstimator.swift)
- `QueueActor` (built on the BackgroundStore ModelActor) managing LLMRequest rows: enqueue(jobIDs, mode: extract|fit_score|missing_fields), process loop with per-provider concurrency semaphores, retry/backoff, auto-pause-after-2-failures, pause/resume flag (settings), cancel/cancel-all/reset, requeue-running-on-launch.
- `ExtractionEngine.extract(job)`: build prompt (task-042 PromptBuilder) → provider.complete → JSONRepair/extract → normalize (task-037) → persist extracted_json + status; emit jobReady.
- Fit path: call provider → parse dimensions → FitScorer.computeScore (task-039) → persist JobFitScore + Job.fitScore; emit jobReady with fitScore.
- Write LLMRequestAttempt rows with full detail (for the Queue screen's attempt history).
- Domain events via an `AsyncStream`/Combine publisher: `jobReady(jobNumber,title,fitScore)`, `jobUnavailable`, `aiProcessingComplete(processed,failed)`, `queueAutoPaused` — consumed by platform integration (notifications/dock).
- `CostEstimator`: token estimate (chars/4) over all jobs + active resumes (port /api/llm-cost) and live OpenRouter pricing fetch (port /api/llm-pricing). Used by Settings/Debug.

## Dependencies
Depends on task-034 (models), task-042 (providers+prompts), task-037 (normalization), task-039 (FitScorer), task-036 (JSONRepair/cleaning). Consumed by LLM Queue screen, Detail (extract/fit triggers), JobService (auto-enqueue on capture), platform integration (events).

## Tests (ServerTests/CoreTests)
- Port concurrency.test.js (per-provider limits, queue draining) and cost.test.js (token/cost math) using a stub LLMProvider. Verify auto-pause after 2 consecutive failures, retry/backoff, attempt-history rows, and event emission. Use in-memory container + stub provider (no network).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 QueueActor manages LLMRequest lifecycle with per-provider concurrency, retry/backoff, and auto-pause after 2 consecutive failures
- [ ] #2 Extraction path: prompt→provider→repair→normalize→persist; fit path: provider→dimensions→FitScorer→persist
- [ ] #3 LLMRequestAttempt rows record model requested/returned, durations, response preview, prompt/response chars
- [ ] #4 Domain events (jobReady/jobUnavailable/aiProcessingComplete/queueAutoPaused) emitted on a stream
- [ ] #5 CostEstimator reproduces /api/llm-cost token math and fetches OpenRouter pricing
- [ ] #6 Ported concurrency.test.js + cost.test.js pass with a stub provider on an in-memory container (no network)
<!-- AC:END -->
