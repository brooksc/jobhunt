---
id: TASK-464
title: >-
  Electron parity: remaining minor gaps (meets_criteria, MCP job_id, MCP
  add_site/job payload, Onboarding, Jobs bulk actions)
status: Done
assignee: []
created_date: '2026-06-14 04:40'
updated_date: '2026-06-17 04:29'
labels:
  - electron-parity
  - cleanup
  - mcp
  - ui
dependencies: []
references:
  - core/LLM/ExtractionEngine.swift
  - mcp/swift/MCPHelpers.swift
  - server/swift/MCPBridgeRoutes.swift
  - app/Views/Onboarding/OnboardingView.swift
  - app/Views/Jobs/JobsView.swift
  - app/Views/Settings/DebugTab.swift
  - static/onboarding.jsx@8c438ca
  - static/screens/jobs.jsx@8c438ca
  - static/screens/settings.jsx@8c438ca
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Tracks the smaller Electron→Swift parity gaps NOT covered by the Phase 5 provider tasks (461-463) and NOT intentionally excluded (Apply workflow + Jobs configurable columns were explicitly dropped by the user). Each is independent; split into separate tasks if/when picked up.

## 1. `meets_criteria` location pass/fail flag (CHANGED)
Electron computed a per-job `meets_criteria` boolean (`applyLocationFilter`, extract.js ~800-870) from remote_type + preferred-location match + allow remote/hybrid/onsite, and persisted it. Swift only NULLs a disallowed `remoteType` (ExtractionEngine.swift ~150-160) and stores no flag. To restore: add optional `Job.meetsCriteria: Bool?` (additive, no migration per Schema.swift policy), compute it post-extraction, surface it in the detail view + as a Jobs filter.

## 2. MCP `job_id` back-compat (CONTRACT BREAK)
Electron MCP job tools keyed on `job_id` (string); Swift requires `job_number` (MCPHelpers.swift:127, MCPBridgeRoutes.swift:14-21). Any saved agent script using `job_id` breaks. Fix: accept EITHER `job_id` or `job_number` in the MCP job tools/routes (resolve job_id→job_number internally), keep job_number as primary.

## 3. MCP `add_site` fields + job payload richness (REDUCED)
- `add_site` (MCPHelpers.swift ~214-223, MCPBridgeRoutes handleMCPSiteAdd) accepts only url+name. Electron accepted note/state/company_website/jobs_url/company_description/interval_days. SiteService.createSite + updateSite already support most of these (update_site was extended in task-da908ff); extend add_site similarly.
- `job_get`/`jobs_list` MCP payloads dropped `events[]`, hashes, `cleaned_description`, `extracted_json`, `employment_type`, `seniority`, `duplicate_of_job_id` vs Electron (MCPBridgeRoutes.swift ~127-167). Add back the useful ones (events[], employment_type, seniority, duplicate_of_job_id at least).

## 4. Onboarding richness (CHANGED/SIMPLIFIED)
Swift onboarding lost: provider cards w/ taglines, per-provider "Get API key" links (API_KEY_URLS), LM Studio download link, in-onboarding "Fetch models", metro grid, and the summary step's config rows + "Don't show again". Files: app/Views/Onboarding/OnboardingView.swift vs static/onboarding.jsx@8c438ca. At minimum add the per-provider "Get API key" links + a "reopen onboarding" button in Settings/Debug (also missing).

## 5. Jobs bulk actions (MISSING)
Electron Jobs had bulk "Compare selected", "Open pages" (open all source URLs), and a "Queue AI" dialog with 3 sub-modes (missing-fields-only / fit-only / full). Swift only has bulk re-run AI + archive. Files: app/Views/Jobs/JobsView.swift (toolbar bulk menu) vs jobs.jsx@8c438ca. "Open pages" + a fit-only / extract-only queue mode are the most useful.

## 6. (deferred earlier) Settings missing odds-and-ends
llm_debug_level toggle, context-window sizing indicator, OpenRouter cost-model lookup, demo-mode switch, config/DB path display, "reopen onboarding" — all dropped from Settings vs settings.jsx@8c438ca. Low priority.

NOTE: Deliberately excluded by the user (do NOT implement): the Apply workflow (Contacts/Cover letters/application instructions) and the Jobs configurable column table.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 meets_criteria: optional Job.meetsCriteria computed post-extraction, shown in detail + available as a Jobs filter
- [x] #2 MCP job tools accept either job_id or job_number (job_id resolved internally)
- [x] #3 MCP add_site accepts the richer field set (note/state/company_website/jobs_url/company_description/interval_days); job_get/jobs_list re-add events[], employment_type, seniority, duplicate_of_job_id
- [x] #4 Onboarding adds per-provider Get-API-key links; Settings adds a Reopen-Onboarding button
- [x] #5 Jobs bulk actions add Open-pages and a fit-only/extract-only queue mode
- [x] #6 Apply workflow and Jobs configurable columns remain intentionally NOT implemented
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Backend MCP items done + committed:
- #2 (AC#2) DONE: MCP job tools accept job_id (Electron's internal jobs.id string, confirmed via `git show 8c438ca:server/mcp.js` → WHERE jobs.id = ?) OR job_number. CLI schemas/dispatch + server routes + JobService.getJob(byID:); resolveJob helper. Tested.
- #3 (AC#3) PARTIAL: add_site now accepts state/interval_days/note/company_website/jobs_url/company_description (create-then-update); job_get/jobs_list re-added employment_type, seniority, duplicate_of_job_id (JobDetailRecord/JobListRecord). DEFERRED: events[] payload — needs a new JobEvent projection.
- AC#6 holds: Apply workflow + Jobs configurable columns remain intentionally NOT implemented.

REMAINING (UI/model — recommend splitting into focused tasks; not runtime-verifiable in this headless env):
- #1 (AC#1): Job.meetsCriteria optional field + post-extraction compute + detail display + Jobs filter.
- #4 (AC#4): Onboarding per-provider Get-API-key links + Settings "Reopen Onboarding" button.
- #5 (AC#5): Jobs bulk "Open pages" + fit-only/extract-only queue mode.
- events[] for job_get; #6 settings odds-and-ends (low).
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
All sub-items implemented (#6 = the intentional-exclusions guard holds). #1: LocationCriteria.meets (Electron applyLocationFilter parity, unit-tested) + additive Job.meetsCriteria, computed post-extraction in ExtractionEngine and persisted by QueueActor; shown as a detail-view chip and a JobsView "Meets criteria only" filter. #2: MCP job tools accept job_id (internal id string — Electron back-compat) or job_number across CLI schemas/dispatch + server routes (resolveJob helper, JobService.getJob(byID:)); tested. #3: add_site accepts state/interval_days/note/company_website/jobs_url/company_description (create-then-update); job_get/jobs_list re-add employment_type/seniority/duplicate_of_job_id; job_get re-adds events[] (JobEventRecord projection). #4: per-provider Get-API-key links + LM Studio download link in onboarding; Settings→Debug "Reopen Onboarding" (OnboardingManager.reopen via .reopenOnboarding notification). #5: Jobs bulk "Score Fit on N Selected" (fit-only queue) + "Open N Pages" (display URLs). Tested where unit-testable (LocationCriteria, projections, MCP dispatch/schemas); UI portions (detail chip, Jobs filter/bulk menu, onboarding links, reopen button) are build-verified only — no headless runtime test. Apply workflow + Jobs configurable columns remain intentionally NOT implemented (AC#6). 814 CoreTests + Server + MCP green; app builds. The #6 settings odds-and-ends (debug-level toggle, cost-model lookup, etc.) were noted low-priority and left out.
<!-- SECTION:FINAL_SUMMARY:END -->
