# Contributing

Bug reports and pull requests are welcome.

## Reporting issues

Open an issue at [github.com/brooksc/jobhunt/issues](https://github.com/brooksc/jobhunt/issues). Include your macOS version and steps to reproduce.

## Pull requests

1. Fork the repo and create a branch from `main`.
2. Run the fast test gate before submitting (see below).
3. Keep changes focused — one fix or feature per PR.
4. Update the README if your change affects setup or usage.

## Dependency versions

Tuist is pinned in `.mise.toml`. CI reads this file via `mise install tuist`.

To update Tuist:
1. Edit `.mise.toml` — change the `tuist` version.
2. Run `mise install tuist` locally.
3. Regenerate the project: `tuist generate --no-open`.
4. Verify tests pass, then commit `.mise.toml`.

## Development setup

```bash
# First time: install Tuist (version pinned in .mise.toml)
mise install tuist

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


See [README.md](README.md#test) for full details on each lane.
