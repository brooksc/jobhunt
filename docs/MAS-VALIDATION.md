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

## Transporter upload procedure
1. Download Transporter from Mac App Store
2. Sign in with Apple ID that has App Store Connect access
3. Open the .pkg artifact from CI
4. Click Deliver → follow prompts
