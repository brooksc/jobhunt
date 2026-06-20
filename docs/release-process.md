# Release Process

How to ship a new version of Jobhunt. There are two distribution channels:

| Channel | Artifact | Workflow | Status |
|---|---|---|---|
| **Developer ID / DMG** (direct download) | notarized `.dmg` + Sparkle `appcast.xml` | `.github/workflows/release-dmg.yml` | **Live** — primary channel |
| **Mac App Store (MAS)** | `.pkg` for App Store Connect | `.github/workflows/release-mas.yml` | **Deferred** — needs setup (see below) |
| **Chrome extension** | `jobhunt-capture-<v>.zip` | `release-extension.yml` (auto-publish to CWS on tag) | Live once `CWS_*` secrets set |

Both app channels share the **same source and version**. A `vX.Y.Z` tag drives the DMG release and
(in parallel) the Chrome extension publish; MAS is built on demand.

> First native release was **v1.0.1 (2026-06-20)**. The earlier `v0.2.x` GitHub releases were the
> legacy Electron app.

---

## 0. One-time setup (already done — for reference / a new machine or repo)

All signing happens in CI from repository **GitHub Actions secrets**. `gh secret list` should show:

### DMG (Developer ID) — required, configured
| Secret | What it is | How to produce |
|---|---|---|
| `APPLE_TEAM_ID` | 10-char team ID (`SU999VT2G2`) | `security find-identity -v -p codesigning` → the `(…)` suffix |
| `APPLE_ID` | Apple ID email for notarization | your developer-account email |
| `APPLE_APP_SPECIFIC_PASSWORD` | notarytool password | appleid.apple.com → Sign-In & Security → App-Specific Passwords |
| `DEVELOPER_ID_CERT_BASE64` | "Developer ID Application" cert as base64 `.p12` | Keychain → export identity → `base64 -i cert.p12 \| gh secret set …` |
| `DEVELOPER_ID_CERT_PASSWORD` | the `.p12` export password | chosen at export time |
| `SPARKLE_EDDSA_PRIVATE_KEY` | Sparkle update-signing private key | `generate_keys -x file` from Sparkle's bin (keychain → file) |

The Sparkle **public** key lives in `Project.swift` (`sparklePublicEDKey`) and ships in the app
Info.plist as `SUPublicEDKey`. `GITHUB_TOKEN` is provided automatically by Actions (the workflows
set it as job env so `mise` authenticates GitHub API calls).

Creating the Developer ID cert: Xcode → Settings → Accounts → Manage Certificates → **+** →
**Developer ID Application** (requires being the team **Account Holder** with a paid membership).

### MAS (App Store) — NOT yet configured
Needed only when enabling the MAS channel (see §5):
| Secret | What it is |
|---|---|
| `MAS_CERT_BASE64` / `MAS_CERT_PASSWORD` | "3rd Party Mac Developer Application" cert `.p12` (signs the app) |
| `MAS_INSTALLER_CERT_BASE64` / `MAS_INSTALLER_CERT_PASSWORD` | "3rd Party Mac Developer Installer" / "Mac Installer Distribution" cert `.p12` (signs the `.pkg`) |
| `APPLE_TEAM_ID` | shared with DMG (already set) |

You also need an **App Store Connect app record** (bundle id `com.jobhunt-app.jobhunt`) before the
first `.pkg` can be uploaded.

---

## 1. Pre-release checklist (every release)

Do these **before** tagging:

1. **Pick the version** `X.Y.Z` (semver). Update all three to the *same* value — a mismatch fails
   the `version-parity` gate and the release workflows:
   - `Project.swift` → `.marketingVersion("X.Y.Z")`
   - `extension/manifest.json` → `"version": "X.Y.Z"`
   - (The git tag will be `vX.Y.Z`.)

2. **⚠️ Bump `currentProjectVersion` in `Project.swift`** to a value **strictly greater** than the
   last release's. This is `CFBundleVersion`, which **Sparkle compares to decide if an update is
   available**. It is a fixed constant today — if you forget to bump it, existing users are **never
   offered the update** even though `marketingVersion` changed, and nothing flags it (version-parity
   only checks `marketingVersion`). Use a monotonic value (e.g. a `YYYYMMDDHHMM` timestamp). See
   TASK-571 for automating this.

3. **Green `main`**: confirm the latest `main` commit passed `Swift Build` (build + fast gate +
   `swiftlint --strict` + `swiftformat`), `gitleaks`, and `Version Parity`.

4. **Changelog / release notes**: draft what's new (the GitHub release body). Past releases edited the
   notes on the GitHub release after the workflow created it.

5. Commit the version bumps to `main` (SSH-signed; 1Password unlocked).

---

## 2. Cut a DMG release

```bash
# from a clean, up-to-date main with the version bumps committed & pushed
git push origin main

git tag -a vX.Y.Z -m "Jobhunt vX.Y.Z"
git push origin vX.Y.Z
```

Pushing the `vX.Y.Z` tag triggers **`release-dmg.yml`** (and `gitleaks` + `version-parity`). It does
**not** trigger MAS (that's `workflow_dispatch`-only until §5). Watch it:

```bash
gh run watch "$(gh run list --workflow=release-dmg.yml --limit 1 --json databaseId -q '.[0].databaseId')"
```

### What `release-dmg.yml` does (for reference)
1. **Verify version consistency** — tag == `marketingVersion` == extension version.
2. **Install mise** (with shims on PATH + `mise reshim`) → `tuist generate`.
3. **Run fast-gate tests** — CoreTests + ServerTests + MCPTests only (not AppUITests).
4. **Import Developer ID cert** (after tests — importing replaces the keychain search list, which
   would break the Keychain unit tests if done first).
5. **Archive** with manual Developer ID signing (`CODE_SIGN_STYLE=Manual`).
6. **Export app from the `.xcarchive`** via `ditto` (not `exportArchive` — its IDEDistribution errors
   on the runner's Xcode).
7. **Re-sign Sparkle's nested helpers** (`Updater.app`, `Autoupdate`, XPC services) inside-out with
   `--options runtime --timestamp` — Xcode's archive signing skips them, which otherwise makes
   notarization fail.
8. **Smoke check** — app + MCP helper + Sparkle embedded & signed with hardened runtime.
9. **Create DMG** → **Notarize** (`notarytool --wait`, must report `Accepted`) → **staple**.
10. **EdDSA-sign + publish `appcast.xml`** (Sparkle `generate_appcast`).
11. **Package the Chrome extension** zip.
12. **Upload** DMG + `.sha256` + `appcast.xml` + provenance + extension zip to the GitHub release.

### Verify the published DMG (do this every release)
```bash
cd /tmp
curl -fsSL -o jh.dmg "https://github.com/brooksc/jobhunt/releases/download/vX.Y.Z/Jobhunt-vX.Y.Z.dmg"
xcrun stapler validate jh.dmg                 # → "The validate action worked!"
hdiutil attach jh.dmg -nobrowse -quiet -mountpoint /tmp/jhmnt
spctl -a -t exec -vvv /tmp/jhmnt/Jobhunt.app  # → "accepted, source=Notarized Developer ID"
hdiutil detach /tmp/jhmnt -quiet
curl -fsSL "https://github.com/brooksc/jobhunt/releases/latest/download/appcast.xml"  # has sparkle:edSignature
```

Then **edit the GitHub release notes** with the changelog and publish.

### Confirm auto-update actually works
On a Mac running the **previous** version: **Check for Updates…** (app menu) should find the new
build and install it. This is the real test that `currentProjectVersion` was bumped and the appcast
signature verifies.

---

## 3. Sparkle auto-update notes

- The app checks `SUFeedURL` = `https://github.com/brooksc/jobhunt/releases/latest/download/appcast.xml`,
  which GitHub serves from the newest non-prerelease release.
- Each release publishes a single-item `appcast.xml` for that version, EdDSA-signed with
  `SPARKLE_EDDSA_PRIVATE_KEY`. A tampered DMG fails signature verification.
- Update detection compares `CFBundleVersion` (`sparkle:version`) — **bump `currentProjectVersion`**
  (see §1.2).
- If you ever rotate the Sparkle key: regenerate with `generate_keys`, update `sparklePublicEDKey` in
  `Project.swift` **and** the `.gitleaks.toml` allowlist, and reset `SPARKLE_EDDSA_PRIVATE_KEY`. This
  invalidates updates for users on the old key (they re-download manually once).

---

## 4. Chrome extension (Chrome Web Store)

**Automated:** `release-extension.yml` runs on every `v*` tag (and via manual dispatch). It verifies
the manifest version matches the tag, packages the zip, uploads it as a build artifact, and — when
the `CWS_*` secrets are configured — **uploads it to the Chrome Web Store and submits it for review**
(`--auto-publish`). If the secrets aren't set, it skips the store upload (the tag still succeeds) and
just produces the zip. CWS still reviews each new version before it goes live (hours–days).

The extension version must match the app version (enforced by `version-parity`), and the store
**rejects re-uploading an already-published version** — so each release tag must carry a new version.

### One-time setup — Chrome Web Store API credentials
Needed to enable the automated upload. All go in repo **Actions secrets**:

| Secret | What it is |
|---|---|
| `CWS_EXTENSION_ID` | the published item id — `jekcbebhfeidkpapienoflbcaeeknlch` |
| `CWS_CLIENT_ID` / `CWS_CLIENT_SECRET` | OAuth 2.0 **Desktop app** client from Google Cloud |
| `CWS_REFRESH_TOKEN` | a refresh token for that client (one-time OAuth flow) |

Steps:
1. [Google Cloud Console](https://console.cloud.google.com) → create/select a project → **APIs &
   Services → Library** → enable **Chrome Web Store API**.
2. **OAuth consent screen** → External; add your own Google account as a **Test user**.
3. **Credentials → Create credentials → OAuth client ID → Desktop app** → copy the **client ID** +
   **client secret**.
4. Get a refresh token (interactive, one-time):
   ```bash
   npx --yes chrome-webstore-upload-keys
   ```
   It opens a browser, you authorize, and it prints the **refresh token**.
5. Load the secrets:
   ```bash
   printf 'jekcbebhfeidkpapienoflbcaeeknlch' | gh secret set CWS_EXTENSION_ID
   printf '<client-id>'      | gh secret set CWS_CLIENT_ID
   printf '<client-secret>'  | gh secret set CWS_CLIENT_SECRET
   printf '<refresh-token>'  | gh secret set CWS_REFRESH_TOKEN
   ```

### Manual / draft upload
- Trigger **Actions → Release Extension → Run workflow**; untick **publish** to upload as a *draft*
  (review/publish later in the dashboard) instead of submitting for review.
- Or fully manual: download the zip from the GitHub release (or run `./scripts/package-extension.sh`)
  and upload at the [CWS Developer Dashboard](https://chrome.google.com/webstore/devconsole). Use the
  reviewer notes in `docs/chrome-web-store-review.md`.

After the **first** publish of a new extension id, add it to `JobhuntServer.allowedExtensionOrigins`
(CORS allowlist) — see the note in the root `CLAUDE.md`. (The current id is already published.)

---

## 5. Mac App Store (MAS) release — deferred

MAS is **not** wired to tags yet: `release-mas.yml` is `workflow_dispatch`-only and the `MAS_*`
secrets aren't set. To enable it:

### One-time
1. Create the two certs in the Apple Developer portal / Xcode and export each as `.p12`:
   - **3rd Party Mac Developer Application** (signs the app)
   - **3rd Party Mac Developer Installer** / **Mac Installer Distribution** (signs the `.pkg`)
2. Load the four `MAS_*` secrets (see §0).
3. Create the **App Store Connect** app record for `com.jobhunt-app.jobhunt`.
4. (Optional) Re-enable the tag trigger in `release-mas.yml` by restoring:
   ```yaml
   on:
     push:
       tags: ['v*']
   ```
   Leave it on `workflow_dispatch` if you prefer to release MAS on demand rather than every tag.

### Each MAS release
- Trigger manually: **Actions → Release MAS → Run workflow** on the `vX.Y.Z` tag, or push the tag if
  you re-enabled the trigger.
- `release-mas.yml` generates the project with **`TUIST_MAS_ONLY=1`** (excludes Sparkle — the App
  Store bans third-party updaters), archives `Release-MAS` (App Sandbox, no MCP helper), exports an
  App-Store `.pkg`, smoke-checks (sandbox entitlements present, no MCP helper, **no Sparkle**), and
  uploads the `.pkg` as a workflow artifact.
- **Upload to App Store Connect**: download the `.pkg` artifact and upload via **Transporter** (the
  workflow does not auto-submit), then submit for review in App Store Connect.
- Before shipping a MAS build, run the sandbox checks in **`docs/MAS-VALIDATION.md`** (localhost
  networking, resume PDF import, user-selected file writes) against a real MAS-signed build.

### DMG vs MAS data stores
They use **separate** stores (MAS is sandboxed). See the "Data store location" section in the root
`CLAUDE.md` — a DMG and a MAS install can't live-share; pick one as primary per machine.

---

## 6. Troubleshooting

Most of these were first-run bugs already fixed in the workflows; listed so a regression is
recognizable.

| Symptom | Cause / fix |
|---|---|
| `tuist: command not found` (exit 127) | mise shims not on PATH — workflow adds `~/.local/share/mise/shims` + `mise reshim`. |
| `Install pinned tools` 403 rate limit | mise unauthenticated GitHub API — workflow sets `GITHUB_TOKEN` job env. |
| `SettingsStore...Keychain` tests fail in release only | cert import ran before tests and replaced the keychain search list — import is after tests. |
| Archive: "conflicting provisioning settings" | manual Developer ID signing needs `CODE_SIGN_STYLE=Manual` (project uses automatic signing by default). |
| Export: "Unknown Distribution Error / method expected one {}" | `exportArchive` on the runner's Xcode — workflow copies the signed app from the `.xcarchive` via `ditto` instead. |
| Notarization `Invalid` on `Sparkle.framework/.../Updater` or `Autoupdate` | Xcode doesn't re-sign Sparkle's nested helpers — the "Re-sign Sparkle nested code" step signs them inside-out with `--options runtime --timestamp`. Fetch the reason: `xcrun notarytool log <submission-id> --apple-id … --password … --team-id …`. |
| `stapler` Error 65 after notarize | submission was `Invalid` but `notarytool --wait` exited 0 — the step now parses status and requires `Accepted`. |
| gitleaks fails on a key string | if it's a genuinely public key (e.g. `SUPublicEDKey`), allowlist it in `.gitleaks.toml`; otherwise it's a real leak. |
| Users not offered the update | `currentProjectVersion` wasn't bumped (see §1.2). |

To inspect a failed run:
```bash
gh run view <run-id>
gh run view --job=<job-id> --log-failed
```

---

## 7. Rollback

A GitHub release can be deleted and the tag re-cut, but **once users have downloaded a DMG or it's
been served via the appcast, treat it as published.** Prefer rolling *forward* with a higher version.
If a release is bad:

1. Delete the GitHub release (or mark it a pre-release so `…/releases/latest` skips it — this also
   stops the appcast from serving it).
2. Fix forward: bump to the next patch version (and `currentProjectVersion`), re-tag.

Do **not** reuse a version number that users may already have.
