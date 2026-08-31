# The extension contract

The only external API surface Jobhunt must keep byte-compatible. The Chrome extension ships and updates on its own cycle through the Chrome Web Store, so an installed extension can be **older than the app** — and a user who updates the app cannot be assumed to have updated the extension, or vice versa. Breaking anything here breaks capture for people who have not updated, silently, with no error the app can show them.

This was §4 of `swift-plan.md`, the (now retired) Swift rewrite plan. It is kept because it is the one part of that plan that is still normative: the rewrite is finished, but the contract it had to preserve is permanent. Verified against the implementation on 2026-08-31.

## Routes

| Method | Path | Request | Response |
|---|---|---|---|
| GET | `/api/ping` | — | `{app:"jobhunt", version, isDemo:bool}` |
| POST | `/captures` | `{schema_version, captured_at, url, canonical_url?, page_title, selected_text?, visible_text?, structured_data?, user_note?, source}` | `{ok:true, capture_id, job_number, duplicate:bool}` |
| POST | `/site-reviews` | `{schema_version, reviewed_at, site_url, site_origin, page_title?, next_review_at?, note?}` | `{ok:true, site_review_id}` |
| GET | `/api/jobs/by-url?url=…` | query param | `{job_number}` (400 if not found) |
| POST | `/api/app/focus` | `{job_number?: number\|null}` | `{ok:true}` |

Route table: `server/swift/JobhuntServer.swift` (~`:497-501`).

## Behavioural requirements

- **Port discovery** — bind the first free port in **8765–8769**, in order. `ServerPortContract` (`core/App/ServerPortContract.swift`) is the single source of truth and `ServerPortContractTests` guards it, so any change is deliberate. There is deliberately **no ephemeral-port fallback**: an ephemeral port is undiscoverable by the extension and the MCP helper, so the server fails closed (surfaced in Settings → Local Server, with Retry) rather than running somewhere no client can reach it.
- **CORS / Private Network Access** — answer `chrome-extension://` origin preflights with `Access-Control-Allow-Private-Network: true` (`server/swift/HTTPResponse.swift:46`). Only a preflight that resolved to a real route earns it; a blanket 204 would advertise "any method, any path, private-network OK" to the browser.
- **Capture validation** — require `url`, `page_title`, and at least one of `visible_text` / `selected_text`.
- **`/api/app/focus`** must raise and focus the app window, and optionally deep-link to a job.

## Why the loopback binding is the security boundary, not CORS

`Origin` is forgeable by any local process, so the extension-route check cannot authenticate a caller. What keeps other machines out is `requiredInterfaceType = .loopback`, enforced by the OS before a request is parsed. The origin allowlist exists to stop *other Chrome extensions* driving these routes from the browser, where the same-origin policy makes `Origin` trustworthy. MCP routes carry a bearer token for a different reason: they are driven by third-party AI clients, so the token scopes which may act on the user's data. Full rationale sits above `isAllowedExtensionOrigin` in `JobhuntServer.swift`; `CLAUDE.md` summarises it.

## Changing this contract

Adding a route or an optional field is safe. Removing one, renaming one, or making an optional field required is not — it breaks every installed extension until each user updates, and the extension has no way to tell the user why capture stopped working.

If a breaking change is genuinely needed, bump `schema_version` and keep the old shape working until the store rollout has landed. Extension-side changes ship on the Chrome Web Store's review cycle, which is days, not minutes.
