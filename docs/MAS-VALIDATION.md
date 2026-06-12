# MAS Sandbox Validation Checklist

## Top risk: sandbox localhost networking
The MAS build uses app-sandbox with network.server + network.client entitlements.

### Test procedure (requires a real MAS-signed build)
1. Build with Release-MAS configuration and real 3rd Party Mac Developer cert
2. Install the signed .pkg
3. Launch and capture a job via the Chrome extension → verify it appears in the app
4. Configure LM Studio (localhost:1234) → verify extraction runs
5. Configure a cloud provider (OpenAI) → verify request succeeds + consent gate enforced
6. Verify /api/ping returns from localhost:8765-8769

### Known risk
- PNA (Private Network Access) header may be blocked under strict sandbox
- Workaround: ensure Access-Control-Allow-Private-Network: true header is set in JobhuntServer
- If extension capture fails under sandbox: file radar, escalate immediately

## Resume PDF import (Settings and onboarding)

Both import paths call `startAccessingSecurityScopedResource()` before reading the selected URL
and balance it with `stopAccessingSecurityScopedResource()` in a `defer` block.

### Test procedure
1. Build and run the MAS-signed build (or enable App Sandbox in the local scheme via Xcode settings)
2. Open Settings → Resumes → Add Resume → Import PDF…
3. Select a PDF that lives **outside** the app container (e.g. ~/Desktop/resume.pdf)
4. Confirm the PDF text appears in the text editor — import must not silently fail
5. Repeat via Onboarding → Import from file → select the same PDF → same expectation

### Known risk
- If `startAccessingSecurityScopedResource()` returns false, the import is silently skipped.
  Add a user-visible error if this proves common in the field.

## PrivacyInfo.xcprivacy and App Store Privacy Assessment

### Determination: NSPrivacyCollectedDataTypes is correctly empty

The developer collects no user data. The rationale is recorded here and in the comment in
`app/Resources/PrivacyInfo.xcprivacy`.

**Data flows audited:**

| Data | Destination | Consent gate |
|---|---|---|
| Job description text (capture) | Configured LLM provider only | Required for cloud/remote |
| Resume text | Configured LLM provider only (fit scoring) | Required for cloud/remote |
| API keys | Provider endpoint (as auth header); stored in Keychain | n/a — user-entered |
| All other settings | Local SwiftData / Keychain only | n/a |
| MCP read queries | User's local AI assistant (stdio) | n/a — user-initiated |

**Cloud/remote LLM transmission:**

When the user configures a cloud provider (OpenAI, Anthropic, Google, OpenRouter) or a
non-loopback custom endpoint, job and resume text is sent from the user's device directly
to that third-party provider under the provider's privacy policy. `ConsentHelper.isConsented`
is called in `QueueActor.swift` before every extraction request **and** before every
fit-scoring request (`processFitRequest`) — if consent has not been granted, the request
is immediately marked failed and no data is transmitted. This is verified by
`testFitRequest_consentMissing_marksRequestFailed` in `ExtractionEngineTests`.

The developer receives none of this data.

**Local and loopback providers (LM Studio, Foundation Models, custom on 127.0.0.1/localhost/::1):**
No data leaves the device.

### App Store Connect privacy questionnaire guidance

- **Data collected by this app** → No (developer collects nothing)
- **Third-party analytics/crash** → No (none integrated)
- The user-directed transmission to user-configured AI providers is not "data collected by
  the developer" under Apple's definition — it is the user deliberately sending their own
  content to a service they chose.

### Re-review trigger

Repeat this assessment before each MAS submission and after any of these changes:
- New network endpoint added to the app or MCP layer
- New analytics, telemetry, or crash reporting integrated
- TASK-151 (MCP raw captured text exposure) completed — review whether MCP tool responses
  constitute a new data flow requiring disclosure

## Transporter upload procedure
1. Download Transporter from Mac App Store
2. Sign in with Apple ID that has App Store Connect access
3. Open the .pkg artifact from CI
4. Click Deliver → follow prompts
