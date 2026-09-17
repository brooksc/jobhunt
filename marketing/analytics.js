// PostHog analytics — marketing site only (jobhunt-app.com).
//
// Deliberately NOT used in the Mac app or the Chrome extension: PRIVACY.md states the app has no
// analytics, no telemetry and no crash reporting, and that remains true. This file only ever runs
// on the public website.
//
// CONSENT-GATED, NOT COOKIELESS-ALWAYS (changed 2026-09-16).
//
// This used to run `cookieless_mode: 'always'`, which stored nothing on the device. That needed no
// banner, but it also made returning visitors unmeasurable: PostHog derives the distinct ID from a
// salt that rotates daily, so the same person counts as new every day and retention cannot be read
// at all. Measuring returning users requires storing an identifier, and storing an identifier for
// analytics is exactly what EU/UK ePrivacy requires consent for — so the banner is not optional
// paperwork, it is the thing that makes the storage lawful.
//
// Three states, and the default is the private one:
//
//   no choice yet  -> cookieless. Counted anonymously, nothing stored, banner shown.
//   accepted       -> persistent ID in localStorage + cookie. Returning visitors are visible.
//   declined       -> cookieless, permanently. Still counted, still anonymous, banner gone.
//
// Declining does not mean "not counted". It means "counted without being remembered", which is what
// the old behaviour was for everyone. Page-view totals stay correct either way; only cross-day
// identity depends on consent.
//
// The consent choice itself is kept in localStorage. Storing a record of someone's privacy
// preference is permitted without consent under the "strictly necessary" exemption — the whole point
// of it is to honour a choice they made, and the alternative is asking again on every page.
//
// The project token below is public by design — a write-only client token meant to be embedded in
// browser-shipped code, like a Sentry DSN or a GA tracking ID.

(function () {
  var TOKEN = 'phc_qNZcpeGwgfKCViFpw3iQyqfuXMuPDPHGKBNLMC9dDf8S';
  var KEY = 'jh_analytics_consent'; // 'granted' | 'declined'

  // Storage can throw (Safari private browsing, blocked site data, embedded webviews). A failure
  // here must degrade to "no consent recorded", never break the page.
  function readConsent() {
    try {
      return window.localStorage.getItem(KEY);
    } catch (e) {
      return null;
    }
  }
  function writeConsent(value) {
    try {
      window.localStorage.setItem(KEY, value);
    } catch (e) {
      /* If we cannot remember the choice we also cannot honour it persistently — stay cookieless. */
    }
  }

  var consent = readConsent();
  var granted = consent === 'granted';

  posthog.init(TOKEN, {
    api_host: 'https://us.i.posthog.com',
    // 'never' lets PostHog assign and store a stable ID; 'always' keeps the old server-derived,
    // daily-rotating one. The persistence setting has to agree with it, or PostHog has an ID it is
    // not allowed to write down.
    cookieless_mode: granted ? 'never' : 'always',
    persistence: granted ? 'localStorage+cookie' : 'memory',
    // Both need device storage and neither is worth asking for on a five-page marketing site.
    disable_session_recording: true,
    disable_surveys: true,
  });

  if (consent) return; // Choice already made — no banner.

  // ── Banner ────────────────────────────────────────────────────────────────────────────────────
  // Built in JS rather than sitting in every page's markup so there is one copy to change, and so a
  // visitor who has already chosen never has it in their DOM at all.

  function render() {
    var bar = document.createElement('div');
    bar.setAttribute('role', 'dialog');
    bar.setAttribute('aria-label', 'Analytics preference');
    bar.style.cssText = [
      'position:fixed', 'left:16px', 'right:16px', 'bottom:16px', 'z-index:9999',
      'max-width:720px', 'margin:0 auto', 'padding:16px 18px',
      'background:#1a1d27', 'color:#f0f2f8',
      'border:1px solid rgba(255,255,255,.14)', 'border-radius:12px',
      'box-shadow:0 18px 50px rgba(0,0,0,.45)',
      'font:14px/1.6 -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif',
      'display:flex', 'flex-wrap:wrap', 'gap:12px', 'align-items:center',
      'justify-content:space-between',
    ].join(';');

    var text = document.createElement('p');
    text.style.cssText = 'margin:0;flex:1 1 320px;color:#c9cedb';
    text.innerHTML =
      'We count page views to see which pages are worth improving. Allowing a cookie lets us tell a ' +
      'returning visitor from a new one. Decline and you are still counted — just not remembered. ' +
      '<a href="/privacy" style="color:#3b82f6">Privacy</a>';

    var actions = document.createElement('div');
    actions.style.cssText = 'display:flex;gap:8px;flex:0 0 auto';

    function button(label, primary) {
      var b = document.createElement('button');
      b.type = 'button';
      b.textContent = label;
      b.style.cssText = [
        'padding:9px 16px', 'border-radius:8px', 'font-size:14px', 'font-weight:600',
        'cursor:pointer', 'font-family:inherit',
        primary ? 'background:#3b82f6' : 'background:transparent',
        primary ? 'color:#fff' : 'color:#f0f2f8',
        primary ? 'border:1px solid #3b82f6' : 'border:1px solid rgba(255,255,255,.2)',
      ].join(';');
      return b;
    }

    var decline = button('Decline', false);
    var accept = button('Allow', true);

    decline.addEventListener('click', function () {
      writeConsent('declined');
      bar.remove();
      // Nothing to reconfigure: already cookieless, and it stays that way.
    });

    accept.addEventListener('click', function () {
      writeConsent('granted');
      bar.remove();
      // Switch this pageview onto a stored ID without a reload. set_config is PostHog's supported
      // way to change these after init; if a future version drops it, the next page load still
      // picks the right mode up from localStorage, so the failure is a delay, not a loss.
      try {
        posthog.set_config({ cookieless_mode: 'never', persistence: 'localStorage+cookie' });
      } catch (e) {
        /* next navigation initialises correctly anyway */
      }
    });

    actions.appendChild(decline);
    actions.appendChild(accept);
    bar.appendChild(text);
    bar.appendChild(actions);
    document.body.appendChild(bar);
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', render);
  } else {
    render();
  }
})();
