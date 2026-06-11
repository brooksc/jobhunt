---
id: TASK-135
title: 'Tests: Isolate mocked URLProtocol state for provider tests'
status: To Do
assignee: []
created_date: '2026-06-11 03:27'
labels:
  - tests
  - flakiness
  - llm
dependencies: []
references:
  - tests/CoreTests/LLMProviderTests.swift
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
LLM provider tests use static mutable URLProtocol state for captured requests and handlers. This is currently reset in setUp, but it can become order-dependent if tests run in parallel or a test exits early.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Provider mock URLProtocol state is scoped per test/session or guarded against cross-test leakage.
- [ ] #2 setUp and tearDown both clear handler and captured request state.
- [ ] #3 Parallel test execution behavior is either supported or explicitly disabled/documented for the provider test bundle.
- [ ] #4 A failure in one provider test cannot leave request handlers that affect the next provider test.
<!-- AC:END -->
