# Jobhunt — Native Swift Rewrite Plan

> Re-implement the Jobhunt **Mac app** (currently Electron + Node) as a native Swift / SwiftUI
> application for **dual distribution: Mac App Store + GitHub DMG**. The Chrome extension is
> **out of scope** and must keep working unchanged.

---

## 0. Decisions (locked) & headline assumptions

| Decision | Choice | Consequence |
|---|---|---|
| Migration strategy | **Direct full Swift rewrite** | Backend + SwiftUI built together. No Electron-shell / WKWebView intermediate. No shippable artifact until the core loop works end-to-end (mitigated by an aggressive "thin vertical slice" first milestone). |
| Minimum macOS | **macOS 15 Sequoia** | Free use of `NavigationSplitView`, `Observation`, `SwiftData`, modern SwiftUI. **Apple Foundation Models is macOS 26+** → gated behind `if #available(macOS 26, *)`. |
| Persistence | **SwiftData** | Schema designed fresh as `@Model` types — best SwiftUI integration (`@Query` deletes the entire data-refresh/SSE layer). **No in-app importer** (no users to migrate). Existing personal data handled by a one-time *external* migrator run once on the developer's machine (§6.5) — or skip and start fresh. |
| MCP server | **Swift stdio→HTTP bridge helper, DMG build only** | The `jobhunt-mcp` executable bridges stdio JSON-RPC to the running app's **localhost HTTP server** rather than opening the SwiftData store directly. Eliminates multi-process store access (SwiftData's sharpest edge) and gives a single writer. Only works while the app is running. DMG only; MAS users don't get MCP. |

### Assumptions (stated explicitly — flag if any are wrong)
1. **The Chrome extension contract stays as-is.** The Swift app serves the exact local-server
   contract the extension depends on (§4). We *can* change `extension/` if a concrete benefit
   emerges, but none is currently planned — the contract is clean.
2. **Bundle identifier stays `com.jobhunt-app.jobhunt`** (consistent data location / scheme). With no
   existing users there's no in-place-replacement requirement; this is just for continuity.
3. **No data migration is a shipped feature.** Per your confirmation, no one else uses the app yet, so
   the app assumes an empty store on first launch. Your own legacy `jobhunt.db` is migrated once via an
   external tool (§6.5), entirely outside the app, or abandoned in favor of a fresh start.
4. **Feature parity is the target**, not a redesign. Every screen, field, and workflow is reproduced.
   Mac-native niceties are additive, not a UX rewrite.
5. **LM Studio remains the default LLM** (localhost OpenAI-compatible). All other providers
   (OpenAI, Anthropic, Google, OpenRouter, custom, Apple Foundation Models) are preserved.
6. **No cloud component.** App stays fully local-first. SwiftData store on-device; LLM keys in Keychain.
7. One developer, full-time-equivalent. Estimates in §15 scale from that.

### Known risks (detail in §16)
- SwiftData ↔ background-queue concurrency (must use `ModelActor`).
- SwiftData `#Predicate` is weaker than raw SQL for the Jobs screen's heavy dynamic filtering →
  mitigated by fetch-all + in-memory filter (matches current React behavior; datasets are small).
- Ongoing `@Model` schema evolution needs `VersionedSchema` + `MigrationPlan` discipline from v1.
- LM Studio / localhost networking under the **App Sandbox** (needs `network.client`; expected OK
  for outbound localhost, but must be tested early on a real MAS-signed build).
- Running an **HTTP listener inside a sandboxed app** (needs `network.server` + Private Network
  Access CORS header for the extension).

---

## 1. Current system — what we are replacing

Source of truth for parity. Numbers are approximate LOC.

### Backend (Node, ~7,600 LOC across `server/`)
- `api.js` (~1,900) — Express, **38 routes**. Two audiences: (a) the **extension** (5 endpoints),
  (b) the **React frontend** (the other 33: jobs CRUD, bulk ops, LLM queue, settings, resumes,
  sites, duplicates, actions, contacts, cover letters, dashboard data, export).
- `db.js` (~2,350) — `node:sqlite`, **13 tables**, WAL, FKs, ~100 query helpers, duplicate
  detection heuristics, settings defaults.
- `extract.js` (~1,550) — multi-provider LLM extraction + fit scoring, the request queue, retry/
  backoff/auto-pause, prompt building, salary/location/remote normalization, OpenRouter free-model
  rotation, cost accounting.
- `apple-foundation.js` (~125) — subprocess bridge to `native/foundation-models/foundation-models`.
- `mcp.js` (~580) — MCP server, 12 tools.
- `availability.js` (~165) — job-URL liveness checking.
- `cleaning.js` (~85), `metros.js` (~120), `rescore.js` (~75), `export.js` (~45),
  `demo.js` (~375), `sse.js` (~30), `index.js` CLI (~205).

### Frontend (React via runtime Babel, ~9,900 LOC in `static/`)
- 10 screens: **jobs** (1,196), **detail** (1,282, 8 tabs), **settings** (1,244),
  **llm_queue** (720), **sites** (547), **help** (509), **quality** (493), **dashboard** (377),
  **needs** (332), **duplicates** (271).
- Shell: `app.jsx` routing (519), `shell.jsx` sidebar/topbar (388), `main.jsx` data layer (571),
  `components.jsx` primitives/icons (589), `onboarding.jsx` 6-step wizard (576).
- Utils: `transform.js`, `sort.js`, `counts.js`, `jd-parser.js`. `styles.css` (~1,826 lines).
- Loads data once from `/api/ui-data`, refreshes on SSE `data-changed`; mutates via `window.JH_API`.

### Electron shell (`electron/main.js`, ~330)
- Boots the Express server on ports 8765–8769, loads `http://127.0.0.1:<port>` in a BrowserWindow.
- Dock badge (unread count), native notifications, `jobhunt://` deep links, global shortcut for
  DevTools, dock-bounce on queue auto-pause, `electron-updater` for DMG.
- Listens to `process.on('jobhunt:*')` events emitted by the server.

### Distribution (already built for Electron — reusable concepts)
- `package.json` `build`: dual `mac` (DMG, Developer ID, hardened runtime) + `mas` (sandboxed) targets.
- `build/entitlements.{dmg,mas,mas.inherit}.plist`.
- `.github/workflows/release.yml`: two jobs (DMG notarized+published; MAS pkg artifact) on `v*` tags.
- `scripts/notarize.cjs` (notarytool), `bump-version.sh`, `release.sh`, etc.
- Completed backlog work: DB→userData migration (task-026), sandbox entitlements (027),
  **in-app LLM consent UI required by App Store 5.1.2(i)** (028), dual-target builder (029),
  auto-update (030), CI workflow (031). Pending: Developer ID cert setup (032).

---

## 2. Target architecture

```
┌──────────────────────────────────────────────────────────────────────┐
│  Jobhunt.app  (single Swift process, SwiftUI lifecycle)               │
│                                                                        │
│  ┌───────────────┐   in-process calls    ┌──────────────────────────┐ │
│  │  SwiftUI UI    │◄────────────────────►│  AppCore (domain layer)   │ │
│  │  (10 screens,  │   @Observable stores  │  - JobService            │ │
│  │   onboarding)  │                       │  - ExtractionEngine      │ │
│  └───────────────┘                       │  - FitScorer             │ │
│         ▲                                 │  - DuplicateDetector     │ │
│         │ @Query / stores                 │  - AvailabilityChecker   │ │
│         ▼                                 │  - SettingsStore         │ │
│  ┌───────────────┐                        │  - QueueActor            │ │
│  │  SwiftData     │◄───────────────────── │  - ExportService         │ │
│  │  ModelContainer│   ModelActor          └──────────────────────────┘ │
│  └───────────────┘                                   ▲                  │
│  (empty on first launch — no in-app importer)        │                  │
│                                           ┌──────────┴───────────────┐ │
│                                           │  LocalHTTPServer (NIO)    │ │
│                                           │  extension contract +     │ │
│                                           │  MCP bridge (DMG only)    │ │
│                                           │  :8765–8769               │ │
│                                           └──────────────────────────┘ │
│                                                      ▲                   │
│  ┌──────────────────────────────────────┐           │ HTTP             │
│  │ LLMProvider adapters (URLSession)     │           │                  │
│  │  LMStudio/OpenAI/Anthropic/Google/    │   ┌───────┴────────┐         │
│  │  OpenRouter/Custom + FoundationModels │   │ Chrome extension│        │
│  └──────────────────────────────────────┘   └────────────────┘         │
└──────────────────────────────────────────────────────────────────────┘

  Separate target (DMG only): jobhunt-mcp (stdio→HTTP bridge to running app)
  One-time, off-machine:      external migrator (legacy jobhunt.db → SwiftData)
```

**Key architectural simplification vs. today:** the SwiftUI frontend calls the domain layer
**in-process** (no HTTP, no SSE, no `/api/ui-data`). SwiftData's `@Query` gives live-updating views
for free, replacing the SSE `data-changed` broadcast. The HTTP server therefore shrinks from 38
routes to the **5 extension endpoints** plus the focus/deep-link bridge.

### Layering (Swift Package targets)
- **`JobhuntCore`** — pure domain: SwiftData models, services, LLM engine, providers, parsing,
  normalization, dedup, availability, cost, demo seeding. No SwiftUI, no AppKit. **Fully unit-testable.**
- **`JobhuntServer`** — the local HTTP listener (depends on Core).
- **`JobhuntMCP`** — stdio MCP executable (depends on Core). DMG target only.
- **`Jobhunt` (app)** — SwiftUI views, app lifecycle, notifications, dock badge, deep links,
  Sparkle wiring (DMG flavor), consent UI. Depends on all of the above.
- **`FoundationModelsBridge`** — thin wrapper, compiled only with `if #available(macOS 26, *)`.

---

## 3. Technology & dependency choices

| Concern | Choice | Notes |
|---|---|---|
| Language | Swift 6 (strict concurrency) | `-strict-concurrency=complete`; Core is `Sendable`-clean. |
| UI | SwiftUI (AppKit bridges where needed) | `NavigationSplitView` 3-column. AppKit for dense table perf if needed (`NSTableView` via `NSViewRepresentable`) — see §10.3. |
| Persistence | **SwiftData** | `ModelContainer` shared; background work via `ModelActor`. |
| HTTP server | **swift-nio** (`NIOHTTP1`) | Minimal hand-rolled router for 6 endpoints. Avoids the weight of Vapor; fewer transitive deps for App Store review. (Alt: Vapor if richer routing wanted — see §16.) |
| HTTP client | `URLSession` + `Codable` | All LLM providers. Streaming not required (extraction is single-shot JSON). |
| JSON repair | port `jsonrepair` behavior | Small Swift implementation or vendored equivalent for malformed-LLM-JSON recovery (§8.4). |
| On-device LLM | `FoundationModels` framework | macOS 26+, called directly (no subprocess) — deletes `apple-foundation.js` + `main.swift` subprocess. |
| Auto-update (DMG) | **Sparkle 2** | Appcast XML published to GitHub Releases. MAS uses App Store updates. |
| PDF resume parsing | `PDFKit` | Replaces pdf.js for resume text extraction. |
| Markdown (Help) | `AttributedString(markdown:)` or `swift-markdown` | Help screen content. |
| Build/orchestration | **Xcode project generated by Tuist** | Reproducible project gen, clean target/dependency manifests, CI-friendly. (Alt: plain SPM + xcodeproj — see §5.) |
| Tests | XCTest (+ Swift Testing where convenient), `swift-snapshot-testing` for UI | Coverage gate mirrors today's 85% line / 78% branch on Core (§12). |

**Dependency budget:** keep third-party deps minimal for App Store review and supply-chain hygiene:
swift-nio, Sparkle (DMG flavor only — excluded from MAS build via compilation condition),
swift-snapshot-testing (test-only). Everything else is first-party Apple frameworks.

---

## 4. The extension contract (must not break) — §reference for §5

The only external API surface that must remain byte-compatible. From the extension source:

| Method | Path | Request | Response |
|---|---|---|---|
| GET | `/api/ping` | — | `{app:"jobhunt", version, isDemo:bool}` |
| POST | `/captures` | `{schema_version, captured_at, url, canonical_url?, page_title, selected_text?, visible_text?, structured_data?, user_note?, source}` | `{ok:true, capture_id, job_number, duplicate:bool}` |
| POST | `/site-reviews` | `{schema_version, reviewed_at, site_url, site_origin, page_title?, next_review_at?, note?}` | `{ok:true, site_review_id}` |
| GET | `/api/jobs/by-url?url=…` | query param | `{job_number}` (400 if not found) |
| POST | `/api/app/focus` | `{job_number?: number\|null}` | `{ok:true}` |

Behavioral requirements:
- **Port discovery:** listen on first free port in **8765, 8766, 8767, 8768, 8769** (try in order).
- **CORS / Private Network Access:** respond to `chrome-extension://` origin preflights with
  `Access-Control-Allow-Private-Network: true` (the current server does this; verified in tests).
- Capture validation: require `url`, `page_title`, and at least one of `visible_text`/`selected_text`.
- `/api/app/focus` must raise/focus the app window and optionally navigate to a job (deep-link bridge).

---

## 5. Project structure & build tooling

### 5.1 Repository layout (additive — Electron stays until cutover)
```
jobhunt/
  Tuist/                         # Tuist config + Project.swift
  Project.swift                  # targets: Jobhunt, JobhuntCore, JobhuntServer, JobhuntMCP, tests
  app/                           # SwiftUI app target sources
    JobhuntApp.swift
    Views/ (Jobs/, Detail/, Dashboard/, Quality/, Needs/, Sites/, Duplicates/, Queue/, Settings/, Help/, Onboarding/)
    Shell/ (Sidebar, Toolbar, Theme, Router)
    Platform/ (Notifications, DockBadge, DeepLinks, Sparkle)
    Resources/ (Assets.xcassets, app icon, Localizable)
  core/                          # JobhuntCore package sources
    Models/ (SwiftData @Model types)
    Services/ (JobService, ExtractionEngine, FitScorer, DuplicateDetector, AvailabilityChecker, ...)
    LLM/ (Providers/, PromptBuilder, Normalization, CostEstimator, Rotation)
    Migration/ (LegacySQLiteImporter)
    Demo/ (DemoSeeder)
    Util/ (Cleaning, Metros, JDParser, JSONRepair, Export)
  server/swift/                  # JobhuntServer (NIO) sources
  mcp/swift/                     # JobhuntMCP sources
  Tests/ (CoreTests, ServerTests, MCPTests, AppUITests, LLMEval)
  build/
    Jobhunt-DMG.entitlements
    Jobhunt-MAS.entitlements
    ExportOptions-DMG.plist
    ExportOptions-MAS.plist
  scripts/ (build, sign, notarize, release — rewritten for xcodebuild)
  .github/workflows/release.yml  # rewritten for Xcode
  extension/                     # UNCHANGED
  server/  static/  electron/    # legacy — removed at cutover (§17)
```

### 5.2 Build tooling
- **Tuist** generates `Jobhunt.xcodeproj` from `Project.swift` (deterministic, reviewable, no merge
  conflicts on pbxproj). Targets, deployment target (macOS 15), entitlements, signing settings, and
  the DMG-vs-MAS variant (build setting / compilation condition `MAS_BUILD`) declared there.
- Two app product flavors from one codebase:
  - **DMG flavor:** Developer ID signing, hardened runtime, Sparkle linked, MCP helper bundled,
    Foundation Models available, `network.server`/`client` via DMG entitlements.
  - **MAS flavor:** App Sandbox, no Sparkle, no MCP helper, MAS entitlements, App Store updates.
  - Selected by `xcodebuild` scheme + `MAS_BUILD` Swift compilation condition (`#if MAS_BUILD`).
- `swiftformat` + `swiftlint` in CI to mirror the current ESLint gate.
- Version bumping: keep `scripts/bump-version.sh` but have it write `MARKETING_VERSION` /
  `CURRENT_PROJECT_VERSION` (via `agvtool` or a Tuist setting) and the extension `manifest.json`
  in lockstep (extension versioning unchanged).

### 5.3 Verification for the milestone
- `tuist generate && xcodebuild -scheme Jobhunt-DMG build` succeeds.
- `xcodebuild -scheme Jobhunt-MAS build` succeeds with sandbox entitlements.
- Empty app launches, shows an empty 3-column window.

---

## 6. Data layer (SwiftData)

### 6.1 Model mapping (legacy table → `@Model`)
One `@Model` class per legacy entity. Relationships modeled with SwiftData `@Relationship`
(replacing FK integers) while **retaining the legacy integer keys as stored properties** so the
extension's `job_number`, the importer, and CSV export stay stable.

| Legacy table | `@Model` | Key fields / relationships |
|---|---|---|
| `captures` | `Capture` | url, canonicalURL, pageTitle, selectedText, visibleText, cleanedDescription, structuredDataJSON, rawHash (unique), cleanedHash, capturedAt; → `job` |
| `jobs` | `Job` | jobNumber (unique), company, title, location, remoteType, salaryMin/Max/Currency/Note, employmentType, seniority, status, extractionStatus, extractionError, extractedJSON, extractedAt, extractionModel, extractionConfidence, fitScore, fitStatus, fitScoreJSON, duplicateOfJobID, duplicateConfidence, rating, applicationURL, manualOverridesJSON, lastOpenedAt, unread; → `capture`, `events[]`, `actions[]`, `contacts[]`, `coverLetters[]`, `fitScores[]` |
| `events` | `JobEvent` | eventType, note, occurredAt; → `job` |
| `site_reviews` | `SiteReview` | siteURL, siteOrigin, pageTitle, reviewedAt, nextReviewAt, note |
| `duplicate_decisions` | `DuplicateDecision` | cleanedHash (unique), decision, keepJobID, note, decidedAt |
| `settings` | `Setting` | key (unique), value, updatedAt (or fold into a typed `SettingsStore`, §6.3) |
| `job_actions` | `JobAction` | note, dueDate, completedAt, snoozedUntil; → `job` |
| `data_quality_reviews` | `DataQualityReview` | reviewedAt, note; → `job` (unique) |
| `sites` | `Site` | origin (unique), url, companyName, companyWebsite, jobsURL, companyDescription, pageTitle, intervalDays, lastReviewedAt, nextReviewAt, note, state |
| `resumes` | `Resume` | name, filename, text, charCount, active, sortOrder, createdAt; → `fitScores[]` |
| `job_fit_scores` | `JobFitScore` | fitScore, fitStatus, fitScoreJSON, model, scoredAt; → `job`, `resume` |
| `llm_requests` | `LLMRequest` | requestType, status, attempt, model, error, createdAt, startedAt, finishedAt; → `job`, `resume?` |
| `llm_request_attempts` | `LLMRequestAttempt` | attempt, status, modelRequested/Returned, responseFormat, baseURL, durations, error, responsePreview, promptChars, responseChars; → `request`, `job` |
| `contacts` | `Contact` | name, role, email, linkedinURL, phone, notes, createdAt; → `job` |
| `cover_letters` | `CoverLetter` | content, instructions, model, createdAt; → `job` |

Indexing: use `#Index` / `#Unique` macros (SwiftData) for `jobNumber`, `rawHash`, `cleanedHash`,
`origin`, and the `(status, createdAt)` query pattern on `LLMRequest`.

### 6.2 Concurrency model (critical)
- One app-wide `ModelContainer`.
- UI reads via `@Query` and a main-actor `ModelContext`.
- **All background work** (extraction queue, availability checks, importer, demo seeding, bulk ops)
  runs in a dedicated **`@ModelActor`** (e.g. `BackgroundStore`) with its own context, then UI
  updates flow back automatically through SwiftData change tracking. This replaces today's SSE.
- Bulk mutations batch + `try context.save()` once per batch.

### 6.3 Settings
~30 keyed settings today. Provide a typed `SettingsStore` (`@Observable`) backed by a single
`Setting` table (or `UserDefaults` for non-sensitive prefs + Keychain for API keys — **API keys go
in Keychain**, not SwiftData, for App Store hygiene). Defaults centralized to mirror `SETTINGS_DEFAULTS`.

### 6.4 Schema evolution
Define `SchemaV1` (`VersionedSchema`) and a `MigrationPlan` from day one so future `@Model` changes
are migratable. The importer (below) targets `SchemaV1`.

### 6.5 One-time external migrator (NOT shipped in the app)
No users exist, so the app does **not** include an importer and assumes an empty store on first
launch. To preserve the developer's own existing data, build a **standalone command-line tool**
(its own small SPM executable, or a throwaway script) that runs **once on the dev machine**:
- Reads the legacy `~/Library/Application Support/Jobhunt/jobhunt.db` via the **C `SQLite3`** API.
- Writes directly into a SwiftData store file (reusing `JobhuntCore`'s `@Model` types + container),
  preserving `jobNumber`, hashes, timestamps, and JSON blobs verbatim.
- Output store is then dropped into the app's data location.

This keeps all migration complexity out of the shipped product (no sandbox open-panel, no
security-scoped bookmarks, no first-launch import flow). **Alternative:** skip the migrator entirely
and start fresh if the existing captured jobs aren't worth keeping.

**Verification:** run the migrator on a copy of the real DB; row counts per entity match; launch the
app against the produced store; jobs render; extension capture still links the right `job_number`.

---

## 7. Local HTTP server (extension bridge only)

- `JobhuntServer` target using swift-nio `NIOHTTP1`.
- Bind `127.0.0.1`, try ports 8765→8769, expose chosen port to the app.
- Hand-rolled tiny router for the 6 endpoints in §4 + `/health` + `/api/events` no longer needed
  (SSE dropped — UI is in-process). Keep `/api/events` returning a harmless 204 only if any extension
  build polls it (it does not — verified; can omit).
- CORS middleware: handle `OPTIONS` preflight, echo `chrome-extension://…` origin, set
  `Access-Control-Allow-Private-Network: true`, allow `Content-Type`.
- Handlers call `JobService` (capture ingestion → dedup → job creation → enqueue extraction),
  `SiteService`, and a `WindowFocusBridge` (posts a notification the app observes to focus/navigate).
- Lifecycle: start on app launch after the store is ready; graceful shutdown on terminate.
- **Entitlements:** `com.apple.security.network.server` (both flavors) — already in MAS plist today.
- **MCP bridge endpoints (DMG only):** add a small set of localhost-only JSON endpoints the
  `jobhunt-mcp` helper calls (list/get/update jobs, sites CRUD, notes, rerun extraction, workflow
  snapshot — the 12 MCP tools mapped to HTTP). Bound to `127.0.0.1`, gated by a per-launch token so
  only the bundled helper can call them. This is how MCP avoids touching the SwiftData store directly
  (§11). Compiled out of the MAS build (`#if !MAS_BUILD`).

**Tests:** spin the listener on an ephemeral port, POST a fixture capture, assert a `Job` is created
with the right `job_number` and dedup behavior; assert `/api/ping` shape; assert CORS headers.

---

## 8. LLM extraction engine (port of `extract.js`)

This is the most logic-dense backend area. Reproduce behavior exactly; restructure for Swift.

### 8.1 Provider abstraction
```
protocol LLMProvider {
  func complete(_ req: ChatRequest) async throws -> ChatResponse
  var concurrencyLimit: Int { get }
}
```
Adapters: `LMStudioProvider` (OpenAI-compatible localhost), `OpenAIProvider`, `AnthropicProvider`
(native Messages API), `GoogleProvider` (`generateContent` + JSON mode), `OpenRouterProvider`
(+ free-model rotation), `CustomOpenAIProvider`, `FoundationModelsProvider` (macOS 26+, in-process).
Selection driven by `SettingsStore.llmProvider`. Concurrency limits per provider preserved
(openai/google/openrouter 3, anthropic 2, apple 1, others 2) via per-provider `Semaphore`/`actor`.

### 8.2 Response-format negotiation
Mirror today's ladder: **JSON schema (strict)** → `json_object` → prompt-only, falling back on
provider rejection. Anthropic/Google have bespoke JSON paths. Record `response_format` per attempt.

### 8.3 Prompt building
Port `PromptBuilder`: system + user prompts for extraction (job description + location prefs +
optional resume summary) and fit scoring (5-dimension rubric). Preserve `MAX_DESCRIPTION_CHARS`
(32k), `MAX_RESUME_CHARS` (12k), overhead budgeting, and the recommended-min-context check.

### 8.4 Parsing & normalization
- Strip markdown fences, extract JSON, **repair malformed JSON** (port `jsonrepair` essentials).
- Salary mining (bands, hourly→annual, currency detection), remote-type inference (URL params for
  LinkedIn/Indeed/Levels + description heuristics), location inference, company backfill from
  structured data. These are well-specified pure functions → straightforward, heavily unit-tested.

### 8.5 Fit scoring (`FitScorer`)
Weighted 5-dimension score (required 45%, preferred 5%, skills 15%, experience 20%, domain 15%),
penalty model (−5/missing requirement, −10/domain-gap keyword, cap −50), `max(0, weighted−penalty)`.
Port `rescore.js` as a pure recompute path (no LLM) for weight changes. Per-(job,resume) scores in
`JobFitScore`; `Job.fitScore` reflects active resume(s).

### 8.6 The queue (`QueueActor`)
- Persistent queue in `LLMRequest`; states queued→running→succeeded/failed.
- Concurrency per provider; exponential backoff on 429 + rotation-pool pause.
- **Auto-pause after 2 consecutive failures** → post `queueAutoPaused` (drives dock bounce + notif).
- Attempt history into `LLMRequestAttempt` (model requested/returned, durations, response preview,
  prompt/response chars for cost).
- Emits domain events the app layer observes: `jobReady`, `jobUnavailable`,
  `aiProcessingComplete`, `queueAutoPaused` (replaces `process.emit('jobhunt:*')`).

### 8.7 Cost & pricing
Port `/api/llm-cost` estimation (chars/4 token estimate over all jobs + active resumes) and
`/api/llm-pricing` (live OpenRouter pricing fetch). Surface in Settings → Debug as today.

### 8.8 Foundation Models (macOS 26+)
Replace the subprocess entirely. `FoundationModelsProvider` calls
`LanguageModelSession(instructions:).respond(to:)` directly inside `#if available`. Availability
check gates the provider in Settings/Onboarding. **Deletes** `native/foundation-models/` and
`apple-foundation.js`.

**Tests:** golden-file extraction tests using recorded provider responses (mirrors the current
`apple-foundation.test.js` + extraction unit tests); a live `eval:llm` equivalent (§12.4).

---

## 9. Supporting services (ports)
- **DuplicateDetector** — hash-based (cleaned-description hash) + heuristic (Jaccard company match,
  description similarity, field-conflict scoring). Produces duplicate groups + confidence. Pure → unit tests.
- **AvailabilityChecker** — fetch job URLs, detect 404/410 + "no longer available" body patterns +
  bad redirects; stale-check scheduler (default 21d, ≤25/run). Emits `jobUnavailable`.
- **Cleaning** — selected→visible text preference, JSON-LD JobPosting extraction, HTML strip/entity
  decode, Workday salary-band splitting.
- **Metros** — port the hardcoded metro/city tables + `parsePreferredMetros`/`expandMetros`.
- **Export** — `jobsCsv()` (19 columns) → `GET /exports/jobs.csv` replaced by a **Save panel** /
  share in the SwiftUI UI; keep CSV column parity.
- **DemoSeeder** — port `demo.js` seed/reseed to a separate in-memory/file SwiftData store; demo mode
  toggle in UI (replaces `/api/db/switch`).

---

## 10. SwiftUI frontend (the 10 screens + shell + onboarding)

### 10.1 App shell & navigation (replaces `app.jsx` + `shell.jsx`)
- `NavigationSplitView`: **sidebar** (sections + status quick-filters + saved views + footer status
  dots + theme toggle + demo banner) | **content** (active screen) | **detail** (job/site inspector).
- A `Router` `@Observable` holding selected section, selected job/site, active saved view — backed by
  `SceneStorage` for restore-on-launch (replaces localStorage + hash routing).
- Deep links: register `jobhunt://` URL scheme in Info.plist; `onOpenURL` → route to `jobhunt://jobs/42`.
- Live data via `@Query` (no manual refresh; SwiftData change tracking replaces SSE).

### 10.2 Screens (parity checklist — each is a milestone-tracked deliverable)
1. **Dashboard** — top opportunities cards, pipeline funnel (clickable), 30-day activity bar chart
   (Swift Charts), site check-in schedule, quality summary, stat cards.
2. **Jobs** — the hardest screen. Dense, sortable, multi-filter table; 18 configurable columns;
   16 sort keys; fixed + dynamic filters; saved views; batch selection (shift-click ranges) + bulk
   ops (status, queue AI, open sources, compare); search with `#number` mode; `⌘K` focus.
3. **Job Detail** (inspector) — 8 tabs: Details (inline-editable fields, status, ⭐ rating,
   extraction-quality badge), Extracted data, Fit score (dimensions breakdown), Summary,
   Requirements, Timeline (events), Raw (JD-parsed blocks via `JDParser`), Compare (when duplicate).
   Inline edit, follow-up actions (create/snooze/complete), arrow-key prev/next, `esc` close.
4. **Data Quality** — issue-grouped lists, severity coloring, site-health metrics, batch review /
   re-extract / open-sources; `qualityIssuesForJob` rules ported.
5. **Needs Action** — actions grouped Overdue/Today/Upcoming; filters; snooze/complete; search.
6. **Sites** — table + detail inspector; review state machine (not_reviewed/reviewed/exclude);
   interval scheduling; add-site flow; mark-reviewed.
7. **Duplicates** — pair list, similarity, side-by-side compare, unmark/delete decisions.
8. **LLM Queue** — request table (type/status/model/duration/error), expandable attempt history,
   batch process/cancel/reset, global pause toggle, manual run.
9. **Settings** — tabs: Settings (provider picker + per-provider config + model fetch + test;
   location filter + toggles; intervals), Resumes (CRUD, active, PDF/text import via PDFKit),
   Debug (LLM debug log, cost pricing inputs, OpenRouter rotation, availability auto-check).
   **Includes the LLM consent gate** (§13.3).
10. **Help** — sectioned reference rendered from Markdown; keyboard-shortcuts table; About (version,
    local-data note, privacy).

### 10.3 Performance note for Jobs table
SwiftUI `Table` handles hundreds of rows fine for typical users (100–1,000 jobs). If profiling shows
jank with large datasets + many columns, wrap an `NSTableView` via `NSViewRepresentable` for the Jobs
list only. Decide by measurement, not upfront (matches "simplicity first").

### 10.4 Design system (replaces `styles.css`, ~1,800 lines)
- Token set (colors, spacing 4px scale, radii, shadows) as a Swift `Theme` `@Observable`.
- Status palette (saved/applied/interview/offer/rejected/archived/not_available/duplicate) → SF
  Symbol + color mapping. Indigo accent (#5E6AD2) preserved.
- Light/Dark/Auto via `preferredColorScheme` + a theme toggle (parity with current).
- Reusable components: `StatusChip`, `ExtractionChip`, `CompanyCell`/`CoLogo`, `StarRating`,
  `Chip`, toolbar/popover filter controls, consent modal, toast/inline-status. SF Symbols replace
  the 30 inline SVG icons.

### 10.5 Platform integration (replaces `electron/main.js`)
- **Dock badge** = unread count (`NSApp.dockTile.badgeLabel`), recomputed on relevant changes.
- **Notifications** via `UserNotifications` (`UNUserNotificationCenter`): job-ready (high-fit emphasis),
  job-unavailable, ai-processing-errors, queue-auto-paused (critical → dock bounce via
  `NSApp.requestUserAttention(.criticalRequest)`). Click → focus + navigate (parity with current
  `showMacNotification` logic, including the "don't flood on big batches" rule).
- **Deep links** + `/api/app/focus` bridge → focus window, select job.
- Menu bar commands, `⌘`-shortcuts, window restoration.

---

## 11. MCP server (`jobhunt-mcp`, DMG only) — stdio→HTTP bridge
- New Swift executable target implementing MCP over stdio (JSON-RPC framing; implement the small
  stdio protocol directly, or use a vetted community package).
- **Does NOT open the SwiftData store.** Instead it translates each MCP tool call into a request to
  the **running app's localhost HTTP server** (§7 MCP-bridge endpoints), authenticating with the
  per-launch token. This sidesteps SwiftData multi-process access entirely and keeps a single writer
  (the app). Consequence: **MCP works only while the Jobhunt app is running** — acceptable, and
  arguably safer than two processes racing on one store.
- Port the **12 tools**: jobs_list, job_get, add_capture, update_job, set_job_status, add_job_note,
  rerun_extraction, list_sites, add_site, update_site, delete_site, workflow_snapshot — each maps to
  one bridge endpoint.
- Discovery: the helper finds the app's port the same way the extension does (probe 8765–8769 +
  `/api/ping`), reads the auth token from a known per-user location the app writes on launch.
- Bundle the binary in the DMG `.app` (e.g. `Contents/Helpers/jobhunt-mcp`); document the
  `claude mcp add` path. **Excluded from MAS build** (`#if !MAS_BUILD`).
- **Tests:** drive the executable with scripted stdio JSON against a stub HTTP server, assert tool
  results (mirrors `tests/integration/mcp.test.js`); plus an end-to-end test against the real app server.

---

## 12. Testing strategy

Mirror the current discipline (459 tests, 85% line / 78% branch gate) — concentrated on `JobhuntCore`.

### 12.1 Unit (XCTest / Swift Testing) — the bulk
Port every `tests/unit/*` to Swift, one-to-one where possible:
- cleaning, transform-equivalents, sort, counts, jd-parser, availability, extraction normalization,
  salary/remote inference, rotation, fit-score math, CSV export, metros, jsonrepair.
- SwiftData model tests (relationships, uniqueness, cascade).

### 12.2 Integration
- **Store + services** (port `db.test.js`, `resumes.test.js`, `cost.test.js`, `concurrency.test.js`):
  spin an in-memory `ModelContainer`, exercise services.
- **HTTP server** (port `api.test.js` extension-relevant parts): ephemeral listener, capture POST,
  ping, CORS/PNA header, by-url, focus bridge.
- **MCP** (port `mcp.test.js`): stdio driver.
- **Importer**: legacy-DB fixture → import → assertions.

### 12.3 UI tests
- XCUITest smoke for each screen (launch, navigate, basic interaction) — replaces the Playwright
  `jobs-smoke` + electron smoke tests.
- `swift-snapshot-testing` for key components/screens in light + dark (catches design regressions).

### 12.4 LLM eval harness
Port `eval:llm` — run real extraction against fixture JDs (e.g. the Pinterest reference), score field
accuracy. Manual/CI-optional (requires LM Studio or a key), like today.

### 12.5 Coverage gate
- `xcodebuild test -enableCodeCoverage YES` + `xccov`; CI fails under thresholds on `JobhuntCore`.
- Keep a `tests/` parity matrix doc mapping each old test → its Swift replacement (don't lose coverage).

---

## 13. Distribution: Mac App Store + GitHub DMG

### 13.1 Two flavors, one codebase
- **DMG (Developer ID):** hardened runtime, sandbox **off**, Sparkle on, MCP helper + Foundation
  Models on, notarized, published to GitHub Releases.
- **MAS:** App Sandbox **on**, no Sparkle, no MCP, App Store update path.
- Differentiate with the `MAS_BUILD` compilation condition + per-scheme entitlements/signing.

### 13.2 Entitlements (port the existing plists)
- **DMG** (`Jobhunt-DMG.entitlements`): hardened runtime; no sandbox. (No JIT/library-validation
  hacks needed — those were Electron-specific; native Swift doesn't need `allow-jit` /
  `disable-library-validation`. **Simplification.**)
- **MAS** (`Jobhunt-MAS.entitlements`):
  - `com.apple.security.app-sandbox` = true
  - `com.apple.security.network.server` = true (extension HTTP listener)
  - `com.apple.security.network.client` = true (LLM providers incl. localhost LM Studio)
  - `com.apple.security.files.user-selected.read-only` = true (resume/legacy-DB import via open panel)
  - **No** child-process inherit plist (single-process app — simpler than Electron).
- Validate with `plutil -lint` in CI.

### 13.3 App Store policy compliance (carry forward task-028)
- **LLM consent UI is mandatory** (Guideline 5.1.2(i)): before any **cloud** provider call, show a
  per-provider consent sheet disclosing what data (job text, resume) goes where, with a privacy-policy
  link; persist `llm_consent_<provider>`; **localhost providers (LM Studio, Foundation Models) bypass
  consent**. Port `LlmConsentModal` to SwiftUI; gate extraction in `QueueActor`.
- Privacy nutrition label / `PrivacyInfo.xcprivacy` manifest declaring no data collection (local-first).
- App Sandbox + no private APIs (Foundation Models is public on 26+; gate cleanly).

### 13.4 Auto-update (DMG)
- Adopt **Sparkle 2** from v1 with an EdDSA-signed appcast published to GitHub Releases.
- **No bridge release needed** — there are no existing `electron-updater` users to carry over. The
  first Swift DMG is simply a fresh download; Sparkle handles every update after that.
- MAS users update through the App Store automatically.

### 13.5 Signing & certificates (reuse task-031/032 secrets)
- DMG: **Developer ID Application** cert; `codesign` + `xcrun notarytool` + `stapler`.
- MAS: **3rd Party Mac Developer Application** + **Installer** certs; `productbuild`/Xcode export →
  `.pkg`; upload via `xcrun altool`/Transporter or App Store Connect API key.
- Same GitHub secrets already documented in the current workflow carry over.

### 13.6 CI/CD (rewrite `.github/workflows/release.yml`)
On `v*` tag, `macos-latest`:
- **Job build-dmg:** `tuist generate` → `xcodebuild -scheme Jobhunt-DMG archive` →
  export Developer ID → notarize → staple → build DMG → generate + EdDSA-sign appcast →
  publish DMG + `appcast.xml` to the GitHub Release.
- **Job build-mas:** `xcodebuild -scheme Jobhunt-MAS archive` → export `.pkg` →
  (optional) auto-upload to App Store Connect via API key, else upload artifact for manual Transporter.
- Reuse `bump-version.sh` (now writing Xcode version settings + extension manifest).
- Run `xcodebuild test` + coverage gate as a required pre-release check.

### 13.7 Distribution verification
- Install notarized DMG on a clean machine → Gatekeeper passes (no `xattr` workaround needed).
- Install MAS build via TestFlight/App Store Connect → sandbox runs, extension captures work,
  LM Studio reachable, cloud provider consent enforced.
- Sparkle update from vN→vN+1 succeeds on DMG.

---

## 14. Upgrade path
- **No users → no in-app upgrade/migration path.** The app ships assuming an empty store.
- Developer's own data: migrate once via the external tool in §6.5 (or start fresh).
- The extension keeps working across the swap from Electron→Swift automatically (same ports, same
  contract); nothing to migrate there.

---

## 15. Work breakdown & milestones (with verification)

Sequenced for a **direct full rewrite**, but front-loaded so a usable internal build exists early.
Estimates assume one FTE; ranges reflect Jobs/Detail being the long poles.

**M0 — Foundations (1 wk)**
- Tuist project, 4 targets, macOS 15 target, both entitlement sets, CI skeleton (build only).
- Verify: both schemes build; empty app launches.

**M1 — Data layer (1–1.5 wks)**
- All `@Model` types, `SchemaV1` + `MigrationPlan`, `ModelContainer`, `BackgroundStore` ModelActor,
  `SettingsStore` (+ Keychain for keys). Standalone external migrator (§6.5) as a side deliverable.
- Verify: `@Query` lists seeded jobs in a debug view; external migrator round-trips the real DB.

**M2 — Extension bridge + capture pipeline (1–1.5 wks)**
- NIO HTTP server (extension endpoints + CORS/PNA + MCP-bridge endpoints behind `#if !MAS_BUILD`),
  `JobService` capture→dedup→job create→enqueue, `SiteService`, window-focus bridge.
- Verify: real Chrome extension captures into the new app; by-url + focus work; dedup correct.
  **(First dogfoodable slice: capture → stored job.)**

**M3 — LLM engine (2.5–3 wks)**
- Provider adapters, format negotiation, prompt builder, normalization, JSON repair, `FitScorer`,
  `QueueActor` (concurrency/backoff/auto-pause/attempts), cost + pricing, Foundation Models provider.
- Verify: extraction + fit scoring produce parity results vs. Node on fixture JDs; `eval:llm` passes;
  unit coverage ≥ thresholds for engine.

**M4 — Supporting services (1 wk)**
- DuplicateDetector, AvailabilityChecker, Cleaning, Metros, Export, DemoSeeder.
- Verify: ported unit tests green; duplicates/availability behave as Node.

**M5 — SwiftUI shell + Jobs + Detail (3–4 wks)**
- NavigationSplitView shell, router, theme/design system, sidebar, notifications, dock badge,
  deep links; **Jobs** table (filters/sort/columns/saved views/batch) + **Detail** (8 tabs, inline
  edit, actions).
- Verify: full capture→extract→review→status loop usable; snapshot + XCUITest smoke pass.
  **(Internal daily-driver build.)**

**M6 — Remaining screens (3–4 wks)**
- Dashboard, Data Quality, Needs Action, Sites, Duplicates, LLM Queue, Settings (+ consent gate +
  resume import), Help, **Onboarding** wizard.
- Verify: per-screen parity checklist (§10.2) signed off; XCUITest per screen.

**M7 — MCP helper (0.5–1 wk)**
- `jobhunt-mcp` stdio executable, 12 tools, DMG bundling.
- Verify: `claude mcp add` works; mcp integration tests pass.

**M8 — Distribution hardening (1.5–2 wks)**
- DMG notarization + Sparkle appcast; MAS sandbox build + `.pkg` + consent compliance +
  `PrivacyInfo.xcprivacy`; CI release workflow; Developer ID + MAS certs. MAS `.pkg` uploaded manually
  via Transporter (no CI auto-upload, per decision).
- Verify: clean-machine DMG passes Gatekeeper; Sparkle update vN→vN+1 works; MAS build approved in
  App Store Connect (TestFlight first); localhost networking (LM Studio + extension listener)
  confirmed on a real signed MAS build.

**M9 — Cutover & cleanup (0.5 wk)**
- Remove `electron/`, `server/`, `static/`; update README/CONTRIBUTING; archive Electron release path.
- Verify: repo builds Swift-only; docs accurate; first public Swift DMG + MAS submission shipped.

**Rough total: ~16–22 weeks (4–5.5 months) FTE.** Jobs/Detail (M5) and the LLM engine (M3) dominate.

---

## 16. Risks, open questions, alternatives

1. **SwiftData maturity / concurrency.** Mitigation: strict `ModelActor` usage; in-memory containers
   in tests; fetch-all + in-memory filtering for the dense Jobs screen (matches current behavior).
   Fallback if SwiftData proves limiting: **GRDB** — cheap to pivot since `JobhuntCore` is isolated.
   *Resolved direction: SwiftData confirmed; the main reason to prefer GRDB (zero-migration schema
   reuse) no longer applies given no users.*
2. **MCP multi-process writes — RESOLVED.** `jobhunt-mcp` bridges to the running app's localhost HTTP
   server (§11) instead of opening the store, so there is never a second process on the SwiftData
   store. Tradeoff accepted: MCP requires the app to be running.
3. **Localhost networking under sandbox** (both LM Studio client and the extension server) — allowed
   by entitlements but must be validated on a real signed MAS build **early** (M2 spike + M8), not at
   the end. This is now the top *unverified* technical risk.
4. **App Store review** of a local HTTP server + on-device "AI" — keep the privacy manifest honest,
   consent UI airtight, no private APIs. Foundation Models gating must be clean (`#available` 26+).
5. **swift-nio vs Vapor** — nio chosen for a small route surface + minimal deps; revisit only if the
   server grows.
6. **Migration risk — RESOLVED/REMOVED.** No users → no in-app importer, no sandbox open-panel, no
   Sparkle bridge release. Personal data handled once by an external tool (§6.5).

### Resolved decisions
- **MAS upload:** manual via Transporter; **no** CI auto-upload to App Store Connect for now (§13.6).
- **`jobhunt://` scheme:** kept unchanged. Extension contract unchanged; we'll only touch the
  extension if a concrete benefit appears.

---

## 17. What gets deleted at cutover (M9)
`electron/`, `server/` (Node), `static/` (React), `native/foundation-models/` (subprocess),
`scripts/*electron*`, `notarize.cjs` (replaced by notarytool calls), Electron-specific `package.json`
build config and deps. **Kept:** `extension/` (unchanged), `marketing/`, `chromestore/`, `.backlog/`,
test fixtures (reused), `bump-version.sh` (adapted).

---

## 18. Agent kickoff order & parallelization guide

This section is written for an AI coding agent (Claude Code / sub-agents) executing the Backlog
tasks in the "Native Swift Rewrite" milestone (task-033 – task-064). Follow this sequencing to
avoid conflicts and maximize wall-clock parallelism.

### Phase 0 — Read before doing anything
1. Read this file (`swift-plan.md`) end-to-end.
2. Call the `backlog` MCP: `get_backlog_instructions` for "task-execution" and "task-finalization".
3. `task_list` the milestone, then `task_view` task-033, 034, 035 to confirm understanding.

### Phase 1 — Foundation (serial, do yourself in main checkout)
These three tasks share the Tuist manifest, the SwiftData schema, and the settings layer.
**No sub-agents until all three are green.**

| Task | What | Blocks |
|------|------|--------|
| task-033 | Tuist scaffold, targets, entitlements | Everything |
| task-034 | SwiftData models (`Job`, `Site`, `Note`, …) | All services, screens |
| task-035 | `SettingsStore`, Keychain, `ModelActor` | All LLM + extraction work |

After each: run `tuist generate && xcodebuild -scheme Jobhunt-DMG build` + test suite. Check in
with the user before starting Phase 2.

### Phase 2 — Core layer (fan out in parallel, isolated worktrees)
Once 033–035 are merged to local `main`, spawn one sub-agent per card. None of these touch the
Tuist manifest or the model definitions simultaneously.

```
036  Utils / extensions
037  Job normalization
038  Deduplication engine
039  FitScorer
040  Demo / fixture data
041  Apple Intelligence availability helpers
042  LLM provider adapters (OpenAI-compat, Anthropic, Foundation Models)
043  External data migrator (standalone tool, not in-app)
```

### Phase 3 — Extraction + services (serial then parallel)
| Step | Tasks | Note |
|------|-------|------|
| 3a | task-044 (ExtractionEngine + Queue) | Depends on 042 being done |
| 3b | task-046 (JobService, SiteService, Export) | Depends on 044 |

After 3b is green: fan out task-047 (HTTP server) and task-045 (App shell + design system) in
parallel — they don't share files.

### Phase 4 — Screens (fan out after task-045 + task-046 are merged)
task-045 defines the shared design system components; nothing should render without it.

```
048  Jobs list screen
049  Job detail screen
050  Add/edit job sheet
051  Notes tab
052  Status pipeline (Kanban / column view)
053  Search + filter
054  Export sheet
055  Capture review sheet
056  Settings screen
057  Help / onboarding overlay
061  Onboarding flow (first-launch)
```

### Phase 5 — Integration & ship (serial)
Run these yourself; they cross-cut everything and touch CI/distribution config.

```
059  MCP server bridge
060  Platform integration (Sparkle, Spotlight, Share, Shortcuts)
058  Eval harness (LLM quality regression)
062  DMG distribution (Developer ID, Sparkle, notarytool)
063  MAS distribution (sandbox, privacy manifest, App Store Connect)
064  Cutover — delete Electron/Node/React, update docs
```

### Critical path to dogfoodable build
```
033 → 034 → 035 → 042 → 044 → 046 → 047   ← extension capture works end-to-end
                                    ↓
                              045 → 048/049  ← usable UI
```
Prioritize this path. Everything else is important but not blocking day-to-day use.

### Sub-agent contract
Each sub-agent receives:
- The task id and an instruction to `task_view` it.
- The specific `swift-plan.md` sections listed on the card.
- The legacy JS/JSX files listed on the card (behavior spec).
- The acceptance criteria as its definition of done.
- Instruction to mark the card In Progress on start, Done when criteria are met.
- Instruction to commit on its worktree branch then rebase onto local `main` (`bc-commit` skill).

Two agents must **never** edit `Project.swift` (Tuist manifest) or `Models.swift` simultaneously.

### Top risk to validate early
**Localhost networking under App Sandbox** — both the extension inbound listener (task-047) and
LM Studio / cloud LLM outbound (task-042). Spike this during M2 on a real signed MAS build; see
§16 risk #3. Do not leave it until the distribution cards.

---

### Appendix A — Parity index (build into a tracking doc)
A living checklist mapping: every legacy table → `@Model`; every extension endpoint → handler;
every `extract.js` behavior → Swift function; every screen → SwiftUI view; every old test → Swift
test. Don't mark a milestone done until its slice of this index is green.
