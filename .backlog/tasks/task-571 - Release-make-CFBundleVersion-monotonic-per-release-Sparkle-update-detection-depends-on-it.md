---
id: TASK-571
title: >-
  Release: make CFBundleVersion monotonic per release (Sparkle update detection
  depends on it)
status: To Do
assignee: []
created_date: '2026-06-20 05:06'
labels:
  - release
  - distribution
  - sparkle
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## Why

`Project.swift` sets `currentProjectVersion("202606142301")` as a fixed constant (CFBundleVersion).
Sparkle's default version comparator compares `sparkle:version` (= CFBundleVersion, read from the app
by `generate_appcast`) against the running app's CFBundleVersion. **If two releases ship the same
CFBundleVersion, Sparkle silently sees no update** even though marketingVersion (1.0.1 → 1.0.2)
increased. `version-parity.yml` only checks marketingVersion vs tag vs extension — it does NOT guard
CFBundleVersion, so this fails silently.

## Options
- Bump `currentProjectVersion` manually each release (cheapest; needs a release-checklist line + ideally
  a CI guard that the new value > the currently-published one).
- Derive it deterministically (e.g. monotonic timestamp or git commit count) at generate time.

## Acceptance
- Successive tagged releases always have strictly-increasing CFBundleVersion.
- Ideally a CI check (release-dmg.yml or version-parity.yml) fails a release whose CFBundleVersion is
  not greater than the previously published one.
<!-- SECTION:DESCRIPTION:END -->
