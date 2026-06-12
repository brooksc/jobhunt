# Third-Party Notices

This file records provenance and license information for vendored third-party code.

---

## Readability.js

- **Source**: https://github.com/mozilla/readability
- **Version/Commit**: unknown — no version tag in file header; file references Arc90's readability.js 1.7.1 as upstream basis. See update procedure below to pin to a specific release.
- **License**: Apache-2.0
- **SHA256**: `e9330028c8a5a4aa7d75147be2605d520f7f213c7b28474947dc0e9c984e9bed`
- **Vendored at**: `extension/Readability.js`
- **Date vendored**: 2026-06-01 (from `git log --follow -- extension/Readability.js | tail -1`)

### Update procedure

To update Readability.js to a newer version:
1. Download the release from https://github.com/mozilla/readability/releases or the npm package `@mozilla/readability`
2. Copy `Readability.js` to `extension/Readability.js`
3. Verify the license header is intact
4. Update the version, SHA256, and date in this file
5. Run extension capture tests to verify parsing still works
