# LLM Extraction Eval

An XCTest harness that runs synthetic job description fixtures through
`ExtractionEngine.extract` — the same production path used at runtime —
and prints a field-by-field accuracy report.

## Modes

### Reporting mode (default)

The test **skips** gracefully when no provider is reachable and **never
fails** on low accuracy. Use this for local experimentation.

### Threshold mode

Set `JOBHUNT_LLM_MIN_ACCURACY` to an integer percentage. The test fails
when overall accuracy falls below that value. Use this as a release gate
or in CI to prevent regressions.

## Prerequisites

A running OpenAI-compatible LLM endpoint (e.g. LM Studio on port 1234) with a model loaded.
Both the endpoint URL and the model id are **required** — there is no hardcoded default model.

## Running

The eval has its own scheme (`Jobhunt-Eval`), kept out of the normal test gate. Simplest path is
the wrapper script:

```sh
# Reporting mode (prints accuracy, never fails)
scripts/run-eval.sh gemma-4-e2b-it-mlx

# Threshold mode (fail below 80%)
scripts/run-eval.sh gemma-4-e2b-it-mlx 80
```

It defaults the endpoint to `http://127.0.0.1:1234`; override with `JOBHUNT_LLM_URL`.

### Or invoke xcodebuild directly

```sh
JOBHUNT_LLM_URL=http://127.0.0.1:1234 \
JOBHUNT_LLM_MODEL=gemma-4-e2b-it-mlx \
  xcodebuild test -project Jobhunt.xcodeproj -scheme Jobhunt-Eval \
  -destination 'platform=macOS' -only-testing:LLMEval CODE_SIGNING_ALLOWED=NO
```

Set `JOBHUNT_LLM_MIN_ACCURACY` to enable threshold mode. The base URL may also be written to
`~/.jobhunt-lmstudio-url` instead of passing `JOBHUNT_LLM_URL`.

## Fixtures

Synthetic job postings covering two paths:

**Extraction-only** (pre-cleaned `description` → extract):
- Remote role with salary bands and application URL
- Hybrid/contract role with hourly pay
- Multi-band US salary with metro override

**End-to-end** (raw `selectedText`/`visibleText`/`structuredData` → `cleanDescription` → extract) — these
also exercise the cleaning pipeline (boilerplate stripping, JSON-LD preference, selection dedupe):
- Boilerplate-heavy page with the salary only in JSON-LD
- Substantial JSON-LD body that should be preferred over page nav

## Output

```
=== LLM Extraction Eval ===
Provider URL: http://127.0.0.1:1234
Model: gemma-4-e4b-it-mlx
Reporting mode: no accuracy threshold

--- remote salary bands and application URL ---
  Model: gemma-4-e4b-it-mlx  chars: 842
  [PASS] company: got=ExampleCloud  expected=ExampleCloud
  [PASS] title: got=Principal Technical Program Manager, AI Platform  expected=contains 'Technical Program Manager'
  ...
  Score: 7/8 (87%)

=== Overall: 21/24 checks passed (87%) ===
```

In threshold mode, the test fails with a message like:
```
XCTAssertGreaterThanOrEqual failed: ("72") is less than ("80") - Accuracy 72% is below threshold 80%.
```
