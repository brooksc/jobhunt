---
id: TASK-477
title: 'Migrator args: Reject missing option values and unknown flags'
status: Done
assignee: []
created_date: '2026-06-15 03:39'
updated_date: '2026-06-15 06:48'
labels:
  - bug
  - migrator
dependencies: []
references:
  - tools/migrator/Args.swift
modified_files:
  - tools/migrator/Args.swift
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Args.swift:44-77 option parsing is silently permissive. `--store`/`--input`/`--output` consume the next token with `if i < args.count` but silently ignore a missing value (e.g. `--store` as the last arg leaves the default production path in effect — a foot-gun for a destructive op). Unknown flags hit `default: break` and are ignored, so a typo like `--reclain` silently falls through. Fix: error out on a flag missing its required argument, and on unrecognized arguments.
<!-- SECTION:DESCRIPTION:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Args.swift now errors (prints to stderr + returns nil → exit 1) when --store/--input/--output is missing its path argument or is followed by another flag, instead of silently leaving the default in effect. Unrecognized arguments now hit `default:` with an "unknown argument" error instead of being silently ignored, so a typo'd flag (e.g. --reclain) fails loudly rather than falling through to the --output-required migrate path.
<!-- SECTION:FINAL_SUMMARY:END -->
