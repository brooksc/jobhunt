# LLM Extraction Eval

An XCTest harness that runs synthetic job description fixtures through the LLM extraction
pipeline and prints a field-by-field accuracy report. The test **skips** gracefully when no
provider is reachable and **never fails** on low accuracy — it is a reporting tool, not a gate.

## Prerequisites

A running OpenAI-compatible LLM endpoint (e.g. LM Studio on port 1234).

## Running

```sh
JOBHUNT_LLM_URL=http://127.0.0.1:1234 \
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

--- remote salary bands and application URL ---
  Model: gemma-4-e4b-it-mlx  chars: 842
  [PASS] company: got=ExampleCloud  expected=ExampleCloud
  [PASS] title: got=Principal Technical Program Manager, AI Platform  expected=contains 'Technical Program Manager'
  ...
  Score: 7/8 (87%)

=== Overall: 21/24 checks passed (87%) ===
```
