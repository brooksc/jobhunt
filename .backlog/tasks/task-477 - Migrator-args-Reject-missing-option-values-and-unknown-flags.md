---
id: TASK-477
title: 'Migrator args: Reject missing option values and unknown flags'
status: To Do
assignee: []
created_date: '2026-06-15 03:39'
labels:
  - bug
  - migrator
dependencies: []
references:
  - tools/migrator/Args.swift
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Args.swift:44-77 option parsing is silently permissive. `--store`/`--input`/`--output` consume the next token with `if i < args.count` but silently ignore a missing value (e.g. `--store` as the last arg leaves the default production path in effect — a foot-gun for a destructive op). Unknown flags hit `default: break` and are ignored, so a typo like `--reclain` silently falls through. Fix: error out on a flag missing its required argument, and on unrecognized arguments.
<!-- SECTION:DESCRIPTION:END -->
