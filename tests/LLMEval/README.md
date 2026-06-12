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

A running OpenAI-compatible LLM endpoint (e.g. LM Studio on port 1234).

## Running

**Reporting mode:**
```sh
JOBHUNT_LLM_URL=http://127.0.0.1:1234 \
  xcodebuild test -scheme Jobhunt-DMG -only-testing:LLMEval
```

**Threshold mode (fail below 80%):**
```sh
JOBHUNT_LLM_URL=http://127.0.0.1:1234 \
JOBHUNT_LLM_MIN_ACCURACY=80 \
  xcodebuild test -scheme Jobhunt-DMG -only-testing:LLMEval
```

Override the model (defaults to `gemma-4-e4b-it-mlx`):
```sh
JOBHUNT_LLM_URL=http://127.0.0.1:1234 \
JOBHUNT_LLM_MODEL=my-model-name \
  xcodebuild test -scheme Jobhunt-DMG -only-testing:LLMEval
```

Alternatively, write the base URL to `~/.jobhunt-lmstudio-url` and omit the env var:
```sh
echo "http://127.0.0.1:1234" > ~/.jobhunt-lmstudio-url
xcodebuild test -scheme Jobhunt-DMG -only-testing:LLMEval
```

## Fixtures

Three synthetic job descriptions covering:
- Remote role with salary bands and application URL
- Hybrid/contract role with hourly pay
- Multi-band US salary with metro override

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
