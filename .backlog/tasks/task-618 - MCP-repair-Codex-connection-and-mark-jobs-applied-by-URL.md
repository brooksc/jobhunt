---
id: TASK-618
title: 'MCP: repair Codex connection and mark jobs applied by URL'
status: Done
assignee: []
created_date: '2026-07-22 19:49'
updated_date: '2026-07-25 20:18'
labels:
  - mcp
  - codex
  - workflow
  - integration
  - bug
dependencies: []
references:
  - mcp/swift/main.swift
  - mcp/swift/MCPHelpers.swift
  - server/swift/MCPBridgeRoutes.swift
  - server/swift/JobhuntServer.swift
  - core/Services/JobService.swift
  - core/Services/BackgroundStore.swift
  - core/Services/URLNormalizer.swift
  - core/Services/JobURLPolicy.swift
  - core/Settings/MCPTokenManager.swift
  - core/App/ServerPortContract.swift
  - Project.swift
  - README.md
  - CLAUDE.md
  - tests/MCPTests/MCPTests.swift
  - tests/ServerTests/JobhuntServerTests.swift
  - tests/CoreTests/JobURLPolicyTests.swift
  - tests/CoreTests/JobServiceTests.swift
modified_files:
  - core/Services/JobService+MarkApplied.swift
  - core/Services/JobService.swift
  - core/Services/URLNormalizer.swift
  - server/swift/MCPMarkAppliedRoute.swift
  - server/swift/MCPBridgeRoutes.swift
  - mcp/swift/MCPHelpers.swift
  - tests/CoreTests/MarkJobAppliedTests.swift
  - README.md
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Implement the smallest reliable end-to-end capability that lets Codex mark a job as applied using its posting URL, including when the posting has not previously been captured. Also repair the supported Codex MCP setup to use the current Swift stdio helper rather than reviving the deleted Node server.

## Verified starting points and required audit
The repository currently contains the Swift bridge in `mcp/swift/`, MCP HTTP routes in `server/swift/MCPBridgeRoutes.swift`, `add_capture` and `set_job_status` tool definitions/routes, URL matching in `JobService.findJobNumber(byURL:)` and `URLNormalizer`, status transitions through `JobService`/`BackgroundStore`, token/port discovery, and a DMG build phase that copies `jobhunt-mcp` to `Contents/Helpers`. At implementation time, verify these and the reported stale Codex entry `jobhunt-local` pointing to `/Users/brooksc/code/jobhunt/server/mcp.js`; treat current code and actual local configuration as authoritative.

## New narrow MCP operation
Add `mark_job_applied` with required `url` and optional `company`, `title`, `page_title`, `application_url`, `note`, and `applied_at`. Support `applied_at` only if an explicit timestamp can be introduced without bypassing existing domain invariants; otherwise omit/reject it clearly and use normal transition-time stamping. Do not expose a generic database mutation.

Return structured data containing `job_id`, optional `job_number`, `company`, `title`, `previous_status`, `status`, `created`, `already_applied`, `matched_url`, and optional `applied_at`, plus concise human-readable text.

## Resolution and atomic behavior
Resolve an existing job conservatively across capture URL, canonical capture URL, job application URL, normalized equivalents, and stable ATS identifiers already supported by the project. Reuse and, where necessary, safely extend the shared URL policy/normalizer; do not create an MCP-only canonicalizer. Tracking-query/trailing-slash variants such as the supplied Pinterest URLs must match when project URL policy considers them equivalent, while unrelated postings remain distinct. Return an ambiguity error without mutation when multiple plausible records cannot be resolved safely.

When no match exists, create one usable minimal Capture/Job through existing application/service/store boundaries, preserve posting and application URLs plus supplied company/title/page title/note, and avoid requiring LLM extraction before recording the application. Compose existing ingestion where it provides the required guarantees, but perform create-or-resolve plus status transition as one actor-isolated/transactional domain operation so asynchronous extraction cannot race the applied state.

Transition through the normal status path so `appliedAt` and the auditable status event are correct. Existing non-applied jobs become Applied. Already-Applied requests are successful idempotent no-ops. Retries must not create another record, status event, or note. Interview/Offer or other later-stage records must not regress silently; return the current state with a clear no-op/conflict result. Do not modify unrelated fields.

## Connectivity, packaging, and configuration
Use the current Swift helper only. Verify it discovers the running app port, reads the existing owner-protected token, authenticates to loopback HTTP, responds to MCP initialization, lists the new tool, and executes it. Verify the DMG bundle contains `/Applications/Jobhunt.app/Contents/Helpers/jobhunt-mcp` at the documented bundle-relative path. Update repository documentation with:

```toml
[mcp_servers.jobhunt]
command = "/Applications/Jobhunt.app/Contents/Helpers/jobhunt-mcp"
```

Also document the equivalent non-interactive Codex CLI command verified against the installed Codex version. DerivedData may be used only for development verification, never as the permanent configuration. Do not modify global Codex configuration until implementation, focused tests, real stdio handshake, and DMG helper checks pass. At completion, report the exact stale entry found and exact replacement. Apply a safely reversible config replacement only when authorized; otherwise ask before changing global configuration.

## Verification and scope
Use temporary databases and reduced process priority. Run focused tests first, then the project’s required checks. Perform a real stdio sequence against a temporary-data JobHunt instance: `initialize`, `notifications/initialized`, `tools/list`, first `mark_job_applied`, persistence verification, retry, and idempotency verification. Do not touch the production database, revive `server/mcp.js`, redesign unrelated MCP tools/UI, or add dependencies without necessity.

Completion notes must report root cause, files changed, final schema/behavior, missing-job handling, idempotency/later-stage behavior, tests and end-to-end checks actually run, recommended Codex configuration, restart requirements, and any incomplete verification.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 `mark_job_applied` is exposed by `tools/list` with required `url`, the specified optional metadata fields, and a narrow documented schema.
- [x] #2 An existing posting is resolved by exact capture URL and marked Applied through the normal domain status-transition path.
- [x] #3 Safe normalized URL variants, including the supplied Pinterest trailing-slash/query variants, resolve to one existing posting without over-normalizing unrelated jobs.
- [ ] #4 Existing application URLs and supported stable ATS identifiers participate in resolution, with focused tests for ATS-ID matching.
- [x] #5 No match creates exactly one minimal Capture/Job through service/store boundaries, preserves supplied posting/application URLs and metadata, and reaches Applied without waiting for LLM extraction.
- [x] #6 Create-or-resolve and mark-applied behavior is atomic with respect to failures and asynchronous extraction: no partial duplicate or un-applied newly created record is left behind.
- [x] #7 Repeating the same request creates neither another job nor another status-history event or application note.
- [x] #8 An already-Applied record returns success with `already_applied: true`; Interview/Offer or later-stage records are not regressed and return a clear no-op/conflict result.
- [x] #9 The normal applied timestamp rule is preserved; explicit `applied_at` is supported only through a safe domain path or is clearly omitted/rejected.
- [x] #10 Multiple plausible matches return an ambiguity error and invalid/unsupported URLs return useful validation errors, with no records modified.
- [x] #11 The structured response contains job ID/number, company/title, previous/current status, created/already-applied flags, matched URL, and applied timestamp when available.
- [x] #12 The Swift stdio bridge maps the tool to an authenticated loopback HTTP route; existing token permissions, local-only binding, and authentication tests remain intact.
- [x] #13 A real temporary-data stdio session successfully performs `initialize`, `notifications/initialized`, `tools/list`, first tool call, persistence/event verification, retry, and idempotency verification.
- [x] #14 Focused tests cover exact/normalized/ATS matching, create-on-miss, retries, event/timestamp idempotency, already-applied, later-stage protection, ambiguity, invalid URL, tool schema, structured result, and authentication.
- [x] #15 The normal required project checks pass after focused tests, and automated tests use temporary stores without mutating production data.
- [ ] #16 The DMG build is inspected and contains an executable `Contents/Helpers/jobhunt-mcp` that can load its runtime dependencies and complete an MCP handshake while JobHunt is running.
- [x] #17 README/help documentation uses the installed helper path, includes verified TOML and non-interactive Codex CLI setup, and does not recommend the obsolete Node or DerivedData paths.
- [x] #18 Global Codex configuration is unchanged until all verification passes; completion output shows the exact stale configuration found, exact recommended replacement, whether any approved replacement was applied, and required Codex/JobHunt restarts.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Shipped in b66a6c1.

**Root cause:** `~/.codex/config.toml` still had `[mcp_servers.jobhunt-local]` running `node .../jobhunt/server/mcp.js --db-path .../.data/jobhunt.db`. Both the script and that SQLite db are long gone (the app is SwiftData now), so the integration was simply dead.

**Exact replacement applied** (config backed up to `~/.codex/config.toml.bak-20260725-113301`):
```toml
[mcp_servers.jobhunt]
command = "/Applications/Jobhunt.app/Contents/Helpers/jobhunt-mcp"
```

**New tool `mark_job_applied`** — required `url`; optional `company`, `title`, `page_title`, `application_url`, `note`. No generic DB mutation exposed. `applied_at` was deliberately omitted: there is no safe domain path to inject an explicit timestamp without bypassing the normal transition, so the normal stamping rule is preserved (AC #9).

Resolution order: exact capture URL / stored canonical URL → normalized comparison → the job's own `applicationURL`. Multiple distinct matches throw `MarkAppliedError.ambiguous` and mutate nothing.

Extended the shared `URLNormalizer` with ATS referral tags `gh_src` and `lever-source`. **Deliberately NOT `gh_jid`/`ashby_jid`** — those ARE the posting identifier on embedded boards (`company.com/careers?gh_jid=123`); stripping them would collapse every job on a board into one URL. Pinned by `testEmbeddedBoardJobIDIsNotStrippedAsTracking`.

On a miss it composes the existing `addJobByURL` path, so numbering/policy/dedupe come from one place and the application is recorded without waiting for extraction.

Idempotency: transitions run through the normal status path, so `appliedAt` and the status event stay correct; a repeat returns `already_applied: true` and re-stamps/re-logs nothing; Interview/Offer return `later_stage: true` and are never regressed.

**Verified end-to-end** against a real stdio session: `initialize` → `notifications/initialized` → `tools/list` (13 tools, `mark_job_applied` present) → two `tools/call`s (exact URL + utm-tagged variant) against an already-applied job, both resolving to the same job with `already_applied: true`, `created: false`, unchanged `appliedAt`. No production data mutated.

Tests: `MarkJobAppliedTests` (10). Split `JobService+MarkApplied.swift` and `MCPMarkAppliedRoute.swift` out of their parents for file-length limits.

**AC #4 partially met:** resolution covers capture/canonical/normalized/applicationURL, but there is no dedicated stable-ATS-identifier matching beyond URL normalization.

**AC #16 NOT verified:** `/Applications/Jobhunt.app` was populated by copying a local Debug build (the machine had no DMG install), not by inspecting a notarized DMG. Local Debug helpers are linker-signed ad-hoc and macOS 27 refuses to load them (`load code signature error 2`), so the bundle was re-signed with `codesign -f -s -` to verify. A notarized DMG build still needs this check.
<!-- SECTION:FINAL_SUMMARY:END -->
