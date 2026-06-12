---
id: TASK-351
title: 'Release artifacts: Publish checksums and provenance for downloads'
status: Done
assignee: []
created_date: '2026-06-12 20:43'
updated_date: '2026-06-12 21:53'
labels:
  - audit
  - supply-chain
  - release
  - provenance
dependencies: []
references:
  - .github/workflows/release-dmg.yml
  - scripts/package-extension.sh
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The DMG release workflow notarizes and uploads the DMG plus Chrome extension zip, but does not generate or publish SHA256 checksums, SBOM/provenance, or release attestations. Users and maintainers have no repository-published digest for verifying downloaded artifacts.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Release workflow generates SHA256 checksums for the DMG and extension zip.
- [ ] #2 Checksums are attached to the GitHub Release alongside artifacts.
- [ ] #3 A provenance or attestation strategy is documented or implemented for release artifacts.
<!-- AC:END -->
