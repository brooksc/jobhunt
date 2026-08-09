// PostHog analytics — marketing site only (jobhunt-app.com).
//
// Deliberately NOT used in the Mac app or the Chrome extension: PRIVACY.md
// states the app has no analytics, no telemetry and no crash reporting, and
// that remains true. This file only ever runs on the public website.
//
// Cookieless by design. `cookieless_mode: 'always'` makes PostHog derive a
// distinct ID server-side from hash(team, daily salt, IP, user agent, host)
// instead of storing anything on the visitor's device, so there are no cookies,
// no localStorage, and therefore no consent banner. The salt rotates daily, so
// a returning visitor counts as a new person each day and cross-day retention
// is not measurable. Session replay and surveys need device storage and are
// off for the same reason.
//
// The project token below is public by design — a write-only client token meant
// to be embedded in browser-shipped code, like a Sentry DSN or a GA tracking ID.
posthog.init('phc_qNZcpeGwgfKCViFpw3iQyqfuXMuPDPHGKBNLMC9dDf8S', {
  api_host: 'https://us.i.posthog.com',
  cookieless_mode: 'always',
  persistence: 'memory',
  disable_session_recording: true,
  disable_surveys: true,
});
