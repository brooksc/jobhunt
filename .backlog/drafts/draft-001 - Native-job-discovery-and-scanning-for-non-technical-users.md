---
id: DRAFT-001
title: Native job discovery and scanning for non-technical users
status: Draft
assignee: []
created_date: '2026-07-22 21:04'
labels:
  - parked
  - on-hold
  - product-direction
  - discovery
  - native-macos
dependencies: []
documentation:
  - /Users/brooksc/git/career-ops/ARCHITECTURE.md
  - /Users/brooksc/git/career-ops/DATA_CONTRACT.md
  - /Users/brooksc/git/career-ops/docs/SUPPORTED_JOB_BOARDS.md
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Parked product direction. Make job discovery a first-class native JobHunt capability so a non-technical user can configure what they are looking for, run or schedule scans, and receive matching roles directly in the New funnel without installing Node, using a terminal, editing YAML or Markdown, operating CareerOps, or understanding provider-specific ATS APIs. CareerOps at /Users/brooksc/git/career-ops is the current reference implementation and is MIT-licensed; it demonstrates the required provider, filtering, deduplication, trust, liveness, scan-history, and portal-health behavior. Revisit whether to selectively port its highest-value providers into Swift, consume a bundled service behind a fully native UI, or define another implementation that preserves a simple installation and support model. Avoid attempting full provider parity before measuring which sources users actually need.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A non-technical user can enable discovery and define target titles, locations, remote preferences, companies or sources, and basic exclusions entirely through JobHunt UI.
- [ ] #2 The default setup requires no terminal commands, source checkout, Node installation, YAML or Markdown editing, API knowledge, or separate application.
- [ ] #3 Users can run a scan on demand and optionally schedule recurring scans with clear last-run, next-run, progress, cancellation, and failure states.
- [ ] #4 Discovered roles enter the New funnel with posting URL, company, title, location, posting date, source, and discovery timestamp when available.
- [ ] #5 Repeated scans are idempotent and reuse JobHunt URL and duplicate-resolution policy without collapsing unrelated postings.
- [ ] #6 The feature distinguishes discovered roles from browser captures and records scan provenance without creating competing sources of truth.
- [ ] #7 Extraction and fit analysis are rate-limited or explicitly controlled so a large scan cannot unexpectedly consume excessive LLM capacity or cost.
- [ ] #8 Closed, stale, malformed, untrusted, and unreachable postings are handled visibly, with retry and source-health information where appropriate.
- [ ] #9 The user can review why a role matched and adjust filters without learning provider-specific configuration.
- [ ] #10 Credentials are not required for public sources; any future authenticated source is opt-in and stores secrets using platform security facilities.
- [ ] #11 Provider networking is bounded by timeouts, rate limits, host validation, and safe redirect handling.
- [ ] #12 The initial provider set is chosen from measured user needs, and broader CareerOps parity is explicitly outside the first release.
- [ ] #13 Focused tests cover provider contracts, filtering, normalization, duplicate handling, scheduling, cancellation, partial failures, and migration of discovery metadata.
- [ ] #14 The implementation retains required CareerOps MIT attribution for any substantially reused or ported code.
<!-- AC:END -->

## Implementation note — prefer public ATS APIs over web scraping (2026-07-22)

Strongly prefer the **public, no-credential ATS job-board APIs** as the provider layer instead of
scraping career-site HTML. We already validated this for availability in **TASK-631**: Greenhouse's
Job Board API (`boards-api.greenhouse.io/v1/boards/{board}/jobs[/{id}]`, no key) returns clean JSON —
full description `content`, `title`, `location`, `departments`, `updated_at`, and (with
`?questions=true`) the application form — and the board list endpoint returns **every open role for a
company**, which is exactly the discovery primitive this card needs. This sidesteps the Cloudflare /
JS-shell fragility that plagues scraping (the whole #122/#325 false-positive class).

The same pattern generalizes to the other ATSes we already detect posting ids for — **Lever**
(`api.lever.co/v0/postings/{company}`), **Ashby**, and **Workday** (CXS) — via the provider
abstraction proposed in **TASK-636**. Discovery should be built on that abstraction:
- Primary sources = ATS board APIs (Greenhouse/Lever/Ashby/Workday), keyed by company/board slug.
- Reuse: **TASK-631** (board-token derivation + liveness), **TASK-632** (canonical content),
  **TASK-634** (per-company role listing — the single-company precursor to full discovery),
  **TASK-635** (application-form preview).
- Fall back to scraping / CareerOps providers only for sources without a usable public API.

Net: much of "scan for matching roles and drop them in New" can be **API-driven**, not scraped —
cheaper, cleaner, and far more reliable.
