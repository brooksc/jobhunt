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

**LLM eval** (opt-in; needs a real provider and **costs money** on a hosted one):

```bash
# LLMEval lives in the opt-in Jobhunt-Eval scheme (NOT Jobhunt-DMG, which never runs it).
TEST_RUNNER_JOBHUNT_EVAL_PROVIDER=lmstudio \
TEST_RUNNER_JOBHUNT_LLM_URL=http://127.0.0.1:1234 \
  xcodebuild test \
  -project Jobhunt.xcodeproj \
  -scheme Jobhunt-Eval \
  -destination 'platform=macOS' \
  -only-testing:LLMEval \
  CODE_SIGNING_ALLOWED=NO
```

> **The `TEST_RUNNER_` prefix is required, not cosmetic.** `xcodebuild` does not forward arbitrary
> environment variables to the test process — only `TEST_RUNNER_`-prefixed ones arrive. An unprefixed
> variable is **silently ignored** and the harness falls back to its config file, so a run that looks
> like it measured what you asked can quietly have measured something else, with no error anywhere.
> This bit us while validating TASK-668; the only giveaway was that the `pass N/5` lines never
> printed. See the comment at the top of `tests/LLMEval/EvalProvider.swift`.

Because of that, the harness prefers **files outside the repo** — which also means an API key can't be
committed by accident. Each setting is read from its environment variable, else
`~/.config/jobhunt/<file>`:

| Setting | Env var | File |
|---|---|---|
| Provider (`lmstudio`, `openrouter`, `google`, …) | `JOBHUNT_EVAL_PROVIDER` | `eval-provider` |
| Model | `JOBHUNT_EVAL_MODEL` | `eval-model` / `eval-models` |
| API key (per provider) | `JOBHUNT_EVAL_API_KEY_<PROVIDER>` | `eval-api-key-<provider>` |
| API key (fallback) | `JOBHUNT_EVAL_API_KEY` | `eval-api-key` |
| Base URL | `JOBHUNT_EVAL_BASE_URL` / `JOBHUNT_LLM_URL` | `eval-base-url` |
| Repeats per case | `JOBHUNT_EVAL_REPEATS` | `eval-repeats` |

To enforce a minimum accuracy threshold (e.g. 80%), add `JOBHUNT_LLM_MIN_ACCURACY=80`. See
[tests/LLMEval/README.md](tests/LLMEval/README.md) for full details.

A local provider (LM Studio) costs nothing and is the right default while iterating. Evaluating
against a **hosted** model spends real money — budget before you run, and see the LLM-spend section in
[`CLAUDE.md`](CLAUDE.md) for measured per-call costs and what a given number of calls actually buys.

## Credentials — what you need, for what

**Most work needs nothing.** Building, the fast gate, the full CI-equivalent gate, the extension
tests, and AppUITests all run with no credentials at all. Only three things do, and they're separable:

| To do this | You need | Where it lives |
|---|---|---|
| Build, test, lint, run UI tests | *nothing* | — |
| **Run the app** and have extraction/scoring work | an AI provider API key, entered in Settings → AI | macOS **Keychain** (never in the repo, never in a store backup) |
| **Run LLM evals** | a provider + key, per the table above | `~/.config/jobhunt/eval-api-key-<provider>` |
| **Cut a release** | the signing secrets below | GitHub Actions secrets + the maintainer's keychain |

Nothing secret belongs in the repo. A `gitleaks` pre-commit hook and CI check are there to catch a
slip, but they're a backstop, not the policy.

### Release secrets (maintainer only)

Releases run entirely in GitHub Actions, which holds 13 repository secrets. **GitHub secrets are
write-only — you cannot read any of them back**, so the authoritative copy has to live somewhere else
(a password manager). Sorted by what happens if you lose one:

**Irreplaceable — the issuer will not give you the same one twice:**

- `SPARKLE_EDDSA_PRIVATE_KEY` — signs the Sparkle appcast. Lose it and **every installed copy is
  permanently cut off from auto-update**, because the documented remedy (ship a build carrying a new
  public key) can only reach users through the update mechanism you just lost. This is the single
  worst thing to lose in the project.
- `~/.appstoreconnect/private_keys/AuthKey_*.p8` — App Store Connect API keys. Apple issues a `.p8`
  exactly once. (Note `AuthKey_68BGNV3CCC.p8` belongs to a *sibling* project sharing this Apple team —
  don't revoke it while tidying.)
- `CWS_REFRESH_TOKEN` — Chrome Web Store OAuth. Regenerable, but only by re-running the consent flow.

**Recoverable with effort** — the Developer ID and Apple Distribution signing identities live in the
maintainer's login keychain, not as files. Losing the private key doesn't break anything already
shipped (a notarized build keeps launching, because its signature carries a secure timestamp); you
revoke and reissue before the next build. Export each as a `.p12` (certificate *and* private key) to a
password manager anyway — a keychain doesn't survive a wiped machine.

**Regenerable in minutes from the relevant portal:** `APPLE_APP_SPECIFIC_PASSWORD`, `MAS_CERT_*`,
`MAS_PROVISIONING_PROFILE_BASE64`, `CWS_CLIENT_ID`, `CWS_CLIENT_SECRET`. `APPLE_ID` and
`APPLE_TEAM_ID` aren't really secrets.

> **Certificate expiry is a real deadline.** Check yours before assuming you can ship:
> ```bash
> security find-certificate -c "Developer ID Application" -p | openssl x509 -noout -enddate
> ```
> After it expires you cannot sign a new DMG until you renew *and* update
> `DEVELOPER_ID_CERT_BASE64`. Nothing already released is affected. As of 2026-09-04 the current
> Developer ID certificate expires **2027-02-01** and Apple Distribution **2027-06-21**.

`llm-eval.yml` also references `JOBHUNT_LLM_URL` and `JOBHUNT_LLM_API_KEY`, which are **not currently
set** as repository secrets — that workflow cannot run as configured. It's manual-dispatch only and
costs money per run, so this may be deliberate; it is not evidence of a break.

## Coming back to this after a long gap

If it's been months, do these in order before trusting anything:

1. `mise install` — the toolchain is pinned in `.mise.toml`, and a `swiftlint`/`swiftformat` earlier
   on your `PATH` will disagree with the gate. Resolve the pinned binaries explicitly if in doubt.
2. `tuist generate --no-open` — the `.xcodeproj` is generated and not committed.
3. Run the **full CI-equivalent gate** above, not just the fast one.
4. Check certificate expiry (command above) *before* planning a release, not during one.
5. If the app's provider stops working, the model may simply have been retired. The model field is
   free text in Settings → AI — type a current model ID. Only the default recommendation is hardcoded
   (`core/LLM/ModelRecommendation.swift`).
6. Back up the SwiftData store before running any `JobhuntMigrator` mode against it —
   `scripts/backup-store.sh`, with the app quit. Copy `jobhunt.store` **and** its `-shm` **and**
   `-wal`; a `.store`-only copy silently loses recent changes.

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
