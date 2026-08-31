# Jobhunt — Claude Code Guide

## Git workflow

- **Work directly on `main`** when you are the only agent in the repo. Don't create feature/fix
  branches for routine solo work — they accumulate and have to be cleaned up.
- **Commit after each completed change** (one logical change per commit) once it builds and the
  relevant tests pass. Don't batch many unrelated changes into one commit.
- Commits are SSH-signed via 1Password (must be unlocked); never use `--no-gpg-sign`.

### When another agent is working in this repo — use a worktree

**Check first, every session:** `git worktree list`. More than one entry means someone else is
mid-change, and two agents committing to `main` in the same checkout will interleave edits in the
same files and produce conflicts neither of them can see coming.

```bash
git worktree add .claude/worktrees/<topic> -b <topic>    # branch off current main
cd .claude/worktrees/<topic>                             # build and test HERE
```

- **Branch name = what you're doing** (`status-perf`, not `fix`), so `git worktree list` tells the
  other agent what you're touching.
- **Merge back at a natural boundary** — a finished, tested change — not at the end of a long
  session. The longer a branch lives, the worse the conflict:
  ```bash
  git -C <main checkout> merge --no-ff <topic>
  git worktree remove .claude/worktrees/<topic> && git branch -d <topic>
  ```
- **`git fetch` and check divergence before pushing.** The other agent may have pushed while you
  were building: `git rev-list --left-right --count origin/main...HEAD`.
- **Only one agent runs the app at a time.** The SwiftData store is single-writer and the store path
  is fixed (not per-worktree), so two running builds fight over the same file. Say which of you
  holds it. `./scripts/rebuild-and-run.sh` from a worktree launches *that* worktree's binary against
  the *shared* production store — fine, as long as it's the only one running.
- **Derived data is shared too.** Concurrent `xcodebuild` runs from two worktrees contend for the
  same DerivedData and the same 8 cores; keep `-jobs 6` and don't start a build while the other
  agent's is running.

## Working with the user: stay interruptible, delegate the work

The user gives feedback continuously, while work is already in flight — a screenshot of something
wrong, a new requirement, an unrelated bug they just hit. That feedback is worth more than an
uninterrupted work session, so **the main session's job is to stay free to receive it.** Hand the
implementation to a subagent and keep this session for talking, triaging and reviewing.

Mid-turn messages are **not lost**. They arrive as a `system-reminder` attached to whatever tool
result lands next, so the only cost is latency — if a build is running, expect a minute or two.
Acknowledge one when it arrives rather than silently folding it in, so the user knows it landed.

### The loop

1. **Triage the moment it arrives.** Three destinations, and say which one you picked:
   - *Changes the task in flight* → fold it in, tell the user you did.
   - *Real but separate* → `mcp__backlog__task_create` immediately, reply with the task id. This is
     the default. Capturing costs one tool call; losing it costs the user the whole observation.
   - *Needs a decision from them* → ask now, while they're present. Don't park a question.
2. **Delegate the implementation.** `Agent` with a full brief; it runs in the background and
   notifies on completion. Use `isolation: "worktree"` so it builds somewhere the user's running app
   isn't affected.
3. **Stay in the main session** — answer, summarize, take the next piece of feedback. Don't start a
   long build here; that's the thing that makes you unresponsive.
4. **Review what comes back** before merging. The subagent's report is a claim, not a verification.

### What this does and doesn't buy

**It buys responsiveness, not parallelism.** Builds serialize whatever you do: one fanless 8-core
machine, one shared DerivedData, one single-writer store. **Roughly one implementing subagent at a
time** — a second one just makes both slower and fights over the app. Read-only agents (`Explore`,
research, code reading) are cheap and can run several at once.

**A subagent cannot ask the user anything.** It will guess instead, and a guess buried in a
background task surfaces as finished work built on the wrong assumption. So resolve every open
question *before* delegating; if the work is genuinely exploratory, keep it here where the user can
be asked.

**A fresh subagent knows nothing about this conversation.** `subagent_type: "fork"` inherits the
context; anything else starts blank and needs the full brief — file paths, the decision already
made, what "done" looks like. If writing the brief costs more than the work, just do it here.

## Project Overview

Jobhunt is a native macOS SwiftUI app (macOS 15+) for tracking job applications. It uses:
- **SwiftData** for persistence
- **Tuist 4.x** to generate the Xcode project (`tuist generate --no-open`)
- **Swift strict concurrency** (`SWIFT_STRICT_CONCURRENCY = complete`)
- A local **HTTP server** (`JobhuntServer` via `NWListener`) for browser extension integration
- An **LLM pipeline** (`QueueActor`) for automatic job extraction

## Directory Layout

```
app/              SwiftUI app target
core/             JobhuntCore framework (models, services, LLM queue)
server/swift/     JobhuntServer framework (HTTP server, MCP bridge)
mcp/swift/        JobhuntMCP command-line tool (MCP stdio bridge)
tools/migrator/   JobhuntMigrator command-line tool (SQLite schema migration)
tests/            All test targets
  AppUITests/     XCUITest suite (requires graphical session — see below)
  CoreTests/      Unit tests for JobhuntCore
  ServerTests/    Unit tests for JobhuntServer
  MCPTests/       Unit tests for MCP helpers
scripts/          Shell utilities
config/           Entitlements, build config
```

## Building & Running

```bash
# Generate Xcode project (required after any Project.swift change)
tuist generate --no-open

# Build + test + launch (fast gate: CoreTests + ServerTests + MCPTests)
./scripts/rebuild-and-run.sh

# Build only
./scripts/rebuild-and-run.sh --skip-tests

# Run fast gate tests directly
xcodebuild test -project Jobhunt.xcodeproj -scheme Jobhunt-DMG \
  -configuration Debug-DMG -destination 'platform=macOS' \
  -only-testing:CoreTests -only-testing:ServerTests -only-testing:MCPTests \
  CODE_SIGNING_ALLOWED=NO
```

## Test Targets

| Target | Type | When to run |
|---|---|---|
| CoreTests | Unit | Always — part of fast gate |
| ServerTests | Unit | Always — part of fast gate |
| MCPTests | Unit | Always — part of fast gate |
| AppUITests | XCUITest | Opt-in — requires graphical session (see below) |
| LLMEval | Eval | Opt-in — requires real LLM API keys |

> **Note:** `MCPHelpers.swift` and migrator sources are compiled directly into their test bundles (MCPTests, CoreTests) because `JobhuntMCP` and `JobhuntMigrator` are `commandLineTool` products that can't be linked as frameworks.

## AppUITests — XCUITest Setup

### What it does
The `AppUITests` suite drives the full macOS app via the Accessibility API. It covers:
- **ScreenshotTests**: visual tour of every view and settings tab (General/Jobs/AI/Data/Debug)
- **BehaviorUITests**: sidebar nav, keyboard shortcuts (⌘K, ⌘,), filter chip state
- **WorkflowUITests**: seeded data workflows (archive a job, etc.)
- **JobsScreenUITests**: Jobs filter sidebar, menu bar commands
- **MockLLMUITests**: end-to-end LLM Test Connection against a localhost mock

### Launch arguments (set in `AppUITests.swift:launchApp`)
```
-UIAnimationDragCoefficient 0   Disables animations for speed
--ui-test-store                 Uses isolated temp DB (never touches production data)
--seed-demo-data                Calls DemoSeeder on startup to populate test rows
```

The app responds to these in `app/JobhuntApp.swift` (`LaunchPlan.parse(...)`, ~line 41).

### Running locally
```bash
xcodebuild test -project Jobhunt.xcodeproj -scheme Jobhunt-DMG \
  -destination 'platform=macOS' \
  -only-testing AppUITests \
  CODE_SIGNING_ALLOWED=NO
```

**Requirements:**
- Must run on a machine with a live graphical session (logged-in user, visible desktop)
- Accessibility permission must be granted to the test runner or Terminal
- Screen Recording permission needed for screenshots
- Screenshots land in `/tmp/jobhunt-screenshots/<timestamp>/` and are attached to the `.xcresult`

### Running in a Tart VM (headless, no focus-steal)
Preferred for local development when you don't want the test runner to hijack your mouse:

```bash
# One-time setup
brew install cirruslabs/cli/tart
brew install hudochenkov/sshpass/sshpass
tart clone ghcr.io/cirruslabs/macos-sequoia-xcode:latest jobhunt-uitest-env

# Run tests in VM
./scripts/run-ui-tests-in-vm.sh

# Leave VM running after tests (for debugging)
./scripts/run-ui-tests-in-vm.sh --no-shutdown
```

**Full VM details:** See `docs/vm-testing.md` — covers architecture, all CLI flags, debugging failures, screenshot retrieval, incremental builds, and comparison with CI.

### CI (GitHub Actions)
Defined in `.github/workflows/ui-tests.yml`. Runs weekly (Monday 8am UTC) or on manual dispatch against `macos-latest` runner. Results uploaded as `.xcresult` artifact (7-day retention).

## Project.swift (Tuist)

`Project.swift` defines all targets and schemes. Key patterns:
- **CoreTests sources** include migrator Swift files directly (commandLineTool can't be linked):
  ```swift
  sources: ["tests/CoreTests/**/*.swift",
            "tests/Support/MockLLM/**/*.swift",
            "tools/migrator/Migration.swift",
            "tools/migrator/Patch.swift",
            "tools/migrator/SQLiteHelpers.swift",
            "tools/migrator/RepairJobNumbers.swift",
            "tools/migrator/Args.swift"]
  ```
- **MCPTests sources** include `mcp/swift/MCPHelpers.swift` directly (same reason)
- **Jobhunt-DMG scheme** test action includes: CoreTests, ServerTests, MCPTests, AppUITests

## Release (Developer ID / DMG)

> **Full release runbook: [`docs/release-process.md`](docs/release-process.md)** — step-by-step for
> cutting a DMG release and the (deferred) MAS release, the version-bump checklist (incl. the
> `currentProjectVersion` bump Sparkle needs), required CI secrets, and troubleshooting.

- **Every release MUST update the GitHub release notes / changelog** — never leave the release body
  empty. Keep it short and DMG-user-facing (a few "What's new" highlights + the Sparkle auto-update
  line + the macOS 15 requirement); don't list internal/CI/docs churn. Format + rules:
  [`docs/release-process.md`](docs/release-process.md#release-notes--changelog-required-every-release).
- **Never deliver a build to the Mac App Store without the user's explicit, per-release confirmation.**
  MAS is a curated channel — not every DMG release ships there. The DMG auto-publishes on a tag; MAS
  does **not**. `release-mas.yml` only uploads to App Store Connect on a manual `workflow_dispatch`
  run with `upload_to_app_store_connect` checked (and never auto-submits for review). See
  [`docs/release-process.md`](docs/release-process.md#5-mac-app-store-mas-release) §5.

- **Hardened runtime is required and explicit** (TASK-401): `Debug-DMG`/`Release-DMG` set
  `ENABLE_HARDENED_RUNTIME = YES` at the project level in `Project.swift`, so signing emits
  `--options runtime` for the app *and* the bundled `jobhunt-mcp` helper — Developer ID apps without
  it are rejected by `notarytool`. Don't rely on the generated default. The `release-dmg.yml` smoke
  check asserts `codesign -dvv … flags=…(runtime)` on both binaries *before* notarization, and on a
  notarization failure pulls `notarytool log <id>` into the workflow logs. (MAS builds use the App
  Sandbox; hardened runtime is a DMG-only concern.)

### Never upload a store build from this Mac's default toolchain

Every MAS delivery goes through `release-mas.yml` on `macos-latest`, which uses the runner's
*released* Xcode (26.6 / 17F113 for the 1.3.0 delivery). Keep it that way. Locally this Mac runs a
beta macOS with only `Xcode-beta.app`, and the scripts pin `DEVELOPER_DIR` at it — correct for
Developer ID, fatal for the App Store:

```
This bundle is invalid. Apple is not currently accepting applications
built with this version of Xcode. (90301)
```

Ingestion checks the `DTXcodeBuild`/`DTSDKBuild` keys stamped into `Info.plist`, so no upload flag
or tool avoids it — Transporter fails exactly as `altool` does. **Notarization is not a pre-flight
signal for this:** the same beta-built binaries notarize and staple cleanly, which is why the DMG
channel never surfaces the problem.

If a local store upload is ever unavoidable (CI down, expired secret, urgent fix), the escape hatch
proven on the sibling `nevermore` project: download the released Xcode `.xip` from
developer.apple.com — the App Store refuses to install it on a beta macOS, developer.apple.com
doesn't — `xip --expand` it (needs ~20 GB free), and point `DEVELOPER_DIR` at the expanded bundle.
The IDE won't launch on beta macOS; `xcodebuild` inside it works, which is all that's needed.

### App Store Connect API (stats, build state, reviews)

`scripts/asc-stats.py` queries App Store Connect — `builds` (has Apple finished processing an
upload?), `versions`, `reviews`, `sales --days N`. It's a `uv` script with inline dependencies, so
`./scripts/asc-stats.py builds` runs it with no venv setup.

Credentials, all **outside the repo**:

| What | Where | Secret? |
|---|---|---|
| Private key | `~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8` (mode `600`) | **Yes** — never print, copy or commit it |
| `issuer_id`, `key_id`, `app_id`, `vendor_number` | `~/.appstoreconnect/config.json` | No, but keep them out of git too |

The key in use is `AuthKey_Y4673VW6CJ.p8`; JobHunt's `app_id` is `6782679255`. `issuer_id` and
`key_id` come from **Users and Access → Integrations → App Store Connect API**; `vendor_number`
is in **Payments and Financial Reports**. Auth is a 20-minute ES256 JWT — Apple rejects longer
expiries.

**The key's role decides what works.** A key with only app access reads `builds`, `versions` and
`reviews` but gets a bare 403 on `sales` — Apple checks the role *before* the vendor number, so the
error reads as a bad vendor number when it isn't. Sales and Trends needs **Admin** or **Finance**,
and a key's role is fixed at creation: generate a new key and update `key_id`.

**Do not revoke `68BGNV3CCC`.** It is *not* an obsolete JobHunt key — it's a Developer-role key
belonging to the **nevermore** project's build-upload pipeline, which shares this Apple team, and
Apple issues a `.p8` exactly once so revoking it can't be undone. Its Developer role is why it 403s
on `sales`. JobHunt uses `Y4673VW6CJ` (an Individual Key, so it doesn't appear in the team's Team
Keys tab).

Sales reports lag ~24h and a zero-sales day simply 404s, which `sales` treats as zero rather than an
error. There is no "installs" endpoint: units from Sales and Trends is the closest thing.

## Data store location & backup

The store path comes from `ModelContainerFactory.productionStoreURL()`: the system Application Support
directory + a fixed `Jobhunt/jobhunt.store`. Because the subfolder is fixed (not keyed by bundle ID),
**which build you run only matters for sandbox status**, and the app bundle ID is the same
(`com.jobhunt-app.jobhunt`) across all four configs:

| Build config | Sandboxed? | Store location |
|---|---|---|
| Debug-DMG / Release-DMG | No | `~/Library/Application Support/Jobhunt/jobhunt.store` |
| Debug-MAS / Release-MAS | Yes | `~/Library/Containers/com.jobhunt-app.jobhunt/Data/Library/Application Support/Jobhunt/jobhunt.store` |

Consequences:
- **All DMG builds share one store** — the dev `Debug-DMG` build run from DerivedData and a shipped
  notarized `Release-DMG` open the *same* file. No migration needed between them.
- **MAS (App Store) is a separate, sandboxed store.** Moving DMG data into a MAS install (or vice
  versa) is a one-time copy with the app quit: copy `jobhunt.store` + `-shm` + `-wal` into the other
  location. A DMG and a MAS install can't live-share — pick one as primary or they diverge.

**Backups.** `scripts/backup-store.sh` makes a consistent single-file snapshot via SQLite's online
backup (`.backup`) — safe to run *with the app open*, folds in the `-wal`, integrity-checks the
result, and rotates (keeps newest `JOBHUNT_BACKUP_KEEP`, default 30) into `JOBHUNT_BACKUP_DIR`
(default `~/Documents/jobhunt-backups`). `--mas` targets the sandbox container. Restore = quit app,
remove `jobhunt.store{,-shm,-wal}`, copy a snapshot to `jobhunt.store`, relaunch (see the script
header). Put the backup dir somewhere itself backed up (Time Machine / iCloud / external) — a copy on
the same disk doesn't survive disk failure.

**Secrets are NOT in the backup (TASK-378).** The backup/restore (both the in-app *Back Up / Restore*
buttons via `BackupService` and `backup-store.sh`) covers the SQLite store only. AI provider **API
keys live in the macOS Keychain**, and the **MCP token** is a transient file (`~/.jobhunt-mcp-token`),
so neither is in a snapshot. After a restore — especially onto a new Mac — the user re-enters API keys
in AI Provider settings; the MCP token regenerates on its own.

**In-app restore quiesces the runtime first (TASK-546).** Because the store is single-writer,
`RestoreCoordinator` (used by the *Restore* button) calls `AppServices.shutdown()` — cancelling the
LLM queue / availability loop and stopping the local server — **before** the safety backup and the
destructive swap, so no background actor can write to the store while its files are being replaced.
On success *or* any failure the app quits, so the next launch opens a known store with a clean
runtime (it's never left half-restored against a partially-quiesced runtime).

**Restore smoke checklist** (run after any restore/migration before trusting it):
1. App relaunches and the **job count / list** matches the source.
2. **Settings → AI Provider**: the selected provider + model are correct (these are store-backed), but
   the **API key field state** is as expected — present if the Keychain item survived (same Mac), empty
   if not (new Mac). Re-enter the key if empty and confirm it saves.
3. Run one **extraction or fit-score** to prove the provider + key actually work end-to-end.
4. A **capture from the extension** still reaches the app (MCP token regenerated, server reachable).
5. Spot-check that **resumes and sites** are present.

## One-time data operations (migrations / cleanup / backfills)

**Do not put one-time data fixups in the app launch path.** They become deprecated code that sits
forever behind a "have we done this yet?" flag, and a stale flag silently skips the work on data that
needs it (we hit exactly this: an in-app re-clean guarded by `reclean_captures_v2_done` had its flag
set *before* a later cleaner change, so 67 captures kept the old cleaning until re-run from the CLI).

Instead, put the transformation logic in **JobhuntCore** (so it's shared and tested) and expose a
one-shot entry point in the **JobhuntMigrator** CLI (`tools/migrator/`). Run it deliberately,
out-of-band, with the app quit. Keep the launch path for **recurring operational work only** (e.g.
`requeueRunningOnLaunch` crash recovery, `pruneFinishedRequests`, the availability re-check loop).

Why the CLI and not a second live process: the SwiftData store (`@ModelActor BackgroundStore` over
SQLite at `~/Library/Application Support/Jobhunt/jobhunt.store`) is **single-writer** and not
multi-process-safe. A separate program must only touch it while the app is **not running**.

Existing migrator modes (default `--store` = the live store; all idempotent):

Exactly one operation flag per invocation — the migrator rejects combining them (TASK-523).

```bash
osascript -e 'quit app "Jobhunt"'             # the store is single-writer — quit first
JobhuntMigrator --reclean                      # recompute every capture's cleanedDescription
JobhuntMigrator --backfill-models              # fill LLMRequest.model on old finished rows
JobhuntMigrator --prune-orphan-fit-scores      # delete resume-less fit scores, recompute job mirrors
JobhuntMigrator --prune-orphan-attempts        # delete LLMRequestAttempts whose request is gone
JobhuntMigrator --prune-orphan-referral-attempts # delete referral attempts whose job is gone
JobhuntMigrator --recompute-fit-mirrors        # recompute every job's denormalized fit mirror
JobhuntMigrator --detect-duplicates            # flag same-cleaned-hash duplicates across URLs
JobhuntMigrator --repair-duplicate-job-numbers # renumber duplicate jobNumbers (raw SQLite, pre-open)
JobhuntMigrator --merge-job --from 761 --into 725 # fold a duplicate job into the keeper, delete it
# Full list (incl. --recheck-evidence, --normalize-seniority, --recompute-criteria,
# --repair-canonical-urls, --unmark-heuristic-duplicates): tools/migrator/README.md
```

**Before running any of these against prod data: quit the app, then back up the store *with its
WAL*** — CoreData leaves an uncheckpointed `-wal`, so copy `jobhunt.store` **and** `jobhunt.store-shm`
**and** `jobhunt.store-wal` together (a `.store`-only copy loses recent changes). Relaunch the app
afterward. When shipping a release build, re-run the same modes once against that build's store if it
carries the same legacy data.

When adding a new fixup: add a `BackgroundStore` (or other JobhuntCore) method + a unit test, then a
`Mode` case + handler in `tools/migrator/Args.swift` and `main.swift`, and document it in
`tools/migrator/README.md`. Once every install has passed a given fixup, the mode can be deleted.

## Conventions

- **A Codable type stored as JSON is a schema too.** `SourceConfig` (in `SearchSource.configJSON`),
  `PromptTemplate`, `ScoringFeedback`, `FitScoreResult` and `BackgroundStore.RawRow` are all persisted
  as JSON strings. A property *declaration default* is not a *decoding default*: synthesized
  `Decodable` calls `decode` for a non-optional property and throws `keyNotFound` when the key is
  absent, so **adding a non-optional property with a default silently breaks every previously-saved
  row**. Worse, the call sites use `try?` and fall back to a blank value, so the failure looks like
  data loss rather than an error (adding `useCache: Bool = true` made every watched source come back
  with an empty slug). Add new fields as optionals, or write `init(from:)` with `decodeIfPresent`.
  Same rule, one layer down, as the SwiftData schema policy below.
- **Changing gate-A matching logic requires bumping `DiscoveryCriteria.gateVersion`.** The ledger
  keys each verdict on `criteriaFingerprint`, and that hash covers the user's criteria *values* plus
  that version constant. Without a bump, every posting already rejected under the old logic stays
  marked as judged and the fix never reaches it.
- **Don't over-optimize for scale this app won't reach.** Expected data is on the order of a *few
  hundred* jobs — a single user's tracked applications. An O(N) or O(N×S) filter/sort/scan over a few
  hundred rows on the main thread is imperceptible, and SwiftUI `List`/`LazyVStack` already window row
  rendering. Don't add caching layers, off-main pipelines, denormalized indexes, or pagination unless
  there's a *measured* problem at the real scale. Prefer the simplest correct code; reserve the
  optimization patterns for genuinely large/unbounded data (e.g. bulk migrator passes).
- **One-time data ops live in the CLI, not app launch** — see the section above. The launch path is
  recurring operational work only.
- **Actor isolation**: `QueueActor` uses closure-based init (`isPaused:`, `onSetPaused:`, `readExtractionSettings:`, `providerFactory:`). Don't use direct property access on settings from outside the actor.
- **Server errors**: Use `safeServerError(_:context:)` instead of `error.localizedDescription` in HTTP response bodies to avoid leaking file paths or SwiftData internals.
- **HTTP server**: `JobhuntServer.receiveRequest` accumulates TCP chunks until a complete request (headers + full Content-Length body) is parsed before dispatching. Don't process partial reads.
- **Test isolation**: `ServerTests` share one `JobhuntServer` instance across all tests in the class (static `sharedServer`) to avoid NWListener port lifecycle issues.
- **CORS is not the security boundary — the loopback binding is.** `Origin` is forgeable by any local
  process, so the extension-route check cannot authenticate a caller. What keeps other machines out is
  `requiredInterfaceType = .loopback`, enforced by the OS before any request is parsed. The origin
  allowlist exists to stop *other Chrome extensions* driving those routes from the browser, where the
  same-origin policy makes `Origin` trustworthy. Extension routes are therefore protected against the
  network but not against a hostile process running as this user — deliberate, since such a process
  could read the SwiftData store directly. MCP routes carry a bearer token for a different reason:
  they are driven by third-party AI clients, so the token scopes which may act on the user's data.
  The allowlist now contains the published CWS ID (`JobhuntServer.productionExtensionOrigin`); debug
  builds additionally permit any `chrome-extension://` origin so unpacked dev builds work, and release
  builds fail closed. Full rationale in the comment above `isAllowedExtensionOrigin`.
