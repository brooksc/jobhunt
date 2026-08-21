# Automatic Job Search — Implementation Spec

Jobhunt today is a **pull** system: a posting exists in the app because a human put it there,
through the extension, the MCP bridge, or a paste. Discovery is a `Site` row with a
`nextReviewAt` date whose only effect is to remind you to go look yourself.

This spec turns jobhunt into a **push** system: it finds the postings, applies the user's
requirements with zero AI, and only then drops survivors into `new` where the existing
extraction and fit-scoring pipeline treats them exactly like any other capture.

It is written to be implemented in stages, each shippable on its own.

---

## Design constraints

These are load-bearing. Everything below follows from them.

1. **No AI before the criteria gate.** A board sweep returns thousands of postings. Extracting
   them all would cost more than the feature is worth and would fill the app with noise.
   Every filter that runs before ingest must be pure string/number work. AI enters only
   after a posting has cleared every configured requirement, and then through the *existing*
   path — `ingestCapture` → extraction queue → `FitScorer` — with no parallel scoring code.
2. **Reuse the requirements the app already has.** The user has configured location, remote
   arrangement, salary floor, and fit floor. A second, divergent definition of "what I'm
   looking for" is the failure mode to avoid.
3. **Discovery must never expire or mutate an existing job.** It only ever creates.
4. **A silent source is the enemy.** A board that migrates ATS does not error — it returns
   zero rows forever. Every source carries health state and says so in the UI.
5. **Nothing auto-applies.** This finds and files. It never contacts an employer.

---

## What already exists (and what it means)

The expensive parts are built. This is mostly wiring.

| Capability | Where | State |
|---|---|---|
| Board listing, Greenhouse | `GreenhouseJobBoard.listOpenRoles` → `boards-api.greenhouse.io/v1/boards/{board}/jobs` | **Done** |
| Board listing, Lever | `LeverProvider.listOpenRoles` → `fetchBoard(company:)` | **Done** |
| Board listing, Ashby | `AshbyProvider.listOpenRoles` → `fetchBoard(org:)` | **Done** |
| Board listing, Workday | `WorkdayProvider.listOpenRoles` | **Returns `[]` — the one real vendor gap** |
| Provider abstraction | `ATSProvider` protocol, `ATSProviders.swift` | Done, but posting-centric (see below) |
| HTTP response caching | `ATSResponseCache` | Done |
| Cross-run dedup | `DuplicateDetector.atsPostingID` (`gh:123`, `lever:co:uuid`) | Done |
| Relevance ranking of a board | `OpenRoleRelevance` — ranked GitLab's 189 roles | Done |
| Scheduler skeleton | `Site.intervalDays`, `Site.nextReviewAt`, `SiteService` | Fields exist; fire a reminder, not a fetch |
| Background sweep precedent | `AvailabilityBacklog`, `RuntimeTaskController` | Done — copy this shape |
| Requirements evaluation | `JobRequirements`, `LocationCriteria`, `JobFilterRules` | Done, but **post-extraction** (see below) |
| Criteria snapshot pattern | `SavedSearchCriteria` — Sendable, off-main-actor, unit-testable | Done — copy this shape |
| Settings surface | `SettingsStore`, `JobsSettingsTab` | Done; needs new keys + a tab |
| Ingest | `JobService.ingestCapture` — validate → clean → hash → dedup → create → enqueue | Done; discovery calls this unchanged |

### The two facts that shape the architecture

**`ATSProvider` is posting-centric.** Every method takes an `atsID` identifying one posting
on one company's board: `handles(atsID:)`, `fetchPosting(atsID:…)`, `listOpenRoles(atsID:…)`.
Even the listing call resolves the board *through* a known posting. That is correct for
refresh and availability, but discovery has no posting to start from — it starts from a
company, or from nothing at all. Discovery therefore needs a sibling protocol, not more
conformances to this one.

**`JobRequirements` cannot be the pre-AI gate.** It evaluates location, salary floor **and
fit floor**, and fit requires a score that only exists post-extraction. `LocationCriteria` is
likewise documented as "computed post-extraction from the extracted remote mode". Both consume
*extracted* fields; a sweep has only *raw ATS* fields. So the gate runs in two stages against
two different data shapes, and the pre-AI stage must be built to consume raw board rows.

This is not duplication if it is done right: stage 1 is a deliberately conservative subset of
stage 2, and stage 2 remains the authority. See "Two-stage filtering" below.

---

## Architecture

```
                      ┌─────────────────────────────────────────┐
   SearchSource       │  DiscoveryScheduler (RuntimeTaskController)│
   rows in SwiftData  │  wakes on the earliest nextRunAt         │
                      └───────────────────┬─────────────────────┘
                                          │
                       ┌──────────────────▼──────────────────┐
                       │  JobSource.fetchRecent(since:)      │  ← new protocol
                       │  Greenhouse│Lever│Ashby│Workday│…   │
                       └──────────────────┬──────────────────┘
                                          │  [DiscoveredPosting]  (raw, no AI)
                       ┌──────────────────▼──────────────────┐
                       │  STAGE 1 — DiscoveryCriteria.passes │  ← zero AI, pure
                       │  title kw · location · seniority ·  │
                       │  salary-if-published · freshness    │
                       └──────────────────┬──────────────────┘
                          rejected ───────┴─────── passed
                          (counted, not stored)      │
                       ┌─────────────────────────────▼───────┐
                       │  DiscoveryLedger.seen(atsPostingID) │  ← dedup across runs
                       └─────────────────────────────┬───────┘
                                                 new │
                       ┌─────────────────────────────▼───────┐
                       │  JobService.ingestCapture(payload)  │  ← UNCHANGED
                       └─────────────────────────────┬───────┘
                                                     │
                       ┌─────────────────────────────▼───────┐
                       │  extraction queue → FitScorer →     │  ← STAGE 2, existing
                       │  JobRequirements (incl. fit floor)  │
                       └─────────────────────────────────────┘
```

### New types

#### `JobSource` (protocol)

```swift
/// A source that can be swept for postings without knowing about any specific posting.
/// Sibling to `ATSProvider`, which is posting-centric and stays as-is.
public protocol JobSource: Sendable {
    /// Stable identifier persisted on `SearchSource.kind` (e.g. "greenhouse", "remotli").
    var id: String { get }
    /// Vendor's own name, shown to the user.
    var displayName: String { get }
    /// What this source needs configured. Drives the add-source form.
    var configuration: SourceConfiguration { get }

    /// Every posting this source currently lists, newest first where the vendor supports it.
    /// `since` is a hint: sources that can filter server-side should; others return all and
    /// let the caller drop stale rows. Throws `SourceError` so health can distinguish
    /// "unreachable" from "reachable and empty" — see Design constraint 4.
    func fetchRecent(config: SourceConfig, since: Date?, session: URLSession) async throws -> [DiscoveredPosting]
}

public enum SourceConfiguration: Sendable {
    /// Needs a company board slug — Greenhouse, Lever, Ashby, Workday.
    case perCompany(slugHint: String)
    /// Whole-market firehose with no company — Remotli, HN Who-is-Hiring.
    case marketWide
}
```

#### `DiscoveredPosting`

The raw board row, before any AI. Deliberately close to `GreenhouseJobBoard.OpenRole` plus
what stage 1 needs. Every field except the first three is optional, because vendors disagree
about what they publish — the same honesty `ATSPosting` already applies.

```swift
public struct DiscoveredPosting: Sendable, Equatable {
    public let atsPostingID: String   // must match DuplicateDetector.atsPostingID's format
    public let url: String
    public let title: String
    public let company: String?
    public let locationRaw: String?   // vendor's own string; NOT a parsed RemoteType
    public let departments: [String]
    public let firstPublished: Date?
    public let updatedAt: Date?
    public let salaryMinPublished: Int?   // only when the ATS publishes a band
    public let salaryMaxPublished: Int?
    public let descriptionPlain: String?  // present when the list endpoint includes it
    public let sourceID: String
}
```

`descriptionPlain` is optional on purpose. Greenhouse's list endpoint omits it; Ashby's
includes it. When it is absent, ingest passes the URL and title and lets the existing
extraction fetch the body — exactly what a browser capture does today.

#### `DiscoveryCriteria` — the stage 1 gate

Modelled on `SavedSearchCriteria`: a `Sendable`, `Hashable` value decoupled from SwiftData so
matching runs off the main actor and is unit-testable in isolation.

```swift
public struct DiscoveryCriteria: Sendable, Hashable {
    public var titleIncludeAny: [String]   // ≥1 must match (substring, case-insensitive)
    public var titleIncludeAll: [String]   // all must match; usually empty
    public var titleExcludeAny: [String]   // any match rejects
    public var allowRemote: Bool
    public var allowHybrid: Bool
    public var allowOnsite: Bool
    public var locationAllowTokens: [String]   // "United States", "Remote", metro names
    public var locationDenyTokens: [String]
    public var minSalaryIfPublished: Int   // 0 disables
    public var maxAgeDays: Int             // 0 disables
    public var excludeSeniority: [SeniorityLevel]

    public func evaluate(_ p: DiscoveredPosting, now: Date) -> DiscoveryVerdict
}

public enum DiscoveryVerdict: Sendable, Equatable {
    case pass
    case reject(DiscoveryRejectReason)   // .title, .location, .seniority, .salary, .stale
}
```

**Three rules that must not be violated:**

- **Absent data never rejects.** A posting with no published band is unknown, not
  disqualified. This is the rule `JobRequirements` already states ("Absent data never fails a
  requirement… lands in `.notStated`"), and stage 1 must not be stricter than stage 2 — the
  gate would then permanently hide roles the user's own settings would have accepted. A
  missing location, missing salary, or missing date **passes**.
- **`minSalaryIfPublished` only applies when a band is published.** The name is deliberate.
- **Remote inference here is coarse and string-based.** Do not reach for
  `RemoteTypeInference` or `LocationCriteria`: both expect extracted fields. Stage 1 matches
  tokens in `title` and `locationRaw` only. Getting this wrong in the permissive direction is
  cheap (one extraction); getting it wrong in the strict direction is invisible and permanent.

#### `SearchSource` (SwiftData model)

```swift
@Model public final class SearchSource {
    public var id: String
    public var kind: String            // JobSource.id
    public var label: String           // user-facing
    public var configJSON: String      // slug / org / tenant, per SourceConfiguration
    public var enabled: Bool
    public var intervalHours: Int
    public var lastRunAt: Date?
    public var nextRunAt: Date?
    public var lastStatus: String      // ok | empty | unreachable | rateLimited
    public var lastError: String?
    public var consecutiveEmptyRuns: Int
    public var lastFoundCount: Int
    public var lastPassedCount: Int
    public var createdAt: Date
    public var updatedAt: Date
}
```

`consecutiveEmptyRuns` is the whole point of Design constraint 4. Three consecutive `empty`
runs is the signal that a board migrated. It must reach the UI.

> **Do not overload the existing `Site` model.** `Site` is a human-review reminder with its
> own semantics (`SiteReview`, `SiteReviewBucket`, `state`). Discovery has different fields,
> a different cadence, and a machine consumer. Stage 5 offers a migration path for users who
> want a `Site` promoted to a `SearchSource`.

#### `DiscoveryLedger`

Cross-run dedup keyed on `atsPostingID`. Without it every sweep re-ingests the same board.

`DuplicateDetector` already prevents duplicate *jobs*, but it runs inside `ingestCapture` —
too late. A sweep that reaches ingest for 6,000 already-known postings does 6,000 redundant
hashes and DB round-trips every hour. The ledger short-circuits before that.

It must record postings that **passed and were ingested** *and* postings that were **rejected
by stage 1**, with the criteria hash. Recording rejections is what stops the sweep from
re-evaluating the same 5,900 rejects hourly; storing the criteria hash alongside is what lets
a criteria change correctly re-evaluate them. Persist it — unlike `AvailabilityBacklog`, this
must survive relaunch or every restart re-floods the queue.

---

## Two-stage filtering

| | Stage 1 — `DiscoveryCriteria` | Stage 2 — `JobRequirements` |
|---|---|---|
| Runs | Before ingest, on every swept row | After extraction, existing behaviour |
| Cost | Zero — string/number only | One LLM extraction + scoring |
| Input | Raw ATS fields | Extracted fields |
| Title | keyword include/exclude | — |
| Location | token match on `locationRaw` | `LocationCriteria` on extracted remote mode |
| Salary | only if the ATS published a band | `minSalary` against extracted band |
| Fit | **not evaluated — no score exists yet** | `minFitScore` via `FitScorer` |
| On failure | Counted, ledgered, not stored | Job exists, badged as not meeting criteria |

Stage 1 is a **conservative pre-filter**, not a reimplementation of stage 2. When the two
could disagree, stage 1 must pass. The user asked that only postings meeting all criteria be
scored; the fit criterion is unknowable pre-AI, so "all criteria" at stage 1 means *all
criteria that can be evaluated without AI*, and stage 2 finishes the job unchanged.

**Seed stage 1 from existing settings.** On first run, derive `DiscoveryCriteria` defaults
from `SettingsStore`: `locationAllowRemote/Hybrid/Onsite`, `preferredLocations`,
`remoteEligibilityRegions`, `minSalary` → `minSalaryIfPublished`. The user should recognise
their own configuration, not start from a blank form. Title keywords have no existing
equivalent and must be entered — that is the one genuinely new input.

---

## Settings UI

A new **Search** tab in `SettingsView`, alongside General / Jobs / AI / Data.

**Section 1 — What I'm looking for** (`DiscoveryCriteria`)
- Title keywords, any-of — token field. Placeholder shows the user's own likely terms.
- Title keywords, none-of — token field, prefilled `Intern, Junior, Graduate, Apprentice`.
- Work arrangement — three checkboxes, **bound to the existing** `locationAllowRemote` /
  `AllowHybrid` / `AllowOnsite`. Not new keys. Editing here edits the same setting.
- Locations allowed / denied — token fields seeded from `preferredLocations` and
  `remoteEligibilityRegions`.
- Minimum salary *when published* — reuses `minSalary`, labelled to make the conditional
  explicit.
- Maximum posting age — stepper, default 14 days, 0 = no limit.
- **Live preview:** "Against your last sweep, these criteria would have passed 41 of 6,168
  postings." Runs stage 1 over the ledger's retained raw rows. This is the single most
  valuable control in the tab — criteria that are silently too strict are the main way this
  feature fails, and the preview is what makes that visible before a week of empty runs.

**Section 2 — Where to look** (`SearchSource` list)
- Table: label · kind · every N hours · last run · found → passed · health.
- Health is a coloured dot: green `ok`, amber `empty` (with `consecutiveEmptyRuns`), red
  `unreachable` / `rateLimited`. Three ambers in a row shows an inline "this board may have
  moved" with a **Re-resolve** button (Stage 5).
- Add source sheet, driven by `SourceConfiguration`: pick a vendor, enter a company name,
  jobhunt probes for the board and shows a live job count before saving. Never save a source
  that resolved zero jobs without an explicit override — that is how dead slugs get in.
- Global toggle: **Automatic search — on/off**, plus "Run all now".

**Section 3 — What happened**
- Last sweep: N sources, M postings seen, K passed, J ingested.
- Rejection histogram by `DiscoveryRejectReason`. If 98% reject on `.title`, the user's
  keywords are wrong, and this is where they find that out.

---

## Staging

Each stage is independently shippable and independently useful.

### Stage 1 — Workday `listOpenRoles` *(smallest, highest value, no new architecture)*

`WorkdayProvider.listOpenRoles` returns `[]`. Workday is the single largest source of real
matches in the reference data (241 of 632 historical matches, 38%), and it is the only one of
the four existing vendors that cannot list a board.

Implement against the CXS search endpoint the availability check already knows how to build
(`AvailabilityChecker.workdayCXSQuery`), paginating as `providers/workday.mjs` does in the
career-ops repo — that file is the working reference, including its retry policy: 429 and 5xx
are transient and retried with backoff; other 4xx are not. Without retry a single 429 silently
truncates an entire tenant.

Ships value immediately with no scheduler, no new models, no UI: it improves the existing
"other open roles at this company" pane for every Workday job in the app.

**Done when:** a Workday job's detail pane lists that tenant's other open roles, and a tenant
that 429s yields a retry rather than a truncated list.

### Stage 2 — `JobSource`, `DiscoveredPosting`, `DiscoveryCriteria`, and the ledger

Pure model and logic layer. No UI, no scheduler, no network beyond the four adapters.

- Define the protocol and value types.
- Adapt the four existing providers to `JobSource` — thin wrappers over the `listOpenRoles`
  work that already exists, plus Stage 1's Workday addition.
- Implement `DiscoveryCriteria.evaluate` with exhaustive unit tests. **Test the absent-data
  rules explicitly**: no salary passes, no location passes, no date passes.
- Implement and persist `DiscoveryLedger`.
- A debug-menu command that sweeps one hard-coded board and prints found/passed/rejected
  counts by reason. No ingest yet.

**Done when:** the debug command reports plausible counts against a real board, and criteria
tests cover every `DiscoveryRejectReason` plus all three absent-data cases.

### Stage 3 — Ingest and the scheduler

- `SearchSource` model + `SearchSourceService` CRUD.
- `DiscoveryScheduler` as a `RuntimeTaskController` task, following `AvailabilityBacklog`'s
  pacing discipline: one source at a time, gentle, cancellable, and never blocking launch.
- Passing postings → `JobService.ingestCapture` with `userNote` recording source and sweep
  date. **No changes to `ingestCapture`.**
- Health recording on every run.
- Hard caps: max ingests per sweep (default 50) and per day (default 200), both surfaced in
  the UI. A misconfigured criteria set must not enqueue 6,000 extractions overnight. When a
  cap truncates a sweep, **say so** — a silent cap reads as "nothing more was found".

**Done when:** an enabled source ingests only postings that clear stage 1, a second sweep
ingests nothing new, and disabling automatic search stops all activity within one cycle.

### Stage 4 — Settings UI

The Search tab as specified, including the live preview and the rejection histogram. Until
this ships, Stage 3 is debug-only — do not enable automatic search by default before the user
can see and edit what it will do.

**Done when:** a new user can add a source, set criteria, see the preview count, run a sweep
manually, and read what happened.

### Stage 5 — Source resolution and health repair

- A company→board resolver probing the vendors in order, accepting a board only when it
  exists **and** lists ≥1 job. `discover-ats.mjs` in the career-ops repo is the working
  reference (12 vendors, ~1 day of probing logic per vendor family).
- The **Re-resolve** button on an amber source, offering the replacement board it found.
- Optional: promote a `Site` to a `SearchSource` when resolution succeeds.

This is what stops the feature rotting. In the reference system, 13 of 87 boards had migrated
and were silently returning nothing for weeks; re-resolution recovered 8 of them, one of which
went from 0 to 53 open roles.

**Done when:** an amber source can be repaired from the UI without editing anything by hand.

### Stage 6 — Market-wide sources *(optional; measure before building)*

`SourceConfiguration.marketWide` sources need no company: Remotli, HN Who-is-Hiring, The Muse,
4 Day Week, a16z speedrun.

**Be honest about the yield before spending the time.** Measured against the reference
system's real criteria, 15 aggregators scanned 5,261 postings and surfaced 12 matches — a
0.23% hit rate — and the largest remote boards (RemoteOK, Remotive, WeWorkRemotely,
Himalayas) returned **zero** program/product roles that day. Of the 12, nine came from just
two sources (Remotli 6, HN 3). Build those two, measure for a fortnight, and only then decide
about the rest.

### Explicitly out of scope

- **The 29k-board reverse-ATS sweep.** It depends on an external company directory refreshed
  weekly, plus DNS pacing, resolver-outage detection, per-vendor concurrency caps, and
  checkpoint/resume. career-ops already does this well and bridges results in. Duplicating it
  is months of work for no new coverage.
- **The other ~65 career-ops providers.** Roughly 20 are regional (DACH, Nordics, Poland, SE
  Asia), ~10 are single-employer, and **14 are HTML parsers** whose maintenance career-ops
  amortises across all its users and jobhunt would carry alone.
- **Auto-apply.** Not now, not later.

---

## Risks

| Risk | Mitigation |
|---|---|
| Criteria too strict → silent zero-yield | Live preview in settings; rejection histogram; amber health on empty runs |
| Criteria too loose → extraction cost blowout | Per-sweep and per-day ingest caps, surfaced, never silent |
| Stage 1 rejects what stage 2 would accept | Absent data always passes; stage 1 is a documented conservative subset |
| Board migrates, source goes quiet | `consecutiveEmptyRuns` → amber → Re-resolve (Stage 5) |
| Vendor rate-limits a burst | Sequential sweeps, per-vendor pacing, retry 429/5xx only, `rateLimited` health |
| Ledger growth | Retain raw rows only for the most recent sweep per source (enough for the preview); keep IDs indefinitely |
| Duplicate work vs the career-ops bridge | Both call `ingestCapture`; `DuplicateDetector` already resolves collisions |

## Open questions

1. Should a discovered job land in `new` or in a distinct `discovered` status? `new` reuses
   the existing triage flow; a separate status makes provenance visible but touches every
   status-handling site. Recommendation: `new` plus a `user_note` marker, revisit if volume
   makes triage noisy.
2. Should stage-1 rejects be inspectable in the UI ("show me what was filtered out")? Useful
   for tuning, but it is a second list of things that are not jobs. Recommendation: the
   histogram only, until asked for.
3. Does the fit floor belong in discovery at all, i.e. should a scored job that misses
   `minFitScore` be auto-archived? Recommendation: no — that is triage, and it already works.
