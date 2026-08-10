/**
 * Launch JobHunt via its URL scheme, then wait for the local server (TASK-489).
 *
 * When the app isn't running a capture just sat in the retry queue until the user happened to open
 * JobHunt — which can be days, by which time the posting may be gone.
 *
 * The scheme is used ONLY to start the app. The capture itself still goes over localhost HTTP,
 * because a capture can be ~4 MB and a URL can't be. Registering and receiving a URL scheme is
 * sandbox-safe, so this works for the MAS build as well as the DMG.
 */
(function (root, factory) {
  if (typeof module === "object" && module.exports) {
    module.exports = factory();
  } else {
    root.jobhuntLaunch = factory();
  }
})(typeof self !== "undefined" ? self : this, function () {
  /** Opt-in, and off by default: launching an app is not something to do behind someone's back. */
  const ENABLED_KEY = "jobhunt.autoLaunchEnabled";

  /**
   * How long to wait for the app to come up. Cold launch on a slow disk is a few seconds; past this
   * the capture stays queued, which is the pre-existing behaviour and a perfectly good fallback.
   */
  const READY_TIMEOUT_MS = 12000;
  const POLL_INTERVAL_MS = 500;

  /**
   * Rate-limits launch attempts. Without it, capturing three jobs in a row while the app is closed
   * fires three `jobhunt://` opens, and Chrome shows its external-protocol prompt for each.
   */
  const RELAUNCH_COOLDOWN_MS = 30000;

  const LAUNCH_URL = "jobhunt://launch";

  async function isEnabled(storageArea) {
    const stored = await storageArea.get(ENABLED_KEY);
    return stored[ENABLED_KEY] === true;
  }

  async function setEnabled(storageArea, enabled) {
    await storageArea.set({ [ENABLED_KEY]: enabled === true });
  }

  /**
   * True when enough time has passed since the last attempt.
   *
   * Deliberately takes `now` so the cooldown is testable without waiting 30 seconds.
   */
  function canAttempt(lastAttemptAt, now) {
    if (!lastAttemptAt) return true;
    return now - lastAttemptAt >= RELAUNCH_COOLDOWN_MS;
  }

  /**
   * Launch the app and poll until the server answers.
   *
   * @param deps.openURL       opens the jobhunt:// URL (chrome.tabs.update / window.open)
   * @param deps.isServerReady resolves true when /api/ping answers
   * @param deps.sleep         injected so tests don't take twelve seconds
   * @param deps.now           injected clock
   * @returns {Promise<{launched: boolean, ready: boolean, reason?: string}>}
   */
  async function launchAndWait(deps) {
    const { openURL, isServerReady, sleep, now, lastAttemptAt } = deps;

    // If it's already up there's nothing to launch — and firing the scheme anyway would raise
    // Chrome's confirmation prompt for no reason.
    if (await isServerReady()) return { launched: false, ready: true };

    if (!canAttempt(lastAttemptAt, now())) {
      return { launched: false, ready: false, reason: "cooldown" };
    }

    try {
      await openURL(LAUNCH_URL);
    } catch (error) {
      return { launched: false, ready: false, reason: String(error && error.message) };
    }

    const deadline = now() + READY_TIMEOUT_MS;
    while (now() < deadline) {
      await sleep(POLL_INTERVAL_MS);
      if (await isServerReady()) return { launched: true, ready: true };
    }
    // Not an error: the capture is already queued and will flush next time the app is seen.
    return { launched: true, ready: false, reason: "timeout" };
  }

  return {
    ENABLED_KEY,
    LAUNCH_URL,
    READY_TIMEOUT_MS,
    POLL_INTERVAL_MS,
    RELAUNCH_COOLDOWN_MS,
    isEnabled,
    setEnabled,
    canAttempt,
    launchAndWait,
  };
});
