---
id: TASK-403
title: 'Pin Tart VM image to a specific digest instead of :latest'
status: Done
assignee: []
created_date: '2026-06-12 23:54'
updated_date: '2026-06-17 04:52'
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
- [x] #1 VM_IMAGE in run-ui-tests-in-vm.sh references a specific digest, not :latest
- [x] #2 A comment next to VM_IMAGE documents the Xcode and macOS version
- [x] #3 docs/vm-testing.md updated with the pinned digest and upgrade instructions
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Pinned `VM_IMAGE` in run-ui-tests-in-vm.sh to the immutable digest `sha256:31413f28df83c37b94e76f8feea8046fb1950b3ed42195523408477189a3f76d` (resolved live from the ghcr `:latest` manifest on 2026-06-17), replacing the drift-prone `:latest` default (AC#1). An inline comment documents the image (macOS Sequoia 15.x, bundled latest Xcode) and an upgrade recipe (AC#2). docs/vm-testing.md's pinning section records the digest + a no-Tart-needed upgrade recipe via the ghcr manifest API (AC#3). Per-run `VM_IMAGE=…` override preserved; script passes `bash -n`. The exact bundled Xcode point version isn't derivable from the digest alone — noted as "bundled latest Xcode"; the maintainer can refine it from the VM after a clone. Can't run Tart here, so the clone itself is unverified, but the digest is real and the OCI `@sha256:` reference form is what Tart accepts.
<!-- SECTION:FINAL_SUMMARY:END -->
