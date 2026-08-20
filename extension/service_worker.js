importScripts("capture.js");
importScripts("retry_queue.js");
importScripts("launch_app.js");
importScripts("export_csv.js");

const BUILD_DATE = "2026-06-02";

// Show build date in the icon tooltip so it's easy to confirm the loaded version
chrome.action.setTitle({ title: `Capture job [${BUILD_DATE}]` });

// Ports to probe when looking for the jobhunt server. MUST match the shared port contract in
// core/App/ServerPortContract.swift (8765–8769) — the app server binds only these and never an
// ephemeral port (TASK-433). The extension tries each in order and caches the winner.
const CANDIDATE_PORTS = [8765, 8766, 8767, 8768, 8769];
const PING_PATH = "/api/ping";
const PORT_CACHE_KEY = "jobhuntServerPort";
const SERVER_NOT_FOUND_MESSAGE = "jobhunt server not found on any candidate port";

async function findServerPort() {
  // Return cached port if it still responds
  const cached = (await chrome.storage.session.get(PORT_CACHE_KEY))[PORT_CACHE_KEY];
  if (cached) {
    try {
      const res = await fetch(`http://127.0.0.1:${cached}${PING_PATH}`, { signal: AbortSignal.timeout(1000) });
      if (res.ok && (await res.json()).app === "jobhunt") return cached;
    } catch (_) { /* fall through and re-probe */ }
    await chrome.storage.session.remove(PORT_CACHE_KEY);
  }

  for (const port of CANDIDATE_PORTS) {
    try {
      const res = await fetch(`http://127.0.0.1:${port}${PING_PATH}`, { signal: AbortSignal.timeout(1000) });
      if (res.ok && (await res.json()).app === "jobhunt") {
        await chrome.storage.session.set({ [PORT_CACHE_KEY]: port });
        return port;
      }
    } catch (_) { /* try next */ }
  }
  throw new Error(SERVER_NOT_FOUND_MESSAGE);
}

async function serverUrl(path) {
  const port = await findServerPort();
  return `http://127.0.0.1:${port}${path}`;
}

const CAPTURE_JOB_MENU_ID = "capture-this-job";
const SAVE_WITH_NOTE_MENU_ID = "save-job-with-note";
const MARK_SITE_REVIEWED_MENU_ID = "mark-site-reviewed";
const OPEN_JOB_IN_APP_MENU_ID = "open-job-in-app";
const OPEN_CAPTURE_QUEUE_MENU_ID = "open-capture-queue";
const SYNC_QUEUE_MENU_ID = "sync-queue";
const EXPORT_CSV_MENU_ID = "export-csv";
const CHECK_SERVER_MENU_ID = "check-server";
const OPEN_APP_MENU_ID = "open-app";

chrome.runtime.onInstalled.addListener(() => {
  chrome.contextMenus.create({
    id: CAPTURE_JOB_MENU_ID,
    title: "Capture this job",
    contexts: ["page", "action"]
  });
  chrome.contextMenus.create({
    id: SAVE_WITH_NOTE_MENU_ID,
    title: "Save job with note",
    contexts: ["page", "selection", "action"]
  });
  chrome.contextMenus.create({
    id: MARK_SITE_REVIEWED_MENU_ID,
    title: "Mark site reviewed",
    contexts: ["page", "action"]
  });
  chrome.contextMenus.create({
    id: OPEN_JOB_IN_APP_MENU_ID,
    title: "Open this job in JobHunt",
    contexts: ["page", "action"]
  });
  chrome.contextMenus.create({
    type: "separator",
    id: "sep-queue",
    contexts: ["action"]
  });
  chrome.contextMenus.create({
    id: OPEN_CAPTURE_QUEUE_MENU_ID,
    title: "View capture queue",
    contexts: ["action"]
  });
  chrome.contextMenus.create({
    id: SYNC_QUEUE_MENU_ID,
    title: "Sync queue now",
    contexts: ["action"]
  });
  chrome.contextMenus.create({
    id: EXPORT_CSV_MENU_ID,
    title: "Export queue to CSV",
    contexts: ["action"]
  });
  chrome.contextMenus.create({
    type: "separator",
    id: "sep-server",
    contexts: ["action"]
  });
  chrome.contextMenus.create({
    id: CHECK_SERVER_MENU_ID,
    title: "Check server connection",
    contexts: ["action"]
  });
  chrome.contextMenus.create({
    id: OPEN_APP_MENU_ID,
    title: "Open Jobhunt app",
    contexts: ["action"]
  });
  refreshCaptureShortcutLabel();
});

// Refresh the label on browser start too (the shortcut is stable per session; onInstalled only fires
// on install/update).
chrome.runtime.onStartup.addListener(() => {
  refreshCaptureShortcutLabel();
});

// Show the currently-bound keyboard shortcut in the "Capture this job" menu title so it's
// discoverable. Chrome doesn't render command shortcuts in context menus, and there's no event for a
// shortcut change, so we refresh on install/startup and whenever the action is used (below).
async function refreshCaptureShortcutLabel() {
  try {
    const commands = await chrome.commands.getAll();
    const shortcut = commands.find((c) => c.name === "capture-job")?.shortcut;
    await chrome.contextMenus.update(CAPTURE_JOB_MENU_ID, {
      title: shortcut ? `Capture this job (${shortcut})` : "Capture this job"
    }).catch(() => {});
  } catch (_) {
    // menus not created yet / commands unavailable — ignore
  }
}

// Queue-management items are only useful when the server is unreachable.
// Hide them when we have a cached server port (i.e. the Mac app is running).
// Note: chrome.contextMenus.onShown does not exist in Chrome (Firefox-only).
// Instead we update visibility whenever the action is clicked or the server port changes.
const QUEUE_MENU_IDS = [OPEN_CAPTURE_QUEUE_MENU_ID, SYNC_QUEUE_MENU_ID, EXPORT_CSV_MENU_ID, "sep-queue"];

async function updateQueueMenuVisibility() {
  await refreshCaptureShortcutLabel(); // keep the shortcut label fresh on each action interaction
  const cached = (await chrome.storage.session.get(PORT_CACHE_KEY))[PORT_CACHE_KEY];
  const visible = !cached;
  await Promise.all(QUEUE_MENU_IDS.map(id =>
    chrome.contextMenus.update(id, { visible }).catch(() => {})
  ));
}

async function handleCaptureRequest(tab) {
  await updateQueueMenuVisibility();
  try {
    await captureCurrentTab(tab);
  } catch (error) {
    console.error("[jobhunt] capture error:", error);
    await showBadge(String(error?.message || "").includes("canceled") ? "CAN" : "ERR", "#b00020");
  }
}

chrome.action.onClicked.addListener(async (tab) => {
  await handleCaptureRequest(tab);
});

// Keyboard shortcut (chrome://extensions/shortcuts to view/rebind). Like the toolbar click, invoking
// a command grants activeTab, so the capture can inject into the current page without extra permissions.
chrome.commands.onCommand.addListener(async (command) => {
  if (command !== "capture-job") {
    return;
  }
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  if (tab) {
    await handleCaptureRequest(tab);
  }
});

chrome.contextMenus.onClicked.addListener(async (info, tab) => {
  if (info.menuItemId === CAPTURE_JOB_MENU_ID) {
    await handleCaptureRequest(tab);
    return;
  }

  if (info.menuItemId === OPEN_CAPTURE_QUEUE_MENU_ID) {
    await openQueueStatus();
    return;
  }

  if (info.menuItemId === SYNC_QUEUE_MENU_ID) {
    await syncQueueFromMenu();
    return;
  }

  if (info.menuItemId === EXPORT_CSV_MENU_ID) {
    await exportQueueCsv();
    return;
  }

  if (info.menuItemId === CHECK_SERVER_MENU_ID) {
    await checkServerConnection();
    return;
  }

  if (info.menuItemId === OPEN_APP_MENU_ID) {
    await openApp();
    return;
  }

  if (!tab || !tab.id) {
    return;
  }

  if (info.menuItemId === SAVE_WITH_NOTE_MENU_ID) {
    await chrome.storage.session.set({ pendingNoteTabId: tab.id });
    await chrome.tabs.create({
      url: chrome.runtime.getURL("note.html"),
      active: true
    });
    return;
  }

  if (info.menuItemId === MARK_SITE_REVIEWED_MENU_ID) {
    await markSiteReviewed(tab);
    return;
  }

  if (info.menuItemId === OPEN_JOB_IN_APP_MENU_ID) {
    await openJobInApp(tab);
    return;
  }
});

chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
  if (!message) {
    return false;
  }

  if (message.type === "captureWithNote") {
    capturePendingNote(message.note || "")
      .then((result) => sendResponse({ ok: true, result }))
      .catch((error) => sendResponse({ ok: false, error: String(error) }));
    return true;
  }

  if (message.type === "flushCaptureQueue") {
    flushQueuedCaptures()
      .then((result) => sendResponse({ ok: true, result }))
      .catch((error) => sendResponse({ ok: false, error: String(error) }));
    return true;
  }

  return false;
});


// --- Greenhouse Boards API enrichment -----------------------------------------------------------
// Greenhouse SPA boards render their JSON-LD client-side, after the capture snapshot is taken, so the
// posting body/salary/location are missing from the raw capture. The public Boards API has them.
//
// This MUST run here in the service worker, not in the injected capture script: that script is
// injected with world:"MAIN" (page context) so it can read page globals, which makes any fetch an
// ordinary cross-origin request — and boards-api.greenhouse.io returns no Access-Control-Allow-Origin
// header, so it was blocked by CORS on every capture and silently yielded nothing. The service worker
// can make the request because the API host is declared in host_permissions.
const GREENHOUSE_TIMEOUT_MS = 5000;

// Regional boards exist (job-boards.eu.greenhouse.io), so allow an optional country subdomain.
const GREENHOUSE_URL_RE = /(?:job-boards|boards)(?:\.[a-z]{2})?\.greenhouse\.io\/([^/?#]+)\/jobs\/(\d+)/;

async function fetchGreenhouseJobData(url) {
  const match = String(url || "").match(GREENHOUSE_URL_RE);
  if (!match) return null;
  const [, board, jobId] = match;
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), GREENHOUSE_TIMEOUT_MS);
  try {
    const res = await fetch(`https://boards-api.greenhouse.io/v1/boards/${board}/jobs/${jobId}`, {
      headers: { Accept: "application/json" },
      signal: controller.signal,
    });
    clearTimeout(timer);
    if (!res.ok) return null;
    const data = await res.json();
    const posting = { "@type": "JobPosting", title: data.title || null, description: data.content || "" };
    if (data.location && data.location.name) {
      posting.jobLocation = {
        "@type": "Place",
        address: { "@type": "PostalAddress", addressLocality: data.location.name },
      };
    }
    if (data.absolute_url) posting.url = data.absolute_url;
    return { posting, rawTitle: data.title || "" };
  } catch (_err) {
    clearTimeout(timer);
    return null; // enrichment is best-effort; a capture must never fail because of it
  }
}

/// Merge Greenhouse API data into a capture payload, keeping `structured_data` and
/// `structured_data_json` in sync (the server prefers the typed field, TASK-437/442).
async function enrichWithGreenhouse(payload) {
  const gh = await fetchGreenhouseJobData(payload.url);
  if (!gh) return payload;
  const structured = Array.isArray(payload.structured_data) ? [...payload.structured_data] : [];
  structured.push(gh.posting);
  const enriched = {
    ...payload,
    structured_data: structured,
    structured_data_json: JSON.stringify(structured),
  };
  // Greenhouse titles the page "Job Application for …"; the API carries the real job title.
  if (gh.rawTitle && /^Job Application\b/i.test(String(payload.page_title || ""))) {
    enriched.page_title = gh.rawTitle;
  }
  return enriched;
}


// ── Lever / Ashby compensation enrichment ─────────────────────────────────────
//
// Both boards state pay OUTSIDE the description body, so no amount of text parsing can recover it:
// Lever returns a structured `salaryRange` object and omits the figures from the description
// entirely (saviynt/c34f16eb — $220,000-$240,000 appears nowhere in the text), and Ashby renders
// compensation in a sidebar the page capture doesn't include. Both expose it on a public API, so
// fetch it here for the same CORS reason as Greenhouse above.
const ATS_TIMEOUT_MS = 5000;
const LEVER_URL_RE = /jobs\.(?:eu\.)?lever\.co\/([^/?#]+)\/([0-9a-f-]{36})/i;
const ASHBY_URL_RE = /jobs\.ashbyhq\.com\/([^/?#]+)\/([0-9a-f-]{36})/i;

async function fetchJSON(url) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), ATS_TIMEOUT_MS);
  try {
    const res = await fetch(url, { headers: { Accept: "application/json" }, signal: controller.signal });
    clearTimeout(timer);
    return res.ok ? await res.json() : null;
  } catch (_err) {
    clearTimeout(timer);
    return null; // enrichment is best-effort; a capture must never fail because of it
  }
}

/// A schema.org baseSalary from Lever's structured salaryRange.
function leverSalaryPosting(data) {
  const r = data && data.salaryRange;
  if (!r || (!r.min && !r.max)) return null;
  // "per-year-salary" / "per-hour-wage" → the schema.org unit the cleaner understands.
  const interval = String(r.interval || "");
  const unit = /hour/i.test(interval) ? "HOUR" : /week/i.test(interval) ? "WEEK"
    : /month/i.test(interval) ? "MONTH" : "YEAR";
  return {
    "@type": "MonetaryAmount",
    currency: r.currency || "USD",
    value: { "@type": "QuantitativeValue", minValue: r.min, maxValue: r.max, unitText: unit },
  };
}

async function fetchLeverJobData(url) {
  const match = String(url || "").match(LEVER_URL_RE);
  if (!match) return null;
  const [, org, id] = match;
  const data = await fetchJSON(`https://api.lever.co/v0/postings/${org}/${id}`);
  if (!data) return null;
  const posting = { "@type": "JobPosting", title: data.text || null, description: data.description || "" };
  const salary = leverSalaryPosting(data);
  if (salary) posting.baseSalary = salary;
  if (data.categories && data.categories.location) {
    posting.jobLocation = {
      "@type": "Place",
      address: { "@type": "PostalAddress", addressLocality: data.categories.location },
    };
  }
  return { posting, rawTitle: data.text || "" };
}

async function fetchAshbyJobData(url) {
  const match = String(url || "").match(ASHBY_URL_RE);
  if (!match) return null;
  const [, board, id] = match;
  // Ashby has no per-job endpoint; the board feed carries every posting with compensation attached.
  const data = await fetchJSON(
    `https://api.ashbyhq.com/posting-api/job-board/${board}?includeCompensation=true`
  );
  const job = data && Array.isArray(data.jobs)
    ? data.jobs.find((j) => String(j.id || "") === id || String(j.jobUrl || "").includes(id))
    : null;
  if (!job) return null;
  const posting = { "@type": "JobPosting", title: job.title || null, description: job.descriptionPlain || "" };
  // Ashby gives a rendered string ("$153K – $180K • Offers Equity") rather than numbers; pass it
  // through as text so the salary sentence matcher picks it up.
  const summary = job.compensation
    && (job.compensation.scrapeableCompensationSalarySummary || job.compensation.compensationTierSummary);
  if (summary) posting.description = `Compensation: ${summary}\n\n${posting.description}`;
  if (job.location) {
    posting.jobLocation = {
      "@type": "Place",
      address: { "@type": "PostalAddress", addressLocality: job.location },
    };
  }
  return { posting, rawTitle: job.title || "" };
}

/// Merge whichever ATS recognises this URL. Greenhouse keeps its own richer path above.
async function enrichWithATS(payload) {
  for (const fetcher of [fetchLeverJobData, fetchAshbyJobData]) {
    const hit = await fetcher(payload.url);
    if (!hit) continue;
    const structured = Array.isArray(payload.structured_data) ? [...payload.structured_data] : [];
    structured.push(hit.posting);
    return {
      ...payload,
      structured_data: structured,
      structured_data_json: JSON.stringify(structured),
    };
  }
  return payload;
}

async function captureCurrentTab(tab, userNote = "") {
  if (!tab.id) {
    return;
  }

  const { payload, action } = await captureTabPayload(tab.id, userNote);
  const result = await submitOrQueue(payload);
  if (action === "open" && result && !result.queued) {
    await openApp(result.job_number);
  }
}

async function captureTabPayload(tabId, userNote = "") {
  // world:"MAIN" is required so the injected scripts can access page-level JS variables
  // (window.__next_f, window.__NEXT_DATA__) used by CSR Next.js job boards like Cribl.
  // The default ISOLATED world shares the DOM but not the page's JavaScript scope.
  await chrome.scripting.executeScript({
    target: { tabId },
    world: "MAIN",
    files: ["Readability.js"]
  });

  await chrome.scripting.executeScript({
    target: { tabId },
    world: "MAIN",
    files: ["capture.js"]
  });

  // Step 1: collect page data and return it to the service worker immediately.
  // This ensures we have the payload even if the tab is closed during the preflight countdown.
  const [dataInjection] = await chrome.scripting.executeScript({
    target: { tabId },
    world: "MAIN",
    func: () => globalThis.jobhuntCapture.capturePage(window, document),
  });
  const greenhoused = await enrichWithGreenhouse({ ...dataInjection.result, user_note: userNote });
  const payload = await enrichWithATS(greenhoused);

  // Step 2: show the preflight dialog in the tab. If the tab closes during the countdown
  // the executeScript call will throw — we catch that and default to saving the capture.
  let action = "save";
  try {
    const [preflightInjection] = await chrome.scripting.executeScript({
      target: { tabId },
      world: "MAIN",
      func: (preflight) => globalThis.jobhuntCapture.showCapturePreflight(preflight),
      args: [payload.preflight],
    });
    if (!preflightInjection.result) {
      throw new Error("Capture canceled");
    }
    action = preflightInjection.result;
  } catch (err) {
    // Re-throw explicit user cancellation; swallow tab-closed / other errors and save.
    if (String(err?.message).includes("canceled")) throw err;
  }

  return { payload, action };
}

/**
 * TASK-489: start the app, then retry. Opt-in and off by default.
 *
 * Only the launch goes through the URL scheme — the capture itself still flushes over localhost
 * HTTP, because a capture can be several MB and a URL can't be.
 */
async function tryLaunchAndFlush() {
  if (!(await jobhuntLaunch.isEnabled(chrome.storage.local))) return false;

  const result = await jobhuntLaunch.launchAndWait({
    openURL: async (url) => {
      // A tab is the only way to hand a custom scheme to the OS from a service worker, and it is
      // left sitting on about:blank afterwards — so close it once the handoff has happened.
      const tab = await chrome.tabs.create({ url, active: false });
      if (tab && tab.id !== undefined) {
        setTimeout(() => chrome.tabs.remove(tab.id).catch(() => {}), 1000);
      }
    },
    isServerReady: async () => {
      try {
        await findServerPort();
        return true;
      } catch (_) {
        return false;
      }
    },
    sleep: (ms) => new Promise((resolve) => setTimeout(resolve, ms)),
    now: () => Date.now(),
    lastAttemptAt: await jobhuntLaunch.readLastAttempt(chrome.storage.local),
  });

  if (result.launched) await jobhuntLaunch.recordAttempt(chrome.storage.local, Date.now());
  return result.ready === true;
}

async function submitOrQueue(payload) {
  await flushQueuedCaptures();

  try {
    const result = await submitCapture(payload);
    await showBadge(result.duplicate ? "DUP" : "OK", "#137333");
    return result;
  } catch (error) {
    // TASK-438: a permanent server rejection must NOT go into the retry queue — it would retry the
    // same bad payload until TTL. Surface it distinctly (ERR) instead of the "queued" state.
    if (error && error.permanent) {
      await showBadge("ERR", "#c0392b");
      return { queued: false, permanent: true, status: error.status, error: error.message };
    }
    // Queue first, launch second: if the app comes up we flush immediately, and if it doesn't the
    // capture is already safely stored rather than depending on the launch succeeding.
    const enqueueResult = await jobhuntRetryQueue.enqueueCapture(chrome.storage.local, payload);
    if (enqueueResult.duplicate) {
      await showBadge("DUP", "#f9ab00");
      return { queued: false, localDuplicate: true };
    }
    if (enqueueResult.error) {
      await showBadge("ERR", "#c0392b");
      return { queued: false, error: enqueueResult.error };
    }
    if (await tryLaunchAndFlush()) {
      const flushed = await flushQueuedCaptures();
      if (flushed.remaining === 0) {
        await showBadge("OK", "#137333");
        return { queued: false, launched: true, submitted: flushed.submitted };
      }
    }

    await showBadge("Q", "#f9ab00");
    await showQueuedStatus(enqueueResult.length);
    return { queued: true, queueLength: enqueueResult.length };
  }
}

async function flushQueuedCaptures() {
  const result = await jobhuntRetryQueue.flushQueue(chrome.storage.local, submitCapture);
  if (result.submitted > 0) {
    await showBadge(result.remaining === 0 ? "SYNC" : "Q", result.remaining === 0 ? "#137333" : "#f9ab00");
  }
  return result;
}

async function capturePendingNote(note) {
  const result = await chrome.storage.session.get("pendingNoteTabId");
  const tabId = result.pendingNoteTabId;
  if (!tabId) {
    throw new Error("No pending tab for note capture");
  }

  // Remove pending state only after capture succeeds so a transient failure
  // (script injection error, network unavailable) leaves the context intact for retry.
  const { payload } = await captureTabPayload(tabId, note);
  const captureResult = await submitOrQueue(payload);
  await chrome.storage.session.remove("pendingNoteTabId");
  return captureResult;
}

async function submitCapture(payload) {
  const response = await fetch(await serverUrl("/captures"), {
    method: "POST",
    headers: {
      "content-type": "application/json"
    },
    body: JSON.stringify(payload)
  });

  if (!response.ok) {
    const err = new Error(`Capture failed: ${response.status}`);
    err.status = response.status;
    // TASK-438: 4xx (except 408 Request Timeout / 429 Too Many Requests) are PERMANENT — the same
    // payload will keep failing (validation error, forbidden origin, 413 too large). Don't retry
    // those. 5xx and network errors are retryable (server busy/unavailable).
    err.permanent = response.status >= 400 && response.status < 500
      && response.status !== 408 && response.status !== 429;
    throw err;
  }

  return response.json();
}

async function markSiteReviewed(tab) {
  if (!tab.url) {
    await showBadge("ERR", "#b00020");
    return;
  }

  const payload = buildSiteReviewPayload(tab);
  try {
    await submitSiteReview(payload);
    await showBadge("REV", "#137333");
  } catch (_error) {
    await showBadge("ERR", "#b00020");
  }
}

function buildSiteReviewPayload(tab) {
  const url = new URL(tab.url);
  return {
    schema_version: 1,
    reviewed_at: new Date().toISOString(),
    site_url: tab.url,
    site_origin: url.origin,
    page_title: tab.title || null,
    next_review_at: null,
    note: ""
  };
}

async function submitSiteReview(payload) {
  const response = await fetch(await serverUrl("/site-reviews"), {
    method: "POST",
    headers: {
      "content-type": "application/json"
    },
    body: JSON.stringify(payload)
  });

  if (!response.ok) {
    throw new Error(`Site review failed: ${response.status}`);
  }

  return response.json();
}

async function showBadge(text, color) {
  await chrome.action.setBadgeText({ text });
  await chrome.action.setBadgeBackgroundColor({ color });

  setTimeout(() => {
    chrome.action.setBadgeText({ text: "" });
  }, 2000);
}

async function showQueuedStatus(queueLength) {
  await chrome.action.setTitle({
    title: `Capture queued (${queueLength}). Open the Jobhunt Mac app to sync.`
  });
  // Auto path (a save landed offline): open the tab in the BACKGROUND so it doesn't steal focus
  // from the page the user is on, and reuse/throttle so a burst of saves doesn't spam tabs.
  await openQueueStatus({ background: true });
}

// Don't reopen the background status tab more than once per this window while the user keeps saving
// offline (it's already open or was just shown). The context-menu path ignores this and always shows.
const STATUS_TAB_THROTTLE_MS = 10 * 60 * 1000;
const STATUS_TAB_ID_KEY = "jobhunt.statusTabId";
const STATUS_TAB_SHOWN_KEY = "jobhunt.statusTabShownAt";

async function openQueueStatus({ background = false } = {}) {
  const statusURL = chrome.runtime.getURL("status.html");
  const state = await chrome.storage.session.get([STATUS_TAB_ID_KEY, STATUS_TAB_SHOWN_KEY]);
  const prevTabId = state[STATUS_TAB_ID_KEY];
  const lastShown = state[STATUS_TAB_SHOWN_KEY];

  // Reuse an already-open status tab instead of spawning another (anti-spam). chrome.tabs.get
  // rejects if the tab was closed, in which case we fall through and open a fresh one.
  if (prevTabId != null) {
    try {
      const tab = await chrome.tabs.get(prevTabId);
      if (tab) {
        if (!background) {
          await chrome.tabs.update(prevTabId, { active: true });
          if (tab.windowId != null) {
            await chrome.windows.update(tab.windowId, { focused: true }).catch(() => {});
          }
        }
        return;
      }
    } catch (_) {
      // tab no longer exists — fall through to create a new one
    }
  }

  // Background (auto) path: skip if we showed the tab recently, so a burst of offline saves doesn't
  // keep reopening it. The context-menu path (background === false) always opens.
  if (background && lastShown && Date.now() - lastShown < STATUS_TAB_THROTTLE_MS) {
    return;
  }

  const created = await chrome.tabs.create({ url: statusURL, active: !background });
  await chrome.storage.session.set({
    [STATUS_TAB_ID_KEY]: created.id,
    [STATUS_TAB_SHOWN_KEY]: Date.now()
  });
}

async function syncQueueFromMenu() {
  const result = await flushQueuedCaptures();
  if (result.submitted === 0 && result.remaining > 0) {
    await showBadge("ERR", "#b00020");
  } else if (result.remaining > 0) {
    await showBadge("Q", "#f9ab00");
  } else {
    await showBadge("OK", "#137333");
  }
}

async function exportQueueCsv() {
  const queue = await jobhuntRetryQueue.getQueue(chrome.storage.local);
  if (queue.length === 0) {
    await showBadge("MT", "#888888");
    return;
  }
  const csv = jobhuntCsv.queueToCsv(queue);
  const dataUrl = "data:text/csv;charset=utf-8," + encodeURIComponent(csv);
  await chrome.downloads.download({ url: dataUrl, filename: jobhuntCsv.csvFilename() });
  await showBadge("CSV", "#137333");
}

async function checkServerConnection() {
  try {
    const port = await findServerPort();
    await chrome.action.setTitle({ title: `Capture job [${BUILD_DATE}] — server on :${port}` });
    await showBadge("OK", "#137333");
  } catch (_error) {
    await chrome.action.setTitle({ title: `Capture job [${BUILD_DATE}] — server not found` });
    await showBadge("ERR", "#b00020");
  }
}

async function openJobInApp(tab) {
  if (!tab?.url) {
    await showBadge("ERR", "#b00020");
    return;
  }
  try {
    const lookupUrl = await serverUrl("/api/jobs/by-url?url=" + encodeURIComponent(tab.url));
    const res = await fetch(lookupUrl, { signal: AbortSignal.timeout(3000) });
    if (!res.ok) {
      await showBadge("?", "#888888");
      return;
    }
    const { job_number } = await res.json();
    await openApp(job_number);
  } catch (_error) {
    await showBadge("ERR", "#b00020");
  }
}

async function openApp(jobNumber) {
  try {
    // Ask the Electron window to focus and navigate — no new browser tab needed.
    const focusUrl = await serverUrl("/api/app/focus");
    const res = await fetch(focusUrl, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ job_number: jobNumber ?? null }),
    });
    if (res.ok) return;
  } catch (_error) { /* fall through */ }

  // Fallback: open the web UI in a browser tab (CLI server or Electron not responding).
  try {
    const hash = jobNumber ? `#/jobs/${jobNumber}` : "";
    const url = await serverUrl("/") + hash;
    await chrome.tabs.create({ url, active: true });
  } catch (_error) {
    await showBadge("ERR", "#b00020");
  }
}
