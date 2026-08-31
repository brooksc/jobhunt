---
id: TASK-704
title: >-
  The coverage gate never runs on a release tag — the one build that ships is
  the one nothing checks
status: To Do
assignee: []
created_date: '2026-08-31 19:39'
labels: []
dependencies: []
priority: medium
type: bug
ordinal: 78000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From the 2026-08-31 backlog audit. [[TASK-062]]'s AC#4 is ticked, but the gate it asserts does not run on the builds that matter. **Verified.**

`check-coverage.sh` appears in exactly one place — `.github/workflows/swift-build.yml:119` — and that workflow is configured:

```yaml
on:
  push:
    branches: [main, swift-rewrite]
    tags-ignore: ['v*']
```

`release-dmg.yml` and `release-mas.yml` fire on `v*` tags. `swift-build.yml` explicitly ignores them. So **no coverage check runs on any release build**. The gate covers development pushes and skips the artifact that reaches users.

The `tags-ignore` is defensible on its own terms — the comment above it explains macOS runners cost 10× a Linux one and this is the only macOS job on every push, so the intent was to avoid a duplicate build on the tag that immediately follows a merge. In practice a tag is usually cut from an already-built `main` commit, so the coverage number is *usually* known. But "usually" is doing load-bearing work: a tag cut from a commit that skipped the workflow (a `docs/**`-only push, a `.backlog/**` push, or a direct tag) ships unchecked.

Worth weighing against a second, related finding: the floor is currently **70%** while real coverage is Core 90.87% / Server 61.96% / combined 88.80% — roughly 19 points of dead headroom, so the gate cannot fail on any plausible change, and `app/` (~22,500 lines) plus the migrator are outside it entirely. A gate that can neither fire nor cover the largest target is not protection, and moving it to the release path without fixing that would just relocate the theatre.

**Decide between two honest options rather than papering over it:**
1. Raise the floor to something near current coverage (a ratchet, like `.warning-baseline`), extend it to `app/`, and run it on the release path.
2. Accept that the gate is advisory, say so in `docs/release-process.md`, and stop treating AC#4 as satisfied.

Either is defensible. What isn't is a ticked acceptance criterion asserting a gate that does not run.
<!-- SECTION:DESCRIPTION:END -->
