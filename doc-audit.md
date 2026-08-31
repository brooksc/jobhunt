# TASK-696 — Documentation audit (read-only proposal)

Audited 2026-08-31 against `main` @ `89e7bc79`. **No files were changed.** No build was run; anything requiring a build or a running app is flagged inline as `[UNVERIFIED]`.

Cutover commit for reference throughout: **`a6f41a2a` "Implement TASK-064: Remove legacy Electron/Node/React stack"** (2026-06-07). This is the commit whose *parent* still contains `electron/`, `static/`, `native/`, `package.json`. Several proposed rewrites below cite it, because a comment that names a deleted file is only useful if it also names the commit where that file can still be read.

---

# Part 0 — Top three recommendations

1. **Fix `CLAUDE.md`'s four factual errors and three incomplete lists (§3.1).** It is loaded into every agent session, so each error propagates into every future session's assumptions. Highest value per line changed in the whole audit.
2. **Delete `dist/` from the working tree and fix the `.gitignore` comment that names it "Electron build output" (§4.3).** `dist/` still holds `Jobhunt-0.2.0.dmg.blockmap`, `latest-mac.yml` (the electron-updater feed) and `builder-effective-config.yaml`. It is untracked and ignored, so no audit or CI sees it — this is the last physical Electron artifact in the repo.
3. **Archive `swift-plan.md` to `docs/archive/` rather than deleting it, but first lift §4 (`:167–186`) out into a live `docs/extension-contract.md` (§3.2).** That section is a normative contract with a *currently shipping* Chrome extension — port-probe order, the private-network CORS header, the capture-validation rule. It is the one forward-looking thing in an otherwise historical document, and today it is buried on line 167 of a file whose third line says the app is "currently Electron + Node".

---

# Part 1 — the 35 `Electron` source references

`grep -rin electron --include=*.swift --include=*.js .`, excluding `.backlog/`, `marketing/`, `chromestore/`.

**Totals:** 35 hits → 3 false positives, 2 out-of-scope (`extension/`), 30 in scope: **21 REWRITE**, **6 DELETE**, **3 KEEP**.

## 1.1 KEEP (3) — the legacy DB is a real, still-existing artifact

These describe `tools/migrator/`, which reads an actual `jobhunt.db` SQLite file that still exists on the developer's disk. The reference is to a *file*, not to deleted source. Leave verbatim.

| File:line | Text |
|---|---|
| `core/Models/Schema.swift:15` | `// tool handles the separate one-time Electron→SwiftData import and is unrelated.` |
| `core/Models/Schema.swift:46` | `// legacy Electron jobhunt.db (SQLite) into a fresh SwiftData store. Its README documents` |
| `core/Models/ModelContainerFactory.swift:23` | `// Electron import CAN carry duplicate `job_number`s, which `--repair-duplicate-job-numbers` recovers.` |

## 1.2 DELETE (6) — the parenthetical carries nothing the sentence doesn't already say

In each case delete only the marked parenthetical; the rest of the comment stands unchanged and is still true.

| File:line | Current | Action |
|---|---|---|
| `core/Models/Projections.swift:287` | `// TASK-464: re-added MCP jobs_list payload fields dropped vs Electron.` | Delete the whole line. The fields below it are self-documenting; "were once missing" informs no future decision. |
| `core/Models/Projections.swift:438` | `// TASK-464: re-added MCP payload fields dropped vs Electron.` | Delete the whole line (duplicate of the above). |
| `core/Services/BackgroundStore.swift:578` | `// Job-level mirror reflects the BEST score across all resumes (Electron parity).` | Drop ` (Electron parity)`. "BEST score across all resumes" *is* the rule. |
| `app/Views/Duplicates/DuplicatesView.swift:637` | `// Summary + skills from the job's extracted data (restored from Electron compare).` | Drop ` (restored from Electron compare)`. |
| `tests/CoreTests/JobServiceTests.swift:419` | `// MARK: - Re-capture: same URL + changed content updates in place (Electron parity)` | Drop ` (Electron parity)` — the MARK already states the invariant. |
| `tests/CoreTests/JobServiceTests.swift:498` | `// MARK: - Manual field overrides (Electron parity: extraction must not clobber user edits)` | Rewrite to `// MARK: - Manual field overrides: extraction must not clobber user edits`. (Delete of the tag, keep the clause.) |

## 1.3 REWRITE (21) — the comment carries real knowledge; state it directly

Proposed replacement text given verbatim. All preserve the TASK reference where one exists.

### Rate limiting / concurrency

**`core/LLM/AdaptiveConcurrency.swift:4`**
```
/// (TASK-463, Electron parity with `onRateLimit`/`CONCURRENCY_PROMOTE_AFTER`).
```
→
```
/// (TASK-463). The back-off-on-429 / promote-on-success shape is carried over from the previous
/// implementation, where it was the only strategy that kept free-tier keys usable without
/// hand-configuring a per-account limit.
```

**`core/LLM/Providers/GoogleProvider.swift:14`**
```
/// Bounded 429 retry budget + per-wait clamp (TASK-463, Electron parity ~4 RL retries).
```
→
```
/// Bounded 429 retry budget + per-wait clamp (TASK-463). Four retries is where the previous
/// implementation settled: a free-tier key recovers within four waits, and beyond that the quota
/// is exhausted for the window, so more retries only stall the queue behind a request that
/// cannot succeed.
```

**`core/LLM/Providers/OpenRouterProvider.swift:19`**
```
/// Max distinct free models tried per request when rotating (TASK-462, Electron parity).
```
→
```
/// Max distinct free models tried per request when rotating (TASK-462). Capped at 4 so one bad
/// request can't walk the entire free pool — past four failures the fault is almost always the
/// request, not the model.
```

**`core/LLM/Providers/OpenRouterModelPool.swift:3`**
```
/// Free structured-output model pool for OpenRouter rotation (TASK-462, Electron parity with
/// `selectFreeStructuredModels`/`refreshRotationPool`). Fetches `/models`, filters to FREE models
```
→
```
/// Free structured-output model pool for OpenRouter rotation (TASK-462). Fetches `/models`,
/// filters to FREE models
```
(The named functions no longer exist and cannot be consulted; the sentence that follows already describes the behaviour completely.)

### Location / criteria

**`core/LLM/LocationCriteria.swift:3`**
```
/// Whether a job meets the user's location/remote criteria — Electron parity with
/// `applyLocationFilter` (TASK-464). Pure; computed post-extraction from the extracted remote mode +
```
→
```
/// Whether a job meets the user's location/remote criteria (TASK-464). Pure; computed
/// post-extraction from the extracted remote mode +
```

**`core/LLM/ExtractionEngine.swift:198`**
```
// TASK-464: compute meets_criteria from the EXTRACTED remote mode (before the clamp below) +
// location against the user's location/remote settings — Electron parity.
```
→
```
// TASK-464: compute meets_criteria from the EXTRACTED remote mode (before the clamp below) +
// location against the user's location/remote settings. It must be computed pre-clamp so the
// verdict reflects what the posting actually offers, not what the user allows.
```

**`core/Models/Job.swift:43`**
```
/// Whether the job passed the user's location/remote criteria at extraction time (TASK-464,
/// Electron `meets_criteria`). Nil for jobs extracted before this field / when not computed.
```
→
```
/// Whether the job passed the user's location/remote criteria at extraction time (TASK-464).
/// Named `meets_criteria` in the MCP payload and in imported legacy rows. Nil for jobs extracted
/// before this field / when not computed.
```
*(This one is load-bearing: the wire name really is `meets_criteria`, so the mapping must survive the rewrite.)*

**`core/Settings/SettingsStore.swift:536`**
```
// Combine manual preferred locations with expanded preferred metros (Electron parity:
// makeExtractorFromSettings expanded metros into the location context), deduped.
```
→
```
// Combine manual preferred locations with expanded preferred metros, deduped: a metro must reach
// the model as its constituent city names, or a posting in a suburb of a preferred metro reads
// as out-of-area.
```

**`tests/CoreTests/LocationCriteriaTests.swift:4`**
```
/// TASK-464: meets_criteria computation (Electron applyLocationFilter parity).
```
→
```
/// TASK-464: meets_criteria computation.
```

### Fit scoring

**`core/Services/JobService.swift:477`** and **`core/Services/BackgroundStore.swift:958`** (same parenthetical, two sites)
```
/// LLM calls (Electron parity: rescore.js). Returns the number of scores updated.
/// model — no LLM calls (Electron parity: rescore.js). Returns the count updated.
```
→ drop ` (Electron parity: rescore.js)` from both, and add to the `BackgroundStore` one:
```
/// model — no LLM calls: the dimension scores are the model's output, the weights are ours, so a
/// weight change is a pure recompute. Returns the count updated.
```

**`core/Services/BackgroundStore.swift:583`**
```
/// fit-score records (Electron parity: jobs.fit_score = MAX across resumes). Falls back to
```
→
```
/// fit-score records — the job's headline score is the MAX across resumes, since a job is as good
/// a fit as your best résumé for it. Falls back to
```

**`core/Services/BackgroundStore.swift:1182`**
```
/// Mirrors the Electron app's queueFitScoresForAllResumes auto-scoring behavior.
```
→
```
/// Every active résumé is scored, not just the default one: which résumé fits best is exactly the
/// question the score is meant to answer.
```

**`tests/CoreTests/JobServiceTests.swift:2026`**
```
// Electron parity (rescore.js): recompute the overall score from stored dimensions using
// current weights, no LLM. Dimensions 80/50/80/90/60 → 72 with the TASK-602 weights
```
→
```
// Recompute the overall score from stored dimensions using current weights, no LLM.
// Dimensions 80/50/80/90/60 → 72 with the TASK-602 weights
```

### Duplicates / ingest

**`core/Services/BackgroundStore.swift:2100`**
```
/// (Electron parity: detectDomainDuplicateJobs after markExtractionSucceeded.) Returns count flagged.
/// TASK-624: no longer called by the app — duplicates are never auto-marked. Retained for tooling.
```
→
```
/// Returns count flagged. Historically run automatically right after a successful extraction;
/// TASK-624 stopped that — duplicates are never auto-marked. Retained for tooling.
```

**`core/Services/BackgroundStore.swift:2379`**
```
// brand-new duplicate job. (Electron parity: insertCapture's same-URL update path.)
```
→
```
// brand-new duplicate job: re-visiting a posting whose text changed must update the row you are
// already tracking, not fork your history across two job numbers.
```

### MCP wire compatibility

These three describe a **live wire contract** with third-party MCP clients. The `job_id` alias is not history — it is still accepted today. Rewrite to say so without naming the dead app.

**`server/swift/MCPBridgeRoutes.swift:82`**
```
// TASK-464: Electron parity — richer add_site fields.
```
→
```
// TASK-464: the full add_site field set, as accepted by the MCP `add_site` tool.
```

**`server/swift/MCPBridgeRoutes.swift:599`**
```
/// Resolve a job by `job_id` (internal id string — Electron back-compat) or `job_number`
```
→
```
/// Resolve a job by `job_id` (internal id string — accepted for back-compat with clients written
/// against the pre-1.0 MCP schema) or `job_number`
```

**`mcp/swift/MCPHelpers.swift:418`**
```
// TASK-464: accept either job_number (primary) or job_id (Electron back-compat).
```
→
```
// TASK-464: accept either job_number (primary) or job_id (back-compat with pre-1.0 MCP clients).
```

**`tests/MCPTests/MCPTests.swift:153`**
```
// MARK: - TASK-464: MCP job tools accept job_id (Electron back-compat) or job_number
```
→
```
// MARK: - TASK-464: MCP job tools accept job_id (pre-1.0 back-compat) or job_number
```

### Status vocabulary

**`core/Services/DashboardMetrics.swift:154`**
```
// Map legacy Electron-era status words onto the current JobStatus vocabulary.
```
→
```
// Map the pre-1.0 status words (saved/ignored/not_available) still present on imported and
// long-lived rows onto the current JobStatus vocabulary.
```
*(This is a live data concern — rows with those words exist in the production store — so the comment must keep saying that, just without the dead-codebase pointer.)*

## 1.4 False positives (3) — no action

`core/Services/JobPromptBuilder.swift:315`, `:555`, `tests/CoreTests/JobPromptBuilderTests.swift:94` all match the word **electronic** ("must STILL NOT complete electronic signatures"). Unrelated.

## 1.5 Out of scope but genuinely stale — `extension/service_worker.js` (2)

The lead flagged these as "likely incidental". **They are not.** Verified:

- `extension/service_worker.js:769` — `// Ask the Electron window to focus and navigate — no new browser tab needed.`
- `extension/service_worker.js:779` — `// Fallback: open the web UI in a browser tab (CLI server or Electron not responding).`

The `POST /api/app/focus` call on :770 is real and still handled by the Swift server, so the *code* is fine — but the fallback below it (`chrome.tabs.create` on `serverUrl("/") + "#/jobs/<n>"`) opens **the deleted React web UI**. In a Swift-only world `GET /` almost certainly does not serve that SPA, so this fallback path is dead or broken. `[UNVERIFIED]` — confirming needs the app running to see what `GET /` returns. Recommend a separate task against `extension/`; out of scope here.

## 1.6 Related residue with no `Electron` keyword — provenance comments (3)

Found by searching for deleted *paths* rather than the word. Same class of problem, same fix.

| File:line | Current | Proposed |
|---|---|---|
| `core/LLM/Normalization.swift:708` | `/// Mirrors mapStatus/mapRemote/mapEmployment/mapExtractionStatus from static/transform.js.` | `/// Ported from the pre-Swift `static/transform.js` (readable at `git show a6f41a2a^:static/transform.js`).` |
| `core/Util/JDParser.swift:1` | `// JDParser.swift — port of static/jd-parser.js` | `// JDParser.swift — ported from `static/jd-parser.js` (`git show a6f41a2a^:static/jd-parser.js`).` |
| `core/Util/JSONRepair.swift:1` | `// JSONRepair.swift — minimal port of npm jsonrepair behavior` | **KEEP as-is** — `jsonrepair` is a real, still-published npm package, not a deleted file. |

Two false positives on the same search, no action: `core/Util/Cleaning.swift:210` and `tests/CoreTests/CleaningTests.swift:247` match `_next/static/`, i.e. Next.js markup being stripped from captures.

---

# Part 2 — verdicts on all 23 markdown docs

(Task text says 22; the actual count at root + `docs/` is 23.)

## 2.1 Summary table

| Doc | Last touched | Verdict |
|---|---|---|
| `AGENTS.md` | 2026-06-13 | **CURRENT** |
| `README.md` | 2026-08-20 | **UPDATE** |
| `CONTRIBUTING.md` | 2026-07-07 | **UPDATE** |
| `CLAUDE.md` | 2026-08-31 | **UPDATE** ← highest value |
| `PRIVACY.md` | 2026-08-09 | **CURRENT** |
| `SECURITY.md` | 2026-06-15 | **CURRENT** |
| `THIRD_PARTY_NOTICES.md` | 2026-06-12 | **CURRENT** (one omission noted) |
| `swift-plan.md` | 2026-06-07 | **ARCHIVE** (judgement call — §5) |
| `docs/app-store-metadata.md` | 2026-08-01 | **UPDATE** |
| `docs/auto-search-spec.md` | 2026-08-22 | **UPDATE** |
| `docs/backlog-triage-2026-08.md` | 2026-08-09 | **ARCHIVE** (judgement call — §5) |
| `docs/chrome-web-store-review.md` | 2026-06-15 | **CURRENT** |
| `docs/fit-scoring-problem-statement.md` | 2026-08-20 | **CURRENT** (one nit) |
| `docs/job-detail-pane-spec.md` | 2026-06-11 | **ARCHIVE** (judgement call — §5) |
| `docs/MAS-VALIDATION.md` | 2026-06-18 | **CURRENT** |
| `docs/model-benchmark-2026-08.md` | 2026-08-20 | **UPDATE** (still load-bearing) |
| `docs/release-process.md` | 2026-08-09 | **UPDATE** |
| `docs/site-deploy.md` | 2026-08-20 | **CURRENT** |
| `docs/test-db-spec.md` | 2026-06-18 | **UPDATE** (substantial) |
| `docs/test-strategy.md` | 2026-07-21 | **UPDATE** |
| `docs/tuning.md` | 2026-07-08 | **CURRENT** |
| `docs/vm-testing.md` | 2026-06-17 | **UPDATE** |
| `docs/workflow.md` | 2026-06-18 | **CURRENT** |

**Note:** not one of the docs verdicted UPDATE is wrong *because of the Electron cutover*. The cutover's documentation debt is almost entirely concentrated in `swift-plan.md`, the source comments in Part 1, and the residue in Part 3. The rest of the doc drift is ordinary drift — worth fixing, but a separate concern from TASK-696's framing.

## 2.2 `CLAUDE.md` — UPDATE (highest priority)

Loaded into every agent session. Four hard errors:

- **:155** — "The app responds to these in `app/JobhuntApp.swift` (`LaunchPlan.parse(...)`, ~line 41)". Two errors: `LaunchPlan` is defined in **`core/App/LaunchMode.swift:18`** with `parse` at **:86**, not in the app target; and the call site is **`app/JobhuntApp.swift:114`**, not ~41. → "parsed by `LaunchPlan.parse` (`core/App/LaunchMode.swift:86`), called from `app/JobhuntApp.swift:114`."
- **:190** — "against `macos-latest` runner". `.github/workflows/ui-tests.yml:14` pins **`runs-on: macos-15`**. (Cron `0 8 * * 1` and 7-day retention are correct.)
- **:143** — settings tabs "(General/Jobs/AI/Data/Debug)". A **Search** tab exists: `app/Views/Settings/SettingsView.swift:54-79` → General(0), Jobs(1), AI(2), Data(3), **Search(5)**, Debug(4, hidden when `hideDebugTab`).
- **:149-154 launch arguments** — incomplete vs `tests/AppUITests/AppUITests.swift:70-76`. Missing **`-ApplePersistenceIgnoreState YES`** and **`--llm-mock-port <port>`** (TASK-486; it is what drives `MockLLMUITests`, which the doc lists two lines above). Also unmentioned anywhere: `--fixture-db <path>` and `--seed-fixture-output <path>`.

Three lists presented as exhaustive that are not — agents will act on them as complete:

- **:356-368 migrator modes** — six shipped flags missing, all in `tools/migrator/Args.swift:15-24,130-151`: `--prune-orphan-referral-attempts`, `--recheck-evidence`, `--normalize-seniority`, `--unmark-heuristic-duplicates`, `--recompute-criteria`, `--repair-canonical-urls`. (Every flag currently listed is real and correctly spelled, including the "exactly one operation flag" rule at `Args.swift:189-213`. Knock-on: `tools/migrator/README.md`, which :378 tells you to keep updated, is itself missing the last three.)
- **:141-146 AppUITests classes** — 5 of 10 listed. Missing: `AccessibilityAuditTests`, `KeyboardShortcutsUITests`, `ReferralUITests`, `SavedSearchUITests`.
- **:92-105 Directory Layout** — omits `tools/scorelab/` (the `ScoreLab` commandLineTool target, `Project.swift:257-263`) and `extension/` (the shipped MV3 extension, whose npm tests gate CI). The `tests/` sub-list omits `LLMEval/`, `Support/`, `fixtures/`.

One cross-check to resolve before editing either side: `CLAUDE.md:278` says key `68BGNV3CCC` belongs to **nevermore** and JobHunt uses `Y4673VW6CJ`, but `scripts/asc-stats.py:17`'s config example shows `"key_id": "68BGNV3CCC"`. One is stale — the script docstring is the likelier culprit. `[UNVERIFIED]` — `~/.appstoreconnect/config.json` is outside the repo and was not read.

`[UNVERIFIED]` (machine/timing/Apple-state dependent, not checkable here): :36-38 / :68 hardware and "~30s" claims; :232-253 the Xcode-beta 90301 narrative.

Everything else in `CLAUDE.md` was checked and is correct — including the `Project.swift` CoreTests `sources:` snippet (matches `:274-282` exactly), the hardened-runtime claim, the store-path table, the bundle-id-identical-across-configs claim, `productionExtensionOrigin`, `DiscoveryCriteria.gateVersion`, the `QueueActor` closure-init parameter names, and both `docs/release-process.md` anchors.

## 2.3 `README.md` — UPDATE

- **:75** — lists **"Apple Foundation Models (macOS 26+, DMG only)"** as a supported provider. **The provider was removed.** `core/Settings/SettingsStore.swift:107-114` has `migrateRemovedProviders()` redirecting `foundation_models`/`apple` → `lmstudio`; there is no such provider in `core/LLM/Providers/` and no entry in `ProviderOption.all` (`core/LLM/AIProviderFormModel.swift:39-66`). **Delete the bullet.** This is a user-facing false claim on the front page.
- **:73-74** — provider list wrong twice vs `ProviderOption.all` (`lmstudio, openai, anthropic, google, openrouter, deepseek, custom`): **Ollama is not a first-class provider** (no `"ollama"` id anywhere in `core/`, `app/`, `server/`) — it works only via **Custom**; and **DeepSeek is missing** from the cloud list although :87 already tells users to bring a DeepSeek key.
- **:146-158 Features** — omission: the shipped auto-search/discovery feature (Settings → Search, `core/Services/DiscoverySweeper.swift`) has no bullet.
- **:81** — "~$1.40 per 100 postings" inherits the lapsed OpenRouter promo rate; see §2.6.

Verified correct and needing no change: macOS 15.0 floor, DMG asset name, `Contents/Helpers/jobhunt-mcp`, CWS ID matching `JobhuntServer.productionExtensionOrigin:425`, `~/.jobhunt-mcp-token`, the MCP payload semantics, ⌘⇧E export, and all 8 linked local paths resolve.

## 2.4 `CONTRIBUTING.md` — UPDATE

- **:95-118** — claims the local gate "mirrors `.github/workflows/swift-build.yml` step-for-step". **Two CI steps are missing, both of which fail builds:** `./scripts/check-tooltips.sh` (TASK-494) and `DEVELOPER_DIR="$(xcode-select -p)" ./scripts/check-warnings.sh` (TASK-570). Both scripts exist and are executable. Add them, or soften the claim.
- **:120-122** — reads as "and that's the rest", which it isn't once the two above are counted.

Note `:113`'s `npm test --prefix extension` is **correct and current** — `extension/package.json` is the extension's own manifest (dependency-free, `node --test 'tests/*.js'`), matching `swift-build.yml:122`. It is not stale root-`package.json` residue. Everything else verified: `.mise.toml` pins, scheme/config/target names, script interfaces, `.marketingVersion("1.4.0")` matching `extension/manifest.json`.

## 2.5 `docs/test-db-spec.md` — UPDATE (substantial divergence)

The infrastructure it specifies genuinely shipped (fixture + manifest + CI check + `FixtureSeeder` + `--fixture-db`), but the data-coverage tables describe a fixture that was never built and a Phase 3 that never happened. This is the "silently diverged spec" case the lead asked about — it currently misdescribes committed test data.

- **:61-78** — status table totalling "~33 jobs". Fixture has **48**: `new` 12 (doc says 3), `pursuing` 8 (4), `applied` 7 (5). Contradicted by `tests/CoreTests/FixtureTests.swift:15-25`.
- **:82-92** — QualityIssueKind table lists `lowConfidence` and `staleApplication`, **neither of which is a case**. Real enum (`core/Models/QualityIssue.swift:5-15`): missingCompany/missingTitle/missingLocation/missingWorkMode/missingSalary/extractionFailed/extractionPending/shortRawText/shortCleanedText/staleExtraction — five of which the doc omits.
- **:143-151** — Job Actions table lists `phoneScreen`/`onsite` action types; `JobAction` has **no type field**, and the fixture seeds 6 actions, not 8 (`core/Demo/FixtureSeeder.swift:1143-1230`).
- **:134-141** — saved-search names all wrong. Actual: "Active Pipeline", "Remote Only — High Fit", "Needs Action — Applied" (`FixtureSeeder.swift:1291-1320`).
- **:114-122** — "10 live JDs with raw HTML, 4 expired, 2 redirect-to-homepage" was never built; `FixtureSeeder.swift:1046-1060` synthesizes text from title+company+location+summary+requirements. No raw HTML, no live-URL canaries. This also moots the :231 open question and :171's "strip `<img>` tags".
- **:124-132** — sites table wrong; fixture has 5 generic board rows ("Lever Job Boards", "Defunct Job Board (404)"), not the linkedin/greenhouse/lever/indeed breakdown.
- **:204-210 Phase 3** — did not happen. **Zero** `AppUITests` pass `--fixture-db`; the two named tests still use demo seeding; `AvailabilityCheckerTests` does not open the fixture. Only `FixtureTests`, `LaunchPolicyTests`, `SchemaEvolutionTests` consume it.
- **:213 Phase 4 #13** — `docs/vm-testing.md` has zero mentions of the fixture. (#14 *is* done.)
- **:27** vs **:187** — internally inconsistent: the API is `fixture(copying:)`.
- **:196** — "add `tests/fixtures/` to `.gitignore` exclusion"; `.gitignore` has no `fixtures` entry at all. Nothing to do.
- **:221** — "there is no 'Load Demo Data' menu item" is true of the menu bar, but `app/Views/Settings/DebugTab.swift:183` has a **Seed Demo Data button**.

## 2.6 Remaining UPDATE docs — specifics

**`docs/auto-search-spec.md`** — substance is current (M1–M6 all on `main`); the *code listings* drifted:
- :59-60, :154-156, :603 — "`WorkdayProvider.listOpenRoles` returns `[]` — the one real vendor gap". **Implemented**: `core/Services/ATSProviders.swift:330-337` delegates to `WorkdayJobBoard.listOpenRoles`; `fetchPosting` (:313-322) hits the CXS detail endpoint.
- :223-241 — `DiscoveredPosting` has no `departments`, no `updatedAt` (`core/Models/DiscoveredPosting.swift:17-33`); the vendor table at :256 advertises department capture that isn't modeled.
- :303-324 — `DiscoveryCriteria` has no `excludeSeniority` and adds `allowRemote/allowHybrid/allowOnsite`; `DiscoveryRejectReason` is `title, location, arrangement, salary, stale` — no `.seniority`, and `.arrangement` is undocumented (`core/Services/DiscoveryCriteria.swift:6-13,44-74`).
- :318, :438 — `hashValue`/`criteriaHash: Int` are actually a string `fingerprint` (`DiscoveryCriteria.swift:132`) and `criteriaFingerprint: String` (`core/Models/DiscoveryLedgerEntry.swift:46`). **This one matters** — CLAUDE.md's gate-version rule depends on readers understanding the fingerprint.
- :423-433 — ledger splits into `outcomeRaw` + `rejectReasonRaw`, not one `verdictRaw`.
- :382-399 — field is `lastStatusRaw`/`SearchSourceStatus`, whose `never` and `misconfigured` cases the doc omits.
- :131, :674-675 — "No changes to `ingestCapture`" is false; it gained `createOnly: Bool = false` for discovery (`core/Services/JobService.swift:110-112`).
- Stale line citations presented as checked: :64 (`DuplicateDetector.swift:373` is now `specificFullURLKey`; `atsPostingID` is at :174), :62 (`workdayCXSQuery` is :489 not :477), :72 (`ingestCapture` is :110 not :97).
- `[UNVERIFIED]` — every measured number (400,616-posting aggregation, the GitLab 204/195/9 run, the live `23andme.wd5` probe) is a historical measurement, not a code claim.

**`docs/model-benchmark-2026-08.md`** — **still load-bearing, not superseded.** It is the cited authority for `ModelRecommendation.modelID` and for `fit-scoring-problem-statement.md:185`. But :86's "OpenRouter 50%-off promo **ending 2026-08-27**" has now lapsed (today is 2026-08-31), so the "Billed here" column (:15, :86, and the `0.375 / 1.875` row at :105) is historical and standard `0.750 / 3.750` applies. The doc's own warning at :92 is now triggered. Re-verify against `GET /api/v1/models`, then propagate to `README.md:81`, `ModelRecommendation.summary`, and `marketing/help/which-model.html`. **This matches the standing memory "verify model pricing by search" — a stale promo rate has already caused one wrong published claim.**

**`docs/release-process.md`** — two internal contradictions where §2 wasn't updated when MAS went live:
- :8 — MAS status "**Live** — … first submission under review" contradicts :234 ("published on the App Store") and `app-store-metadata.md:3`.
- :116 — "It does **not** trigger MAS (that's `workflow_dispatch`-only until §5)". **False**: `.github/workflows/release-mas.yml:13-15` is `push: tags: ['v*']`, and :232 of this same doc says so. **This one is dangerous** — a reader tags a release believing MAS won't fire.
- :68 — "(MAS will need its own uint32-sized build-number scheme when it ships…)" is stale; :251 documents the `yymmddHHMM` auto-increment as shipped.

**`docs/app-store-metadata.md`** — :93 pins version `1.0.1`; `Project.swift:45` is `1.4.0` and the latest tag is `v1.4.0`. :99-169's "What's New" is still 1.3.0 copy; :138 says "last delivered was `mas-v1.1.3`" but `mas-v1.3.0` exists.

**`docs/test-strategy.md`** — :79-85 AppUITests table missing `AccessibilityAuditTests`(1), `KeyboardShortcutsUITests`(5), `ReferralUITests`(1), `SavedSearchUITests`(2), and lists `JobsScreenUITests` as 2 tests when the file has 1. :100 says `macos-latest` for `ui-tests.yml`; it pins `macos-15` (`docs/vm-testing.md:229` has this right). :14-25 omits the `npm test --prefix extension` job that gates merges (`swift-build.yml:121-122`).

**`docs/vm-testing.md`** — :176's "**Limitation**: Screenshots and the `.xcresult` are lost when the VM shuts down … See the backlog for a planned fix" **contradicts :111 and :267-276 in the same file**, which describe the `EXIT`-trap copy-back that shipped (TASK-402, recorded at `.gitignore:32-33`). Delete :176; the manual `scp` recipe at :170-174 is now `--no-shutdown`-only. :252-257's "last observed versions" table is dated 2026-06-17 with the CI row blank — refresh or drop.

**`docs/fit-scoring-problem-statement.md`** — CURRENT; one nit: :187 says gemini ties Sol "at **6×** lower cost" while `model-benchmark-2026-08.md:36` says **5×**. Reconcile.

**`THIRD_PARTY_NOTICES.md`** — CURRENT, and to answer the framing question directly: **it does not list any Node/Electron/npm dependency.** Its single entry is `extension/Readability.js`, a live vendored file; the one "npm" string (:19) is a fetch instruction for updating it. Separate (non-cutover) gap: it omits **Sparkle** and **swift-nio**, the app's actual current third-party code.

---

# Part 3 — cutover residue (report only, nothing removed)

## 3.1 Dead / unwired scripts

Every script cross-checked against the whole repo, `.github/workflows/`, `extension/package.json`, and docs.

| Script | Finding |
|---|---|
| `scripts/screenshot-views.sh` | **Strongest dead-code candidate.** 9.1 KB of AppleScript navigating the sidebar by hard-coded button index and x/y **pixel coordinates** (`:5-14`), with a stale "10 buttons" map. Zero external references. Superseded by `ScreenshotTests` + `scripts/screenshot-tests.sh`. |
| `scripts/check-stale-artifacts.sh` | **No callers** anywhere. Also carries Electron-era assumptions: `:47` scans `dist/*.dmg`; `:18` shells out to `node -e "require('./extension/manifest.json')"`. Ironic given §3.3. |
| `scripts/migrate-db.py` | Superseded by Swift `tools/migrator`. Sole reference is a comment: `tools/migrator/main.swift:47` "Matches the pgrep precondition in scripts/migrate-db.py." Reads the legacy Node-era `jobhunt.db`. |
| `scripts/label-error-direction.py` | Only self-references. Not cited by `fit-scoring-problem-statement.md` (which names only `export-fit-analysis.py`) nor any test. |
| `scripts/package-firefox-extension.sh` | Zero references, but builds against a real `extension/manifest.firefox.json` — an **unwired capability** (TASK-619's "Firefox port is buildable" half), not rot. Do not delete; document or wire it. |
| `scripts/__pycache__/*.pyc` | **Two compiled bytecode files are committed to git** (`analyze-fit-quality.cpython-314.pyc`, `migrate-db.cpython-314.pyc`). `.gitignore` has no `__pycache__/` or `*.pyc` entry, which is why. |
| `scripts/analyze-fit-quality.py` | Live-ish: sole coupling is a comment at `tests/CoreTests/FitScorerTests.swift:681` warning the Swift filter must not drift from its `is_fragment`. Unenforced coupling — worth a note. |

All other scripts have live callers.

## 3.2 CI workflows — **clean of cutover residue**

No `actions/setup-node`, no `npm ci`/`npm install`, no reference to `electron/`, `static/`, `native/`, or a root `package.json` across all 10 workflow files. The two Node usages are both legitimately about the live extension (`swift-build.yml:121-122`, `release-extension.yml:34`).

Two non-Electron leftovers from the migration branch:
- `.github/workflows/swift-build.yml:11` — `branches: [main, swift-rewrite]`
- `.github/workflows/version-parity.yml:8` — `branches: [main, swift-rewrite]`

`swift-rewrite` merged in `a6f41a2a` and no longer exists.

Latent fragility (not residue, but noted): both Node invocations rely on the runner's preinstalled `node` with no `setup-node` pin.

## 3.3 `.gitignore` — and a real Electron artifact still on disk

- **:14-15** — `# Electron build output` / `dist/`. The comment names the deleted stack, **and a real `dist/` directory still exists in the working tree**: `builder-debug.yml`, `builder-effective-config.yaml`, `latest-mac.yml` (the electron-updater feed), `Jobhunt-0.2.0-arm64.dmg.blockmap`, `Jobhunt-0.2.0.dmg.blockmap`, `Jobhunt-0.2.2-arm64.dmg.blockmap`, `Jobhunt-0.2.2.dmg.blockmap`, `dist/mac/`, `dist/mac-arm64/`. Untracked and ignored, so invisible to CI and to every previous audit. Per `release-process.md:15`, the `v0.2.x` releases *were* the Electron app. **This is the last physical Electron artifact in the repo.**
- **:1** — `node_modules/`: no such directory exists and `extension/package.json` declares zero dependencies. Vestigial, harmless insurance.
- **:10-12** — the "do NOT use `*.lock`" policy comment reasons about `package-lock.json`/`yarn.lock`; there is no root manifest and the extension has no lockfile, so the rationale now applies to nothing.
- **:40 and :45** — `build/` listed **twice**.
- **Missing** — no `__pycache__/` or `*.pyc`, hence §3.1's committed bytecode.

## 3.4 `.mise.toml` — nothing dead

`tuist 4.196.1`, `swiftlint 0.63.3`, `swiftformat 0.61.1`. All three have live callers in workflows and scripts. The `swiftformat` pin is **load-bearing** per `docs/backlog-triage-2026-08.md:112-114` (Homebrew's 0.62.1 disagrees on 110 files vs CI's 18) — do not float it. No Node tool is pinned, which is correct even though CI shells out to `node`.

## 3.5 TASK-064 itself (AC #6)

`.backlog/tasks/task-064 - Cutover-cleanup-remove-Electron-Node-React-update-docs.md`: `status: Done`, all **four** acceptance criteria unchecked, final summary "Cutover complete: legacy Electron/Node/React stack removed, README and docs updated for native Swift app."

Assessment against evidence:
- **AC#1 — met.** `electron/`, `static/`, `native/`, `package.json`, `scripts/notarize.cjs` all confirmed gone (`a6f41a2a`).
- **AC#2 — met.** `extension/`, fixtures, `marketing/`, `chromestore/`, `swift-plan.md` retained; `bump-version.sh` adapted.
- **AC#3 — partially met, and the summary overstates it.** README/CONTRIBUTING were updated for Swift/Tuist, but "no Node references" was not achieved in the sense the AC means: 30 in-source Electron references remain, `swift-plan.md` still opens by calling the app "currently Electron + Node", and `.gitignore` still has an `# Electron build output` section pointing at a directory that still exists.
- **AC#4 — `[UNVERIFIED]`.** No build was run in this audit.

Recommendation: **supersede rather than reopen.** TASK-064's code half is genuinely, verifiably done and reopening it re-litigates settled work; TASK-696 already scopes the remaining half. Concretely — tick AC#1 and AC#2 on TASK-064, replace its final summary with an honest one ("legacy stack removed; documentation cleanup deferred to TASK-696"), and add a `[[TASK-696]]` link. Leave `status: Done`.

---

# Part 4 — Judgement calls (decide before acting)

Everything above is high-confidence and evidence-backed. These three need a human decision, and the tradeoff is stated for each.

## 4.1 `swift-plan.md` — recommend **ARCHIVE to `docs/archive/swift-plan.md`**, not delete

Its premise line (`:3`, "currently Electron + Node") has been false since `a6f41a2a`. Now-false lines if anyone tries to keep it live as-is: `:3, :59, :65, :74, :81, :190, :219, :384, :641, :676-679`.

**What deletion would lose** — three things git history does not contain:

1. **§4 `:167-186` — "The extension contract (must not break)."** A normative, byte-level table of five endpoints plus behaviour: port-probe order 8765→8769, `Access-Control-Allow-Private-Network: true` on `chrome-extension://` preflights, and the capture-validation rule (require `url`, `page_title`, and at least one of `visible_text`/`selected_text`). This is a **contract with a currently-shipping, published Chrome extension** — forward-looking, not history. Git shows what the old Express routes *were*; it does not record which of them were *promised to a third party*. Nothing else in the repo states this.
2. **§6.1 `:245-270` — legacy SQLite → `@Model` field mapping**, with the rationale for retaining legacy integer keys (`jobNumber`, `rawHash`, `cleanedHash`) as stored properties "so the extension's `job_number`, the importer, and CSV export stay stable." Anyone touching SchemaV2 (parked TASK-480) needs the *why*; the diff that added those columns doesn't explain it.
3. **§16 `:648-673` — rejected alternatives.** GRDB vs SwiftData and the condition under which pivoting is still cheap; swift-nio vs Vapor ("revisit only if the server grows"); why MCP bridges over localhost HTTP rather than opening the store directly (single-writer). **Git records the choice made and never the choices declined** — this is the classic irrecoverable category.

Everything else (§1 LOC inventory, §10 parity checklist, §15 milestones, §17 deletion list, §18 kickoff order) is fully superseded.

**Recommended action:** lift §4 into a live `docs/extension-contract.md`, then move the remainder to `docs/archive/swift-plan.md` with a one-line header: "Completed migration plan. The migration landed in `a6f41a2a` (2026-06-07); this document describes the pre-Swift codebase and is retained for §6.1's schema rationale and §16's rejected alternatives." Optionally lift §16 into `.backlog/decisions/` if that directory is the intended home for ADRs — it exists but I did not survey it.

**Tradeoff if you delete instead:** you save 789 lines of confusing file and rely on `git show a6f41a2a:swift-plan.md`. That works for anyone who knows to look — which is exactly the population that doesn't need it. The extension contract is the piece I would not gamble on.

## 4.2 `docs/backlog-triage-2026-08.md` — recommend **ARCHIVE**

A dated point-in-time triage whose own "Final state — 2026-08-09" section is already superseded: `:98` says TASK-570 is "WORK, 2 of 5 … Periphery needs a curated retain-rule set before it can gate", but `.github/workflows/static-analysis.yml` now runs `scripts/check-periphery.sh` weekly with `.periphery-baseline` committed. It informs no open decision.

**But it holds one durable fact worth rescuing before archiving:** `:112-114`, the reason the `swiftformat = "0.61.1"` pin cannot float (Homebrew 0.62.1 disagrees on 110 files vs CI's 18). That belongs in `CONTRIBUTING.md` or as a comment in `.mise.toml`, where someone about to bump the pin will actually see it. The rest of the "Standing risks" block (`:110-118`) is already covered by CLAUDE.md/CONTRIBUTING.

**Tradeoff:** archiving a triage snapshot costs nothing if the pin rationale is moved first; if it isn't, someone floats the pin and burns an afternoon on a 110-file format diff.

## 4.3 `docs/job-detail-pane-spec.md` — recommend **ARCHIVE**, after extracting one open item

A build-this spec whose "current implementation" inventory is now wholly wrong and whose gap list is ~90% shipped. Its `:4` framing — "documents every gap versus the original Node.js app" — is pre-migration by construction.

Superseded specifics: `:173-244, :448-452` describe a tab structure that never happened (real tabs are `Overview · Fit · Timeline · Description · Raw · Compare`, `app/Views/Detail/JobDetailView.swift:23-29`); `:234`'s "Bug: summary truncated to `String.prefix(500)`" — no such call exists in `app/` or `core/`; `:224/:418`'s "no resume name shown (bug)" is fixed at `JobDetailView.swift:1599`; `:227, :420-427` (requirements + BEST badge), `:257, :326-343` (next-action), `:312-323` (Description tab), `:347-358` (Skills), `:444` (recapture icon) are all shipped; `:157-167` / `:290-307` are superseded by `DetailHeader` (:149-538), which the doc doesn't describe at all. Its model tables at `:9-101` omit `salaryHourlyMin/Max`, `appliedAt`, `meetsCriteria`, `availabilityCheckedAt/Verdict/Detail`, `atsFirstPublishedAt/atsUpdatedAt`, `manualFieldOverridesJSON`, `qualityReview`.

**Extract before archiving:** `:372-413` **Priority 5 (Apply tab: application instructions, contacts, cover letters) is genuinely unbuilt** — and it has left dead surface behind it. `Job.contacts` and `Job.coverLetters` relationships exist (`core/Models/Job.swift:96,99`) and `JobService+Contacts.swift` exists, but **no file under `app/` references `job.contacts`, `coverLetters`, `createContact`, or `CoverLetter`.** That is model + service code with zero UI. Turn it into a task (build it, or delete the dead surface); don't let a 466-line stale spec be its only record.

`[UNVERIFIED]` — the doc's keyboard claims at `:177` (`←`/`→` prev-next, `Esc` deselect). Navigation is wired as `onNavigatePrev/Next` callbacks from `app/ContentView.swift:379` with chevron buttons; no `keyboardShortcut(.leftArrow/.rightArrow)` was found in the detail pane, but bindings may live in a command menu or list-level handler not exhaustively traced. Confirming needs the app running.

---

# Appendix — what could not be verified without building or running

- TASK-064 AC#4 (both schemes build, full suite passes).
- `extension/service_worker.js:779`'s web-UI fallback — what `GET /` actually returns from the Swift server.
- `docs/job-detail-pane-spec.md:177` keyboard shortcuts.
- All measured numbers in `docs/auto-search-spec.md` and `docs/model-benchmark-2026-08.md` (historical measurements, not code claims).
- `README.md:17-18, :63` extension runtime behaviour (offline queue, pre-save preview) — `extension/retry_queue.js` and `status.js` are consistent with the claims, but confirming needs a browser.
- `CLAUDE.md:263-282` App Store Connect credentials (`~/.appstoreconnect/config.json` is outside the repo and was not read) — including the `68BGNV3CCC` vs `Y4673VW6CJ` discrepancy against `scripts/asc-stats.py:17`.
- `CLAUDE.md:36-38, :68, :232-253` — hardware, timing, and Apple-state claims.
