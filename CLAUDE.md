# Jobhunt — Claude Code Guide

## Git workflow

- **Work directly on `main`** unless there's a specific reason not to (e.g. a subagent running in
  its own worktree). Don't create feature/fix branches for routine work — they accumulate and have
  to be cleaned up.
- **Commit after each completed change** (one logical change per commit) once it builds and the
  relevant tests pass. Don't batch many unrelated changes into one commit.
- Commits are SSH-signed via 1Password (must be unlocked); never use `--no-gpg-sign`.

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
- **ScreenshotTests**: 19-test visual tour of every view/settings tab
- **BehaviorUITests**: sidebar nav, keyboard shortcuts (⌘K, ⌘,), filter chip state
- **WorkflowUITests**: seeded data workflows (archive a job, etc.)
- **JobsScreenUITests**: Jobs filter sidebar, menu bar commands

### Launch arguments (set in `AppUITests.swift:launchApp`)
```
-UIAnimationDragCoefficient 0   Disables animations for speed
--ui-test-store                 Uses isolated temp DB (never touches production data)
--seed-demo-data                Calls DemoSeeder on startup to populate test rows
```

The app responds to these in `app/JobhuntApp.swift` (~line 26).

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
            "tools/migrator/Migration.swift",
            "tools/migrator/Patch.swift",
            "tools/migrator/SQLiteHelpers.swift"]
  ```
- **MCPTests sources** include `mcp/swift/MCPHelpers.swift` directly (same reason)
- **Jobhunt-DMG scheme** test action includes: CoreTests, ServerTests, MCPTests, AppUITests

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

```bash
osascript -e 'quit app "Jobhunt"'          # the store is single-writer — quit first
JobhuntMigrator --reclean                   # recompute every capture's cleanedDescription
JobhuntMigrator --backfill-models           # fill LLMRequest.model on old finished rows
JobhuntMigrator --prune-orphan-fit-scores   # delete resume-less fit scores, recompute job mirrors
# --migrate / --patch / --verify / --repair-fit-scores: the original SQLite→SwiftData import path
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

- **One-time data ops live in the CLI, not app launch** — see the section above. The launch path is
  recurring operational work only.
- **Actor isolation**: `QueueActor` uses closure-based init (`isPaused:`, `onSetPaused:`, `readExtractionSettings:`, `providerFactory:`). Don't use direct property access on settings from outside the actor.
- **Server errors**: Use `safeServerError(_:context:)` instead of `error.localizedDescription` in HTTP response bodies to avoid leaking file paths or SwiftData internals.
- **HTTP server**: `JobhuntServer.receiveRequest` accumulates TCP chunks until a complete request (headers + full Content-Length body) is parsed before dispatching. Don't process partial reads.
- **Test isolation**: `ServerTests` share one `JobhuntServer` instance across all tests in the class (static `sharedServer`) to avoid NWListener port lifecycle issues.
- **CORS**: Only `chrome-extension://` origins are allowed CORS headers. The allowlist in `JobhuntServer.allowedExtensionOrigins` is empty during development (permits all `chrome-extension://` origins); add the CWS ID after publishing.
