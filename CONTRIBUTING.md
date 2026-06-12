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

**Fast gate** (CoreTests + ServerTests + MCPTests, ~30s) — this is what CI runs:

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
JOBHUNT_LLM_URL=http://127.0.0.1:1234 xcodebuild test \
  -project Jobhunt.xcodeproj \
  -scheme Jobhunt-DMG \
  -configuration Debug-DMG \
  -destination 'platform=macOS' \
  -only-testing:LLMEval \
  CODE_SIGNING_ALLOWED=NO
```

To enforce a minimum accuracy threshold (e.g. 80%), add `JOBHUNT_LLM_MIN_ACCURACY=80`. See [tests/LLMEval/README.md](tests/LLMEval/README.md) for full details.


See [README.md](README.md#test) for full details on each lane.
