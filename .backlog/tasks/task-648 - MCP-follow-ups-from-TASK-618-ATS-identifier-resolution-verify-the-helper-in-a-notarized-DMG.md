---
id: TASK-648
title: >-
  MCP follow-ups from TASK-618: ATS-identifier resolution + verify the helper in
  a notarized DMG
status: To Do
assignee: []
created_date: '2026-07-25 21:34'
updated_date: '2026-08-10 00:03'
labels:
  - mcp
  - release
  - integration
dependencies: []
references:
  - core/Services/JobService+MarkApplied.swift
  - core/Services/URLNormalizer.swift
  - tests/CoreTests/MarkJobAppliedTests.swift
  - .github/workflows/release-dmg.yml
modified_files:
  - core/Services/JobService+MarkApplied.swift
  - tests/CoreTests/MarkJobAppliedTests.swift
priority: medium
ordinal: 89000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The two acceptance criteria left unchecked on TASK-618, recorded so they aren't quietly lost.

**AC #4 — stable ATS-identifier resolution.** `mark_job_applied` resolves by exact capture URL, stored canonical URL, normalized comparison, and the job's own `applicationURL`. It does NOT match on a stable ATS identifier independent of URL shape. So the same Greenhouse posting reached via `boards.greenhouse.io/acme/jobs/12345` and via an embedded `acme.com/careers?gh_jid=12345` will not resolve to one job. Note the deliberate constraint: `gh_jid`/`ashby_jid` must NOT be stripped as tracking params (they identify the posting) — pinned by `testEmbeddedBoardJobIDIsNotStrippedAsTracking`. The fix is to *extract and index* the ATS id, not to normalize it away.

**AC #16 — DMG helper verification.** Never done against a real artifact. `/Applications/Jobhunt.app` on the dev machine was populated by copying a local Debug build, which is linker-signed ad-hoc and is refused by macOS 27 (`load code signature error 2`); it only ran after `codesign -f -s -`. A notarized DMG still needs verifying: helper present at `Contents/Helpers/jobhunt-mcp`, executable, Developer ID signed with hardened runtime, able to resolve `@rpath/JobhuntCore.framework` from `Contents/Frameworks`, and completing a full MCP handshake while the app runs.

Do the AC #16 check as part of the next release that ships `mark_job_applied`.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The same posting reached via an ATS board URL and via an embedded board URL carrying the same ATS id resolves to one job
- [x] #2 gh_jid/ashby_jid remain un-stripped by URLNormalizer; the existing over-normalization regression test still passes
- [x] #3 Focused tests cover ATS-id matching, including two distinct postings on one embedded board staying distinct
- [ ] #4 A notarized DMG is inspected: Contents/Helpers/jobhunt-mcp is present, executable, Developer ID signed with hardened runtime
- [ ] #5 The DMG-installed helper completes initialize/tools/list/tools-call against the running app without re-signing
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
**2026-08-09 — AC #1–#3 done; #4–#5 parked as release-gated.**

`resolveJob` gained a final `jobsMatchingATSID` step: it extracts the ATS id from the incoming URL via `DuplicateDetector.atsPostingID` and compares it against the ids on every capture URL, canonical URL and applicationURL. Deliberately *last*, after every URL match — those are exact, this is an inference. 4 tests: board-vs-embedded resolving to one job, two postings on one embedded board staying distinct, a non-ATS URL still creating a new job, and `gh_jid` surviving normalization while `utm_source` doesn't (#2, guarded from the consuming side).

#4 and #5 are **not verified: requires a notarized DMG**, which means cutting a release — out of scope without an explicit request, and the task itself says to do this check as part of the next release that ships `mark_job_applied`. Leaving the task open for those two.
<!-- SECTION:NOTES:END -->
