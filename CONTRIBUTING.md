# Contributing

Contributions are welcome — **including AI-assisted or AI-generated ones.** There's no separate
process for them; the same quality bar applies (tests pass, change is focused, lint/format clean).

**Before building anything, tell us what you have in mind.** To request or discuss any change — a bug
fix, a feature, or a design question — please [open an issue](https://github.com/brooksc/jobhunt/issues)
or open a pull request. That keeps direction visible and avoids duplicated or wasted work.

## Reporting issues

Open an issue at [github.com/brooksc/jobhunt/issues](https://github.com/brooksc/jobhunt/issues). Include your macOS version and steps to reproduce.

## Pull requests

1. Fork the repo and create a branch from `main`.
2. Run the fast test gate before submitting (see below); run the full CI-equivalent gate before opening the PR.
3. Keep changes focused — one fix or feature per PR.
4. Update the README if your change affects setup or usage.

## Stack

| Layer | Technology |
|---|---|
| Language | Swift 6+ |
| UI | SwiftUI |
| Persistence | SwiftData |
| Networking | Network.framework (HTTP server), URLSession (LLM client) |
| Project | Tuist 4.x (`tuist generate --no-open`) |
| Extension | Chrome Manifest V3 |

The app stores its SwiftData database under `~/Library/Application Support/Jobhunt/`. See the root
[`CLAUDE.md`](CLAUDE.md) for the directory layout, actor-isolation conventions, and one-time data
operations (migrations live in the `JobhuntMigrator` CLI, never the app launch path).

**Tunable heuristics** — the opinionated constants you're most likely to tweak (fit-scoring weights &
penalties, duplicate-detection thresholds, "posting gone" phrase lists, staleness thresholds) are
indexed in [`docs/tuning.md`](docs/tuning.md).

## Dependency versions

The whole build toolchain is pinned in `.mise.toml` — **Tuist, SwiftLint, and SwiftFormat** — and CI
installs exactly these via `mise install`. Install all of them the same way (don't install Tuist via
its upstream curl script, or you may generate the project with a different version):

```bash
mise install   # installs the pinned Tuist + SwiftLint + SwiftFormat
```

To update a pinned tool:
1. Edit `.mise.toml` — change the tool's version.
2. Run `mise install` locally.
3. If Tuist changed, regenerate the project: `tuist generate --no-open`.
4. Verify the full gate passes, then commit `.mise.toml`.

## Development setup

```bash
# First time: install the pinned toolchain (Tuist + SwiftLint + SwiftFormat)
mise install

# Regenerate the Xcode project whenever Project.swift changes
tuist generate --no-open

# Build (Debug) and launch in one step
./scripts/rebuild-and-run.sh

# Build only
xcodebuild build \
  -project Jobhunt.xcodeproj \
  -scheme Jobhunt-DMG \
  -configuration Debug-DMG \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO
```

## Running tests

**Fast gate** (CoreTests + ServerTests + MCPTests, ~30s) — a *partial* check for quick local
feedback while iterating. It is NOT the full CI gate (CI also builds both schemes, runs the
extension tests, and lints — see below). Run this constantly; run the full gate before opening a PR.

```bash
xcodebuild test \
  -project Jobhunt.xcodeproj \
  -scheme Jobhunt-DMG \
  -configuration Debug-DMG \
  -destination 'platform=macOS' \
  -only-testing:CoreTests \
  -only-testing:ServerTests \
  -only-testing:MCPTests \
  CODE_SIGNING_ALLOWED=NO
```

**Full CI-equivalent gate** (TASK-411) — run this before opening a PR; it mirrors
`.github/workflows/swift-build.yml` step-for-step. Each step must pass:

```bash
mise install                                    # pinned Tuist / SwiftLint / SwiftFormat
tuist generate --no-open

# 1. Build both shipping schemes
xcodebuild -scheme Jobhunt-DMG -configuration Debug-DMG -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO
xcodebuild -scheme Jobhunt-MAS -configuration Debug-MAS -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO

# 2. Fast tests + line-coverage floor
xcodebuild test -scheme Jobhunt-DMG -configuration Debug-DMG -destination 'platform=macOS' \
  -only-testing CoreTests -only-testing ServerTests -only-testing MCPTests \
  -resultBundlePath build/FastTests.xcresult CODE_SIGNING_ALLOWED=NO
./scripts/check-coverage.sh build/FastTests.xcresult

# 3. Extension Node tests
npm test --prefix extension

# 4. Lint + format (must be clean)
swiftlint lint --strict
swiftformat --lint app core server/swift mcp/swift tests
```

CI additionally guards against mixed-case test paths and verifies the committed fixture matches its
manifest (`scripts/build-fixture-db.sh` writes both) — those only matter if you touched test paths or
regenerated the fixture. **AppUITests are NOT in either gate** — they need a display and run in a VM /
scheduled lane (below).

**UI tests** (requires a display; run manually or on a scheduled CI lane):

```bash
xcodebuild test \
  -project Jobhunt.xcodeproj \
  -scheme Jobhunt-DMG \
  -configuration Debug-DMG \
  -destination 'platform=macOS' \
  -only-testing:AppUITests \
  CODE_SIGNING_ALLOWED=NO
```

**LLM eval** (opt-in; requires a running LLM provider):

```bash
# LLMEval lives in the opt-in Jobhunt-Eval scheme (NOT Jobhunt-DMG, which never runs it).
JOBHUNT_LLM_URL=http://127.0.0.1:1234 xcodebuild test \
  -project Jobhunt.xcodeproj \
  -scheme Jobhunt-Eval \
  -destination 'platform=macOS' \
  -only-testing:LLMEval \
  CODE_SIGNING_ALLOWED=NO
```

To enforce a minimum accuracy threshold (e.g. 80%), add `JOBHUNT_LLM_MIN_ACCURACY=80`. See [tests/LLMEval/README.md](tests/LLMEval/README.md) for full details.

## Versioning & releases

The version lives in `Project.swift` (`.marketingVersion`) and must match `extension/manifest.json`
(the `version-parity` CI gate enforces this). Bump both with:

```bash
./scripts/bump-version.sh patch   # z++   (reads the current version from Project.swift)
./scripts/bump-version.sh minor   # y++, z=0
./scripts/bump-version.sh major   # x++, y=0, z=0
./scripts/bump-version.sh 1.2.3   # set an explicit version
```

The script updates `Project.swift` + `extension/manifest.json` and prints the new version; it does
**not** commit. Cutting an actual release (tagging, signing, notarization, Sparkle appcast, Mac App
Store) is maintainer-only and documented in [`docs/release-process.md`](docs/release-process.md).
