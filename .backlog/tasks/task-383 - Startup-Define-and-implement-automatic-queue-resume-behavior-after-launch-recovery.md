---
id: TASK-383
title: >-
  Startup: Define and implement automatic queue resume behavior after launch
  recovery
status: Done
assignee: []
created_date: '2026-06-12 22:55'
updated_date: '2026-06-16 16:43'
labels:
  - audit
  - concurrency
  - startup
  - llm-queue
dependencies: []
references:
  - app/Shell/AppServices.swift
  - core/LLM/QueueActor.swift
  - app/Views/Queue/LLMQueueView.swift
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
requeueRunningOnLaunch() resets stuck running requests to queued, but nothing starts processing on launch. Processing only starts from UI paths, which may leave recovered requests idle indefinitely.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Decide whether launch recovery should auto-start processing when the queue is not paused or remain manual by design.
- [x] #2 If automatic, start the drain loop after successful recovery and respect the queue paused setting.
- [ ] #3 If manual, make the queue view/dashboard surface pending recovered work clearly.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
AC#1 decision: automatic resume. After `requeueRunningOnLaunch()` succeeds, `AppServices.startRuntime` now calls `queue.startProcessing()` so crash-recovered (running→queued) requests and any other pending work resume automatically instead of sitting idle until a UI action. AC#2: `startProcessing()` breaks at the top of its loop when `isPaused()` is true, so the auto-resume respects the user's paused setting — no change needed there. Test (CoreTests): the launch sequence (requeueRunningOnLaunch + startProcessing) on a paused queue leaves a recovered `.queued` request queued; the non-paused drain is already covered by existing startProcessing tests. AC#3 (manual surfacing) is N/A given the automatic decision. App builds; CoreTests green.
<!-- SECTION:FINAL_SUMMARY:END -->
