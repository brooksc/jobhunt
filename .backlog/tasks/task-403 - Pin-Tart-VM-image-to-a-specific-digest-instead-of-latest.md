---
id: TASK-403
title: 'Pin Tart VM image to a specific digest instead of :latest'
status: To Do
assignee: []
created_date: '2026-06-12 23:54'
labels: []
dependencies: []
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The run script clones `ghcr.io/cirruslabs/macos-sequoia-xcode:latest`, which silently drifts to a new Xcode or OS patch version whenever Cirrus Labs pushes a new image. This can cause tests to break after a `tart delete && tart clone` without any code change.

Pin to a specific digest in `run-ui-tests-in-vm.sh`. Store the digest in the `VM_IMAGE` constant with a comment documenting the exact Xcode and macOS versions. Update `docs/vm-testing.md` and `CLAUDE.md` with the pinned digest and upgrade instructions.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 VM_IMAGE in run-ui-tests-in-vm.sh references a specific digest, not :latest
- [ ] #2 A comment next to VM_IMAGE documents the Xcode and macOS version
- [ ] #3 docs/vm-testing.md updated with the pinned digest and upgrade instructions
<!-- AC:END -->
