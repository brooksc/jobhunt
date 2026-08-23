# Automatic Job Search — Implementation Spec

Jobhunt today is a **pull** system: a posting exists in the app because a human put it there,
through the extension, the MCP bridge, or a paste. Discovery is a `Site` row with a
`nextReviewAt` date whose only effect is to remind you to go look yourself.

This spec turns jobhunt into a **push** system: it finds the postings, applies the user's
requirements with zero AI, and only then drops survivors into `new` where the existing
extraction and fit-scoring pipeline treats them exactly like any other capture.

It is written to be implemented in milestones, each shippable on its own.

**Provenance.** The design is a port of the working scanner in `~/git/career-ops`, which the
user runs daily. Where this document cites that repo it cites a real file and a real behaviour;
the mechanisms it borrows are ones that already survived contact with live ATS endpoints. Where
jobhunt's own code is cited, the file and line have been checked against the tree as of
2026-08-22. **career-ops is not a dependency** — nothing here calls it, imports it, or requires
it to be installed. It is the reference implementation the Swift is derived from.

---

## Design constraints

These are load-bearing. Everything below follows from them.

1. **No AI before the criteria gate.** A board sweep returns thousands of postings. Extracting
   them all would cost more than the feature is worth and would fill the app with noise.
   Every filter that runs before ingest must be pure string/number work. AI enters only
   after a posting has cleared every configured requirement, and then through the *existing*
   path — `ingestCapture` → extraction queue → `FitScorer` — with no parallel scoring code.
2. **No per-posting network request before the gate.** This is the sharper form of constraint 1
   and it is what career-ops calls "zero-token by design": a provider populates `description`
   **only when the list payload carries it for free** (`providers/README.md`). One extra HTTP
   round trip per swept posting is 6,000 requests an hour at real board sizes, which is both
   slow and rude. Hydration happens *after* the gate, on survivors only — see
   "Hydration" below.
3. **Reuse the requirements the app already has — by seeding, not by aliasing.** The user has
   configured location, remote arrangement, salary floor and fit floor. Discovery should start
   from those values so the user recognises their own configuration. It must **not write back
   to the same settings keys**: those keys drive `JobRequirements`, which badges every job in
   the app, so "let me widen the search a bit" would silently re-evaluate hundreds of existing
   jobs. Seed on first use, then own the copy.
4. **Discovery must never expire or mutate an existing job.** It only ever creates.
5. **A silent source is the enemy.** A board that migrates ATS does not error — it returns
   zero rows forever. Every source carries health state and says so in the UI.
6. **Nothing auto-applies.** This finds and files. It never contacts an employer.

---

## What already exists (and what it means)

The expensive parts are built. This is mostly wiring.

| Capability | Where | State |
|---|---|---|
| Board listing, Greenhouse | `GreenhouseJobBoard.listOpenRoles` (`GreenhouseJobBoard.swift:113`) | **Done** |
| Board listing, Lever | `LeverProvider.listOpenRoles` (`ATSProviders.swift:110`) | **Done** |
| Board listing, Ashby | `AshbyProvider.listOpenRoles` (`ATSProviders.swift:220`) | **Done** |
| Board listing, Workday | `WorkdayProvider.listOpenRoles` (`ATSProviders.swift:314`) | **Returns `[]` — the one real vendor gap** |
| Posting body fetch | `ATSProvider.fetchPosting` → `ATSPosting.contentPlain` | Done for GH/Lever/Ashby; **Workday returns `nil`** |
| Provider abstraction | `ATSProvider` (`ATSProvider.swift:49`) | Done, but posting-centric (see below) |
| Workday CXS endpoint derivation | `AvailabilityChecker.workdayCXSQuery` (`AvailabilityChecker.swift:477`) | Done — tenant/site/reqId from a URL |
| HTTP response caching | `ATSResponseCache` | Done |
| Cross-run dedup key | `DuplicateDetector.atsPostingID` (`DuplicateDetector.swift:373`) — `gh:123`, `wd:tenant:req`, `lever:co:uuid` | Done; **returns `nil` for non-ATS hosts** |
| Relevance ranking of a board | `OpenRoleRelevance` | Done |
| Scheduler skeleton | `Site.intervalDays`, `Site.nextReviewAt`, `SiteService` | Fields exist; fire a reminder, not a fetch |
| Background sweep precedent | `AvailabilityBacklog`, `RuntimeTaskController` | Done — copy this shape |
| Requirements evaluation | `JobRequirements`, `LocationCriteria`, `JobFilterRules` | Done, but **post-extraction** (see below) |
| Seniority inference | `SeniorityLevel` + inference (`SeniorityLevel.swift`) | Done — usable on a bare title |
| Criteria snapshot pattern | `SavedSearchCriteria` (`SavedSearchCriteria.swift:46`) — Sendable, off-main-actor, unit-testable | Done — copy this shape |
| Settings surface | `SettingsStore`, `JobsSettingsTab` | Done; needs new keys + a tab |
| Ingest | `JobService.ingestCapture` (`JobService.swift:97`) | Done; discovery calls it unchanged — **but see the text requirement** |

### The three facts that shape the architecture

**`ATSProvider` is posting-centric.** Every method takes an `atsID` identifying one posting
on one company's board: `handles(atsID:)`, `fetchPosting(atsID:…)`, `listOpenRoles(atsID:…)`.
Even the listing call resolves the board *through* a known posting. That is correct for
refresh and availability, but discovery has no posting to start from — it starts from a
company. Discovery therefore needs a sibling protocol, not more conformances to this one.

**`ingestCapture` requires body text.** `JobService.swift:118–125` throws `missingPageTitle`
when the title is blank and `missingText` when *both* `selectedText` and `visibleText` are
empty. Nothing downstream fetches a URL to obtain a description — a browser capture arrives
with the body already attached. Greenhouse's list endpoint returns only
`id, title, location, absolute_url, updated_at, first_published` (`GreenhouseJobBoard.swift:33`),
and Workday's CXS list is similarly body-free. **So a swept posting cannot be ingested as-is.**
This is the single largest correction to the previous draft, and it is why the pipeline has a
hydration step between the gate and ingest.

**`JobRequirements` cannot be the pre-AI gate.** It evaluates location, salary floor **and
fit floor**, and fit requires a score that only exists post-extraction. `LocationCriteria` is
likewise computed from the *extracted* remote mode. Both consume extracted fields; a sweep has
only raw ATS fields. So the gate runs in two stages against two different data shapes, and the
pre-AI stage must be built to consume raw board rows.

This is not duplication if it is done right: gate A is a deliberately conservative subset of
gate B, and gate B remains the authority. See "Two-gate filtering" below.

---

## Architecture

```
                      ┌──────────────────────────────────────────┐
   SearchSource       │ DiscoveryScheduler (RuntimeTaskController)│
   rows in SwiftData  │ wakes on the earliest nextRunAt           │
                      └───────────────────┬──────────────────────┘
                                          │
                       ┌──────────────────▼──────────────────┐
                       │  JobSource.fetchRecent(since:)      │  ← new protocol
                       │  Greenhouse│Lever│Ashby│Workday     │
                       └──────────────────┬──────────────────┘
                                          │  [DiscoveredPosting]  (raw, no AI, no per-row fetch)
                       ┌──────────────────▼──────────────────┐
                       │  GATE A — DiscoveryCriteria.evaluate│  ← zero AI, zero network, pure
                       │  title kw · location · seniority ·  │
                       │  salary-if-published · freshness    │
                       └──────────────────┬──────────────────┘
                          rejected ───────┴─────── passed
                       (counted + ledgered)        │
                       ┌─────────────────────────────▼───────┐
                       │  DiscoveryLedger.isKnown(key)       │  ← dedup across runs
                       └─────────────────────────────┬───────┘
                                                 new │  (already capped here)
                       ┌─────────────────────────────▼───────┐
                       │  HYDRATE — ATSProvider.fetchPosting │  ← 1 request per SURVIVOR only
                       │  → ATSPosting.contentPlain          │
                       └─────────────────────────────┬───────┘
                       ┌─────────────────────────────▼───────┐
                       │  JobService.ingestCapture(payload)  │  ← UNCHANGED
                       └─────────────────────────────┬───────┘
                       ┌─────────────────────────────▼───────┐
                       │  extraction queue → FitScorer →     │  ← GATE B, existing
                       │  JobRequirements (incl. fit floor)  │
                       └─────────────────────────────────────┘
```

### Hydration

Between the ledger and ingest, each surviving posting gets exactly one body fetch:

1. If the list payload already carried a description (Ashby does; Lever's board payload does),
   use it. No request.
2. Otherwise call `provider.fetchPosting(atsID:company:urlString:session:)` and use
   `ATSPosting.contentPlain` as `visibleText`.
3. If hydration fails or returns an empty body, **do not ingest** — record the posting in the
   ledger as `hydrationFailed` and count it. A job row whose description is its own title is
   worse than no row: extraction will produce garbage and fit-scoring will score the garbage.

The cost is bounded by the ingest cap, not by board size: at most 50 hydration requests per
sweep. It is also why the cap exists at the ledger boundary rather than after ingest.

**Workday needs its own hydration path.** `WorkdayProvider.fetchPosting` returns `nil`
(`ATSProviders.swift:308`). The CXS list gives `externalPath`; the per-posting body comes from
`GET /wday/cxs/{tenant}/{site}{externalPath}`.

**Verified 2026-08-22** against a live tenant (`23andme.wd5`), both calls, HTTP 200. The detail
payload carries more than the list does, and two fields are worth having:

| Field | Value seen |
|---|---|
| `jobPostingInfo.jobDescription` | full JD as HTML — this is the hydration body |
| `jobPostingInfo.startDate` | `"2026-08-03"` — an **absolute** date, where the list has only `"Posted 19 Days Ago"` |
| `jobPostingInfo.jobRequisitionLocation.country.alpha2Code` | `"US"` — structured country |
| `jobPostingInfo.timeType`, `.jobReqId`, `.externalUrl` | full/part time, req id, canonical URL |

`startDate` and `alpha2Code` exist **only on the detail endpoint**, so they are post-gate: they
can enrich the ingested capture, but gate A still has to work off the relative `postedOn` label
and `locationsText`/URL hint.

### New types

#### `JobSource` (protocol)

```swift
/// A source that can be swept for postings without knowing about any specific posting.
/// Sibling to `ATSProvider`, which is posting-centric and stays as-is.
public protocol JobSource: Sendable {
    /// Stable identifier persisted on `SearchSource.kind` (e.g. "greenhouse").
    var id: String { get }
    /// Vendor's own name, shown to the user.
    var displayName: String { get }
    /// What this source needs configured. Drives the add-source form.
    var configuration: SourceConfiguration { get }

    /// Every posting this source currently lists, newest first where the vendor supports it.
    ///
    /// `since` is a hint: sources that can stop paginating early should (Workday sorts
    /// newest-first and can); others return everything and let the caller drop stale rows.
    /// Must NOT issue a request per posting — see design constraint 2.
    ///
    /// Throws `SourceError` so health can distinguish "unreachable" from "reachable and
    /// empty" — Design constraint 5. An empty array is a *successful* answer meaning the
    /// board listed nothing, and it must never be conflated with a failure.
    func fetchRecent(
        config: SourceConfig, since: Date?, session: URLSession
    ) async throws -> [DiscoveredPosting]
}

public enum SourceConfiguration: Sendable {
    /// Needs a company board slug — Greenhouse, Lever, Ashby.
    case perCompany(slugHint: String)
    /// Needs tenant + instance + site, which cannot be derived from a company name.
    case workdayTenant
    /// Whole-market firehose with no company — Remotli, HN Who-is-Hiring.
    case marketWide
}

public enum SourceError: Error, Sendable {
    case unreachable(String)     // DNS, TLS, timeout, 5xx after retries
    case rateLimited(retryAfter: TimeInterval?)
    case malformedResponse(String)
    case misconfigured(String)   // slug doesn't parse, tenant URL isn't Workday-shaped
}
```

#### `DiscoveredPosting`

The raw board row, before any AI and before any body fetch.

```swift
public struct DiscoveredPosting: Sendable, Equatable {
    /// `DuplicateDetector.atsPostingID(urlString:)` where it resolves, else
    /// `"url:" + URLNormalizer.dedupKey(url)`. Never optional: the ledger needs a key for
    /// every row, and `atsPostingID` returns nil for any host it doesn't recognise.
    public let dedupKey: String
    public let url: String
    public let title: String
    public let company: String?
    public let locationRaw: String?   // vendor's own string; NOT a parsed RemoteType
    public let departments: [String]
    public let firstPublished: Date?
    public let updatedAt: Date?
    public let salaryMinPublished: Int?   // only when the ATS publishes a band
    public let salaryMaxPublished: Int?
    public let salaryCurrency: String?
    public let descriptionPlain: String?  // ONLY when the list payload included it for free
    public let sourceID: String
}
```

#### What each vendor actually publishes at list time

This table is the honest version of the filter capabilities. Gate A can only evaluate a
criterion where the vendor supplies the field, and "absent data passes" means a missing field
makes that criterion a **no-op for that vendor** — not a rejection.

| Field | Greenhouse | Lever | Ashby | Workday |
|---|---|---|---|---|
| title | ✅ | ✅ | ✅ | ✅ |
| location string | ✅ | ✅ | ✅ | ⚠️ often `"5 Locations"` — recover from URL path |
| posted date | ✅ `first_published` | ⚠️ `createdAt` | ⚠️ sometimes | ⚠️ relative label only (`"Posted 5 Days Ago"`), unbounded above 30 days |
| salary band | ❌ | ❌ | ⚠️ sometimes | ❌ |
| description | ❌ | ✅ | ✅ | ❌ |
| departments | ❌ | ✅ | ✅ | ❌ |

**Consequence to state plainly:** for Greenhouse — the most common vendor — gate A reduces to
*title keywords + location string*, with salary and age no-ops. That is fine, and it is still
the difference between 6,000 extractions and 40. But it means the title filter is carrying most
of the load, which is why its matching semantics (below) matter more than they look, and why the
live preview is not optional.

### Measured selectivity — the user's own 65 runs

From `~/git/career-ops/data/scan-runs.tsv`, aggregated 2026-08-22 over every completed run
(the config is 156 tracked companies, 6 positive title keywords, 27 negative, 1 `allow` /
14 `always_allow` / 39 `block` location entries):

| | Postings | Share of swept |
|---|---|---|
| Swept | 400,616 | — |
| Rejected on **title** | 384,444 | **95.96%** |
| Rejected on **location** | 15,073 | 3.76% |
| Rejected on salary / age / content / tier | 0 | 0% — *not configured*, so untested |
| Dropped as already-seen | 958 | 0.24% |
| **Newly added** | **141** | **0.035%** |

Four things follow, and they change the build order:

1. **Title is the gate.** 96% of the reduction. Everything about its matching semantics — word
   boundaries on `TPM`, the 27 negative keywords — is load-bearing, and everything else is a
   rounding error by comparison.
2. **Salary, age and content filters have never fired in production.** They are not proven
   useless, they are unconfigured. Build them last, or not at all until asked.
3. **`block_hard` is unused** (0 entries) — ship three location tiers, keep the fourth in the
   model only if it's free.
4. **The real yield is ~2 new postings a day** (141 over 65 runs). The proposed caps of 50 per
   sweep / 200 per day are two orders of magnitude above observed reality. They are still worth
   having as a runaway guard, but they should be understood as a circuit breaker, not a budget —
   and the cost table below is a worst case that will not be approached.

#### `DiscoveryCriteria` — gate A

Modelled on `SavedSearchCriteria`: a `Sendable`, `Hashable` value decoupled from SwiftData so
matching runs off the main actor and is unit-testable in isolation.

The matching semantics below are not invented here. Each one is a fix career-ops made after a
silent miss in production; the comment in `scan.mjs` naming the failure is cited so the reason
survives the port.

```swift
public struct DiscoveryCriteria: Sendable, Hashable {
    // Title
    public var titleIncludeAny: [String]   // ≥1 must match; empty = no title requirement
    public var titleExcludeAny: [String]   // any match rejects
    // Location, four tiers — evaluated in this order
    public var locationBlockHard: [String] // rejects even if alwaysAllow matches
    public var locationAlwaysAllow: [String]
    public var locationBlock: [String]
    public var locationAllow: [String]     // empty = any location passes
    // Other
    public var minSalaryIfPublished: Int   // 0 disables
    public var maxSalaryIfPublished: Int   // 0 disables
    public var maxAgeDays: Int             // 0 disables
    public var excludeSeniority: [SeniorityLevel]

    public func evaluate(_ p: DiscoveredPosting, now: Date) -> DiscoveryVerdict
}

public enum DiscoveryVerdict: Sendable, Equatable {
    case pass
    case reject(DiscoveryRejectReason)  // .title .location .seniority .salary .stale
}
```

**Rule 1 — absent data never rejects.** A posting with no published band is unknown, not
disqualified. This is the rule `JobRequirements` already states ("Absent data never fails a
requirement… lands in `.notStated`"), and career-ops's filters state independently
("don't penalize missing data", `scan.mjs:~205`). Gate A must not be stricter than gate B or it
permanently hides roles the user's own settings would accept. Missing location, missing salary,
missing date, unparseable date: **pass**.

**Rule 2 — short keywords match on word boundaries.** A 2–3 letter all-letter keyword is
anchored (`\bcoo\b`), everything else is a plain case-insensitive substring
(`scan.mjs:compileKeyword`). Without this, `COO` matches "Coordinator" and `AI` matches
"Maintenance" — a silent flood, and the summary shows one "passed" count that cannot tell a
tuned filter from a leaking one.

**Rule 3 — location keywords are *always* word-boundary matched**, using lookarounds rather
than `\b` so keywords with leading/trailing punctuation still anchor
(`scan.mjs:compileLocationKeyword`). The motivating bug is worth keeping in the Swift comment:
blocking `india` also rejected *Indian Head, MD*, *Indiana* and *Indianapolis* — real US
locations, dropped from every scan, invisibly. Same class: `china` swallows *Chinatown*.

**Rule 4 — four location tiers, in this order:** `blockHard` → `alwaysAllow` → `block` →
`allow`. Multi-location postings are why: "Stockholm · London · Madrid" must not die on a
London block entry, so `alwaysAllow` beats `block`. But "Porto Alegre, Rio Grande do Sul,
Brazil" must not be rescued by an `alwaysAllow` entry for *Porto*, so `blockHard` exists as the
one tier `alwaysAllow` cannot override. Opt-in and additive: a criteria set with no `blockHard`
behaves exactly as three tiers.

**Rule 5 — recover the location from the URL when the vendor rolls it up.** Workday reports
`"5 Locations"` while the canonical URL still names the primary one
(`…/job/Hyderabad-Telangana-India/Network-Engineer_R-65193-1`). Read **only** the path segment
after `/job/`, never the whole URL — scanning the full URL matches company slugs and ATS
subdomains by accident. `scan.mjs:locationHintFromUrl`.

**Rule 6 — a remote marker in the title can widen `allow`, never `block`.** Several ATSs report
the hiring office as the location even when the role is remote and say "Remote" in the title
instead. Measured on one live tenant: 14 matching-family postings, 0 passed `allow`, 5 said
Remote in the title. So a title remote-marker is a last-resort rescue evaluated **after**
`block`, meaning "Program Manager - Remote" in a blocked location stays rejected. The marker
must be unambiguous — `remote` followed by end-of-string, a non-letter, or ` in …` — or
"Remote Sensing Program Manager" (an on-site GIS role) sails through. And a negation anywhere
in the title (`non-remote`, `not remote`, including non-ASCII dashes) disqualifies the rescue.
`scan.mjs:REMOTE_TITLE_RE`, `REMOTE_NEGATED_RE`.

**Rule 7 — salary is a range *overlap*, not a floor.** Reject only when the posting's band lies
entirely outside the user's range. Currency mismatch rejects only when **both** currencies are
known. `scan.mjs:buildSalaryFilter`. `minSalaryIfPublished` is named for what it does: absent
band, no opinion.

**Rule 8 — coarse, string-based remote inference only.** Do not reach for `RemoteTypeInference`
or `LocationCriteria` here; both expect extracted fields. Getting this wrong in the permissive
direction costs one extraction; getting it wrong in the strict direction is invisible and
permanent.

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
    public var lastStatus: String      // ok | empty | unreachable | rateLimited | truncated
    public var lastError: String?
    public var consecutiveEmptyRuns: Int
    public var lastFoundCount: Int
    public var lastPassedCount: Int
    public var lastIngestedCount: Int
    public var createdAt: Date
    public var updatedAt: Date
}
```

`consecutiveEmptyRuns` is the whole point of Design constraint 5. Three consecutive `empty`
runs is the signal that a board migrated. It must reach the UI. `truncated` is its own status:
a sweep that stopped on a rate limit found *some* jobs and must not be recorded as healthy.

> **Do not overload the existing `Site` model.** `Site` is a human-review reminder with its own
> semantics (`SiteReview`, `SiteReviewBucket`, `state`) and a `@Attribute(.unique) origin`.
> Discovery has different fields, a different cadence and a machine consumer. M5 offers a
> migration path for users who want a `Site` promoted to a `SearchSource`.

#### `DiscoveryLedger`

Cross-run dedup keyed on `DiscoveredPosting.dedupKey`. Without it every sweep re-ingests the
same board.

`DuplicateDetector` already prevents duplicate *jobs*, but it runs inside `ingestCapture` — too
late, and after hydration has already spent a request. A sweep that reaches ingest for 6,000
already-known postings does 6,000 redundant hashes and DB round-trips every hour.

It records every posting the sweep saw, with its verdict and the criteria hash:

```swift
@Model public final class DiscoveryLedgerEntry {
    @Attribute(.unique) public var dedupKey: String
    public var sourceID: String
    public var verdictRaw: String       // pass | reject:<reason> | ingested | hydrationFailed
    public var criteriaHash: Int        // DiscoveryCriteria.hashValue at evaluation time
    public var firstSeenAt: Date
    public var lastSeenAt: Date
    /// Raw row, JSON-encoded, retained only for the most recent sweep per source — the live
    /// preview replays gate A over these without re-fetching. Nil once superseded.
    public var rawJSON: String?
}
```

Recording rejections is what stops the sweep re-evaluating the same 5,900 rejects hourly.
Storing `criteriaHash` alongside is what lets a criteria change correctly re-evaluate them: an
entry whose hash differs from the current criteria is re-evaluated, one that matches is skipped.

It is a SwiftData model like everything else, written through `BackgroundStore` — the store is
single-writer, so the scheduler must not open its own context. Pruning: `rawJSON` is cleared for
entries superseded by a newer sweep of the same source; entries themselves are kept
indefinitely (a key is ~60 bytes, and forgetting one means re-ingesting a job the user already
archived).

This is the one place the CLAUDE.md "don't optimise for scale this app won't reach" convention
does **not** apply. The rest of jobhunt handles a few hundred jobs; a full Workday tenant is
3,000 rows in one response and career-ops has seen tenants of 23,000.

---

## Two-gate filtering

| | Gate A — `DiscoveryCriteria` | Gate B — `JobRequirements` |
|---|---|---|
| Runs | Before hydration, on every swept row | After extraction, existing behaviour |
| Cost | Zero — string/number, no network | 1 body fetch + 1 LLM extraction + scoring |
| Input | Raw ATS list fields | Extracted fields |
| Title | keyword include/exclude | — |
| Location | 4-tier token match on `locationRaw` + URL hint | `LocationCriteria` on extracted remote mode |
| Salary | range overlap, only if the ATS published a band | `minSalary` against extracted band |
| Fit | **not evaluated — no score exists yet** | `minFitScore` via `FitScorer` |
| On failure | Counted, ledgered, not stored | Job exists, badged as not meeting criteria |

Gate A is a **conservative pre-filter**, not a reimplementation of gate B. When the two could
disagree, gate A must pass. The user asked that only postings meeting all criteria be scored;
the fit criterion is unknowable pre-AI, so "all criteria" at gate A means *all criteria that can
be evaluated without AI*, and gate B finishes the job unchanged.

**Seed gate A from existing settings, once.** On first use, derive `DiscoveryCriteria` defaults
from `SettingsStore`: `preferredLocations` → `locationAllow`, `remoteEligibilityRegions` →
`locationAlwaysAllow`, `minSalary` → `minSalaryIfPublished`, `locationAllowRemote/Hybrid/Onsite`
→ the initial remote handling. Then **store the copy under its own keys**
(`discovery_*`) — see Design constraint 3. Title keywords have no existing equivalent and must
be entered; that is the one genuinely new input, and it is also the one doing most of the work.

---

## HTTP discipline

Every one of these is a live-fire lesson from career-ops. They are cheap to build in and
expensive to retrofit.

- **Retry 429, 5xx and transport errors only.** Any other 4xx is the server saying the request
  is wrong; retrying burns the budget. Exponential backoff with jitter, and honour
  `Retry-After` **clamped** so a hostile or misconfigured `Retry-After: 86400` cannot stall a
  sweep. `providers/_http.mjs:isRetryableError`, `withRetry`.
  Without retry, a single 429 silently truncates an entire tenant — career-ops measured a
  3,383-posting tenant reduced to 20.
- **Carry the attempt count on the error** so a truncation log says how many requests were
  actually made rather than assuming the full budget.
- **`redirect: .never` / refuse redirects, and validate the host before fetching.** Every
  career-ops provider passes `redirect: 'error'` so a server-side redirect cannot be used for
  SSRF. jobhunt fetches user-configured URLs from a desktop app on the user's LAN; this matters
  more here, not less.
- **Consume the body inside the timeout window.** A server that sends headers and then stalls
  the body hangs the caller forever with the abort timer already cleared — this froze
  career-ops's full sweeps silently.
- **Pace within a source, sequentially.** 250 ms between pages of one tenant. Parallel requests
  to a single board have no upside and trip WAF rate limiting. Sequential also means a mid-run
  failure keeps the pages already gathered instead of discarding the batch.
- **Some tenants need browser-like headers.** Workday tenants behind Cloudflare bot management
  500 a request that lacks a real UA, `accept-language`, and matching `origin`/`referer`. Send
  them.
- **A cap that truncates must say so.** Both in the log and in `SearchSource.lastStatus`. A
  silent cap reads as "nothing more was found".

---

## Settings UI

A new **Search** tab in `SettingsView`, alongside General / Jobs / AI / Data.

**Section 1 — What I'm looking for** (`DiscoveryCriteria`)
- Title keywords, any-of — token field. Seeded empty; the placeholder shows likely terms.
- Title keywords, none-of — token field, prefilled `Intern, Junior, Graduate, Apprentice`.
- Work arrangement — three checkboxes, **seeded from** `locationAllowRemote/Hybrid/Onsite` and
  stored under `discovery_*`. Editing here does not re-badge existing jobs.
- Locations: allow / always-allow / block / block-hard — four token fields. The last two are
  behind a "More" disclosure; most users need two tiers, and the four-tier order is only
  explicable next to a multi-location example, which the help text should give.
- Salary range *when published* — seeded from `minSalary`, labelled to make the conditional
  explicit.
- Maximum posting age — stepper, default 14 days, 0 = no limit.
- **Live preview:** "Against your last sweep, these criteria would have passed 41 of 6,168
  postings." Replays gate A over the ledger's retained `rawJSON`. This is the single most
  valuable control in the tab — criteria that are silently too strict are the main way this
  feature fails, and the preview is what makes that visible before a week of empty runs.

**Section 2 — Where to look** (`SearchSource` list)
- Table: label · kind · every N hours · last run · found → passed → ingested · health.
- Health is a coloured dot: green `ok`, amber `empty` (with `consecutiveEmptyRuns`), red
  `unreachable` / `rateLimited`, amber `truncated`. Three ambers in a row shows an inline
  "this board may have moved" with a **Re-resolve** button (M5).
- Add-source sheet driven by `SourceConfiguration`: pick a vendor, enter a company name,
  jobhunt probes for the board and shows a live job count before saving. **Never save a source
  that resolved zero jobs without an explicit override** — that is how dead slugs get in.
- Workday gets its own form: tenant URL, not company name. It cannot be resolved from a name
  (see M5).
- Global toggle: **Automatic search — on/off**, plus "Run all now".

**Section 3 — What happened**
- Last sweep: N sources, M postings seen, K passed gate A, H hydrated, J ingested.
- Rejection histogram by `DiscoveryRejectReason`. If 98% reject on `.title`, the user's
  keywords are wrong, and this is where they find that out.
- Cap notices: "stopped at the 50-per-sweep cap — 130 more passed" must be visible here, not
  only in a log.

---

## Cost

The caps are the running cost of the feature, so state the arithmetic rather than picking round
numbers. Per ingested posting: one hydration request (free), one extraction (≈4–8k input
tokens on a full JD, ≈500 output), one fit score (≈3–6k input). At the default caps:

| | Per sweep (50) | Per day (200) |
|---|---|---|
| LLM calls | 100 | 400 |
| Rough input tokens | ~0.6 M | ~2.4 M |

At Haiku-class pricing that is cents a day; at a frontier model it is not. **The default caps
should be set from the user's configured extraction model, and the Search tab should show the
estimate next to the cap steppers.** A cap the user cannot price is a cap they cannot choose.

**But this is a worst case that measurement says won't happen.** The observed yield is ~2
postings a day (see "Measured selectivity"), i.e. ~4 LLM calls — under a cent at any model.
The caps exist for the misconfiguration case: an empty `titleIncludeAny` turns a 15,000-posting
sweep into 15,000 extractions, and that is the scenario the circuit breaker is for.

---

## Milestones

Each is independently shippable and independently useful. (Renamed M1–M6 — the previous draft
used "Stage" for both pipeline stages and shipping stages, which made "Stage 1" ambiguous.)

> **Status as of 2026-08-22: M1–M5 are built and on `main`. M6 is not.**
>
> End-to-end verification against GitLab's live Greenhouse board (204 open roles), with a
> program/product-manager criteria set:
>
> | | |
> |---|---|
> | Listed by the board | 204 |
> | Rejected on title | 195 (95.6%) |
> | Passed gate A | 9 |
> | Hydrated and ingested | 9, bodies 6.0–11.7 KB |
> | Hydration failures | 0 |
> | **Second sweep, unchanged board** | **204 found, 0 ingested** |
>
> The 95.6% title rejection matches the 95.96% measured across career-ops' 65 historical runs,
> which is the closest thing available to independent confirmation that the port behaves like the
> scanner it replaces. Workday's two CXS endpoints were separately verified against a live tenant.
>
> Resolution (M5) verified live from company names alone: GitLab (204 roles), Anthropic (517) and
> Stripe (575) resolve to Greenhouse; Ramp (136) and Notion (128) to Ashby. Netflix correctly
> reports no board — it uses none of the three — as does a made-up company name.

### M1 — Workday listing and body fetch ✅ *shipped*

`WorkdayProvider.listOpenRoles` returns `[]` and `fetchPosting` returns `nil`. Workday is the
single largest source of real matches in the reference data (241 of 632 historical matches,
38%), and it is the only one of the four existing vendors that can do neither.

`AvailabilityChecker.workdayCXSQuery` already derives tenant/site/reqId from a posting URL. The
listing call is `POST https://{tenant}.{instance}.myworkdayjobs.com/wday/cxs/{tenant}/{site}/jobs`
with body `{"limit":20,"offset":N,"searchText":"","appliedFacets":{}}`. Port
`~/git/career-ops/providers/workday.mjs` — it is 328 lines and every non-obvious line is a fix
for something observed live:

- **Pagination**: page size 20, `total` from the first response, default cap 100 pages, hard cap
  1500. Sequential with a 250 ms inter-page delay.
- **`total` can lie.** Workday's backend sometimes reports exactly `maxPages × pageSize` when
  the real count is far higher (dickssportinggoods: `total=2000`, public site lists 7,120; the
  offsets past 2000 return page 0 again). Flag it, don't try to defeat it.
- **Retry `{retries: 3}`** on 429/5xx/transport. Truncate the tenant with a warning and keep the
  pages already fetched rather than discarding the batch.
- **Dates are relative labels only**: `"Posted Today"`, `"Posted Yesterday"`,
  `"Posted N Days Ago"`, and `"Posted 30+ Days Ago"` — the last is unbounded and must map to
  *no date*, not to 30 days.
- **Early-stop**: postings come newest-first, so stop paginating once a page's oldest
  *unambiguously dated* posting is past the `since` window, with a 2-day margin for the ~1 day
  of ordering jitter real tenants show. Pages of entirely undated postings never trigger it.
- **Location fallback** from the `/job/{Location-Slug}/` path segment when `locationsText` is a
  rollup.
- **Browser-like headers** (real UA, `accept-language`, `origin`, `referer`) — some tenants sit
  behind Cloudflare bot management that 500s anything else.
- **Body fetch** (no career-ops precedent — verify first, see "Hydration"):
  `GET /wday/cxs/{tenant}/{site}{externalPath}` → `jobPostingInfo.jobDescription` (HTML; strip
  to plain text through the existing cleaner).

Ships value immediately with no scheduler, no new models, no UI: it makes "other open roles at
this company" and description-refresh work for every Workday job already in the app.

**Done when:** a Workday job's detail pane lists that tenant's other open roles; a refresh pulls
that posting's description; a tenant that 429s yields a retried, explicitly-truncated list
rather than a silent short one; and `pageIsPastWindow`, `parsePostedOn` and the location
fallback each have unit tests over recorded fixtures.

### M2 — `JobSource`, `DiscoveredPosting`, `DiscoveryCriteria`, the ledger ✅ *shipped*

Pure model and logic layer. No UI, no scheduler, no network beyond the four adapters.

- Define the protocol and value types.
- Adapt the four existing providers to `JobSource` — thin wrappers over the `listOpenRoles` work
  that already exists, plus M1's Workday addition.
- Implement `DiscoveryCriteria.evaluate` with exhaustive unit tests. **Test rules 1–7
  explicitly**, each with the failure it prevents named in the test: no salary passes, no
  location passes, no date passes, `coo` doesn't match Coordinator, `india` doesn't match
  Indianapolis, `blockHard` beats `alwaysAllow`, a remote title rescues an `allow` miss but not
  a `block` hit, `non-remote` doesn't rescue, a band overlapping the floor passes.
- **Scope by the measurement:** title + the three live location tiers are the milestone. Salary,
  age and content have never fired in production (0 of 400,616) — model the fields, leave the
  evaluation for later, and don't build UI for them in M4.
- **Differential test against career-ops.** The strongest available correctness check: run the
  Swift gate over a recorded board payload with the user's real `portals.yml` criteria and
  assert it passes the same rows the `.mjs` filters do. A disagreement is either a port bug or
  a deliberate divergence, and both are worth being forced to name.
- Implement and persist `DiscoveryLedger`, including criteria-hash re-evaluation.
- A debug-menu command that sweeps one configured board and prints found / passed / rejected
  counts by reason. No hydration, no ingest yet.

**Done when:** the debug command reports plausible counts against a real board, and criteria
tests cover every `DiscoveryRejectReason` plus all three absent-data cases.

### M3 — Hydration, ingest, and the scheduler ✅ *shipped*

- `SearchSource` model + `SearchSourceService` CRUD.
- `DiscoveryScheduler` as a `RuntimeTaskController` task, following `AvailabilityBacklog`'s
  pacing discipline: one source at a time, gentle, cancellable, never blocking launch.
- Hydration as specified above, including the "don't ingest a body-less posting" rule.
- Passing postings → `JobService.ingestCapture` with `userNote` recording source and sweep date.
  **No changes to `ingestCapture`.**
- Health recording on every run, including `truncated`.
- Hard caps: max ingests per sweep (default 50) and per day (default 200), enforced at the
  ledger boundary so the cap also bounds hydration requests. When a cap truncates a sweep,
  **say so**.

**Done when:** an enabled source ingests only postings that clear gate A and hydrate to a real
body, a second sweep ingests nothing new, a criteria change re-evaluates prior rejects, and
disabling automatic search stops all activity within one cycle.

### M4 — Settings UI ✅ *shipped*

The Search tab as specified, including the live preview, the rejection histogram and the cost
estimate. Until this ships, M3 is debug-only — **do not enable automatic search by default
before the user can see and edit what it will do.**

**Done when:** a new user can add a source, set criteria, see the preview count, run a sweep
manually, and read what happened.

### M5 — Source resolution and health repair ✅ *shipped*

- A company→board resolver probing vendors in order — Greenhouse, Ashby, Lever first, then the
  long tail — accepting a board only when it exists **and** lists ≥1 job.
  `~/git/career-ops/discover-ats.mjs` is the working reference (11 vendors, bounded concurrency
  of 8 because Ashby holds a ~30s connection per board, and a `SLUG_RE` guard so a malformed
  company name cannot inject characters into a URL).
- **Workday cannot be resolved from a company name** — the tenant and instance
  (`{tenant}.wd5.…`) are not derivable, and career-ops flags Workday-without-a-hint for manual
  follow-up rather than guessing. jobhunt should do the same: ask for the tenant URL.
- The **Re-resolve** button on an amber source, offering the replacement board it found.
- Optional: promote a `Site` to a `SearchSource` when resolution succeeds.

This is what stops the feature rotting. In the reference system, 13 of 87 boards had migrated
and were silently returning nothing for weeks; re-resolution recovered 8, one of which went from
0 to 53 open roles.

**Done when:** an amber source can be repaired from the UI without editing anything by hand.

### M6 — Market-wide sources *(not built; optional, measure first)*

`SourceConfiguration.marketWide` sources need no company: Remotli, HN Who-is-Hiring, The Muse,
4 Day Week, a16z speedrun.

**Be honest about the yield before spending the time.** Measured against the reference system's
real criteria, 15 aggregators scanned 5,261 postings and surfaced 12 matches — 0.23% — and the
largest remote boards (RemoteOK, Remotive, WeWorkRemotely, Himalayas) returned **zero**
program/product roles that day. Of the 12, nine came from two sources (Remotli 6, HN 3). Build
those two, measure for a fortnight, then decide about the rest.

Note that these sources have no `atsPostingID`, which is why `DiscoveredPosting.dedupKey` falls
back to a normalised URL rather than being ATS-only.

### Explicitly out of scope

- **The 29k-board reverse-ATS sweep** (`scan-ats-full.mjs`). It depends on an external company
  directory refreshed weekly, plus DNS caching, resolver-outage detection, per-vendor
  concurrency caps and checkpoint/resume. career-ops already does this well. Duplicating it is
  months of work for no new coverage.
- **The other ~75 career-ops providers.** Roughly 20 are regional (DACH, Nordics, Poland, SE
  Asia), ~10 are single-employer, and a large group are HTML parsers whose maintenance
  career-ops amortises across all its users and jobhunt would carry alone.
- **Auto-apply.** Not now, not later.

---

## Risks

| Risk | Mitigation |
|---|---|
| Criteria too strict → silent zero-yield | Live preview; rejection histogram; amber health on empty runs |
| Criteria too loose → extraction cost blowout | Per-sweep and per-day ingest caps, priced in the UI, never silent |
| Gate A rejects what gate B would accept | Absent data always passes; gate A is a documented conservative subset with a test per rule |
| Title filter leaks (`COO` → Coordinator) | Word-boundary matching for short keywords, with a regression test |
| Location filter over-blocks (`india` → Indianapolis) | Word-boundary location matching, with a regression test |
| Body-less posting ingested as a stub | Hydration failure is a ledger outcome, not an ingest |
| Board migrates, source goes quiet | `consecutiveEmptyRuns` → amber → Re-resolve (M5) |
| Vendor rate-limits a burst | Sequential sweeps, inter-page delay, retry 429/5xx only, `rateLimited`/`truncated` health |
| A tenant's `total` is wrong | Page cap + explicit truncation notice; never trusted as completeness |
| Redirect used for SSRF | Refuse redirects, validate host before fetching |
| Ledger growth | Keep keys indefinitely; clear `rawJSON` when superseded |
| Duplicate work vs career-ops | Both end at `ingestCapture`; `DuplicateDetector` resolves collisions |

## Open questions

1. Should a discovered job land in `new` or a distinct `discovered` status? `new` reuses the
   existing triage flow; a separate status makes provenance visible but touches every
   status-handling site. **Recommendation:** `new` plus a `userNote` marker. The real risk isn't
   provenance, it's a machine filling the same triage inbox the user hand-curates — so if the
   daily cap is being hit regularly, revisit this.
2. Should gate-A rejects be inspectable ("show me what was filtered out")? Useful for tuning,
   but it is a second list of things that are not jobs. **Recommendation:** the histogram only,
   until asked for — the live preview covers the tuning case.
3. Does the fit floor belong in discovery, i.e. should a scored job that misses `minFitScore` be
   auto-archived? **Recommendation:** no — that is triage, and it already works.
4. Should hydration reuse `ATSResponseCache`? It would collapse the board fetch and the
   per-posting fetch for Lever/Ashby, where both come from the same payload. Probably yes;
   confirm the cache's keying and TTL suit a sweep before assuming it.
