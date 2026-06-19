# Jobhunt Test Strategy

## Overview

Tests are split into four layers, each with a distinct scope, speed, and environment requirement.

```
Layer 4 — AppUITests    (XCUITest, full app, graphical session, ~2–5 min)
Layer 3 — MCPTests      (unit, MCP JSON-RPC helpers, ~1 s)
Layer 2 — ServerTests   (unit, HTTP server + CORS + MCP bridge, ~1 s)
Layer 1 — CoreTests     (unit, models / services / migrations, ~10 s)
```

## Fast Gate (CI & local pre-commit)

Layers 1–3 run on every build via `rebuild-and-run.sh`:

```bash
xcodebuild test -project Jobhunt.xcodeproj -scheme Jobhunt-DMG \
  -configuration Debug-DMG -destination 'platform=macOS' \
  -only-testing:CoreTests -only-testing:ServerTests -only-testing:MCPTests \
  CODE_SIGNING_ALLOWED=NO
```

Target: **< 30 seconds**, **0 failures**.

### Coverage gate

Line coverage for `JobhuntCore` + `JobhuntServer` is measured (`-enableCodeCoverage YES`) and enforced by `scripts/check-coverage.sh`, run in `swift-build.yml` CI and locally by `rebuild-and-run.sh`. It is a **ratchet floor** (currently **70% line**; actual ≈ 71%) — raise it as coverage improves, never let it regress.

> `xccov` reports **line** coverage only — there is no branch-coverage gate for the Swift code. (The old 85% line / 78% branch figure was the legacy Node/Express project's gate and does not apply here.)

## Layer 1 — CoreTests

**What's covered:**
- `JobService` — ingest, deduplicate, archive, status transitions
- `DuplicateDetector` — URL + title similarity
- `AvailabilityChecker` — job expiry logic
- `DemoSeeder` — seeded data health check
- `Normalization` — LLM extraction output normalization
- `MigratorTests` — SQLite schema migration correctness
- `ModelRoundTripTests` — SwiftData encode/decode round-trips

**How source files reach the test bundle:**
`JobhuntCore` framework is linked directly. Migrator sources (`Migration.swift`, `Patch.swift`, `SQLiteHelpers.swift`, `RepairJobNumbers.swift`, `Args.swift`) and the shared MockLLM server are compiled directly into CoreTests because `JobhuntMigrator` is a `commandLineTool` (not linkable).

**Key patterns:**
- Use `ModelContainerFactory.inMemory()` for a fresh in-memory SwiftData store per test
- `BackgroundStore` actor is initialized with the in-memory container
- No mocking of the database — always use real SwiftData (avoids mock/prod divergence)

## Layer 2 — ServerTests

**What's covered:**
- HTTP routing — `/health`, `/api/ping`, `/captures`, `/site-reviews`, `/api/jobs/by-url`, `/api/app/focus`
- CORS — only `chrome-extension://` origins get reflected headers; non-extension origins get 403
- MCP bridge routes — token validation (empty → 503, wrong → 401, correct → dispatches)
- Error bodies — no file paths, no SwiftData class names in 4xx/5xx responses (`safeServerError`)
- HTTP parser — accumulates fragmented TCP reads before processing (Content-Length body check)

**Infrastructure note:**
All tests share one `JobhuntServer` instance (class-level `static sharedServer`) to avoid per-test NWListener create/destroy cycle, which caused intermittent RST errors and `~1s` timeouts from URLSession sending partial POST requests.

## Layer 3 — MCPTests

**What's covered:**
- JSON-RPC response shape (`successResponse`, `errorResponse`)
- Tool list completeness and schema shape (`jobs_list`, `job_get`, `add_capture`, …)
- `resolveToolRoute` — unknown tool → failure, valid tool → correct path + body
- `readToken` — doesn't crash when token file is absent

**How source files reach the test bundle:**
`mcp/swift/MCPHelpers.swift` is compiled directly into MCPTests (same pattern as migrator in CoreTests). `main.swift` is excluded (it has the entry point, which conflicts with a test host).

## Layer 4 — AppUITests (XCUITest)

**What's covered:**

| Suite | Tests | Description |
|---|---|---|
| `ScreenshotTests` | 18 | Visual tour: Dashboard → every Jobs filter → NeedsAction → Sites → Duplicates → LLM Queue → Data Quality → Settings tabs (General/Jobs/AI/Data/Debug) → Resumes |
| `BehaviorUITests` | 6 | Sidebar nav, ⌘K, ⌘, (Settings), Remote filter chip, Data Quality filter chip |
| `WorkflowUITests` | 2 | Archive a job, seeded data health check |
| `MockLLMUITests` | 1 | LLM Test Connection vs a localhost mock (skipped — TASK-540) |
| `JobsScreenUITests` | 2 | Pursuing filter, Jobs menu bar commands |

**Launch arguments (set automatically by `launchApp()`):**
```
-UIAnimationDragCoefficient 0   Disables animations
--ui-test-store                 Isolated temp DB at ~/Library/Temp/JobhuntUITest/
--seed-demo-data                Populates demo jobs, sites, captures via DemoSeeder
```

**Environment requirements:**

| Environment | Display | Permissions | Command |
|---|---|---|---|
| Local (native) | Logged-in graphical session | Accessibility + Screen Recording | `xcodebuild test … -only-testing AppUITests` |
| Tart VM (headless) | Provided by VM | Auto-granted in VM | `./scripts/run-ui-tests-in-vm.sh` |
| GitHub Actions | `macos-latest` runner | Auto-granted | `.github/workflows/ui-tests.yml` |

**When to run:**
- Before a release
- After any UI layout change
- After adding a new view or sidebar item
- Scheduled weekly via CI (Monday 8am UTC)

**Running locally without focus-steal:**
```bash
# One-time: clone the VM image (requires Tart installed)
brew install cirruslabs/cli/tart
brew install hudochenkov/sshpass/sshpass
tart clone ghcr.io/cirruslabs/macos-sequoia-xcode:latest jobhunt-uitest-env

# Run
./scripts/run-ui-tests-in-vm.sh
```

**Screenshots:**
- Written to `/tmp/jobhunt-screenshots/<timestamp>/` during test run
- Also attached to the `.xcresult` bundle (viewable in Xcode → Report Navigator)
- `scripts/screenshot-tests.sh` copies them to `screenshots/` (gitignored)

## What Is NOT Tested (and Why)

| Area | Reason |
|---|---|
| Real LLM calls | Cost + non-determinism; covered by `LLMEval` target (opt-in) |
| Production SwiftData store | Tests always use in-memory or `--ui-test-store` |
| macOS Keychain | Stores AI-provider API keys (via `KeychainStore`); keys are NOT in the SwiftData store or backups |
| Push notifications / background fetch | Not implemented |
| App Store receipt validation | No MAS-specific logic yet |

## Adding New Tests

### Unit test (CoreTests / ServerTests / MCPTests)
1. Add a `final class FooTests: XCTestCase` to the appropriate target directory
2. Use `ModelContainerFactory.inMemory()` if SwiftData is needed
3. Run: `xcodebuild test … -only-testing CoreTests` (or ServerTests/MCPTests)

### UI test (AppUITests)
1. Add to the appropriate suite file in `tests/AppUITests/`
2. Use `launchApp()` (seeds data, disables animations, uses isolated store)
3. Use `navigate(app, label:)` for sidebar navigation — uses `accessibilityIdentifier` not display text
4. Use `snap(app, "name")` for screenshots
5. Run: `xcodebuild test … -only-testing AppUITests` or `./scripts/run-ui-tests-in-vm.sh`

### Adding a new sidebar item
When adding a new sidebar entry:
1. Set `.accessibilityIdentifier("sidebar.<name>")` on the button in `Sidebar.swift`
2. Add the mapping to `AppUITests.swift:sidebarIDs`
3. Add a `ScreenshotTests` test for the new view

## Flakiness Notes

- `AppUITests` are inherently slower and more sensitive to timing than unit tests. Use `waitUntil(timeout:)` and `waitForExistence(timeout:)` — never `sleep()`.
- `ServerTests` previously had intermittent RST failures when creating a new `NWListener` per test. Resolved by sharing one server instance across all tests (`static sharedServer`).
- `testCORSPreflight` checks for 204 OR 200 (both acceptable for OPTIONS preflight) to avoid brittleness.
