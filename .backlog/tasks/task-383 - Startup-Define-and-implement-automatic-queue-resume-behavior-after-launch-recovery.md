---
id: TASK-383
title: >-
  Startup: Define and implement automatic queue resume behavior after launch
  recovery
status: To Do
assignee: []
created_date: '2026-06-12 22:55'
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
- [ ] #1 Decide whether launch recovery should auto-start processing when the queue is not paused or remain manual by design.
- [ ] #2 If automatic, start the drain loop after successful recovery and respect the queue paused setting.
- [ ] #3 If manual, make the queue view/dashboard surface pending recovered work clearly.
<!-- AC:END -->
