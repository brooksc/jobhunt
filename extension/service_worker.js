importScripts("capture.js");
importScripts("retry_queue.js");
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
  const payload = { ...dataInjection.result, user_note: userNote };

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
    const enqueueResult = await jobhuntRetryQueue.enqueueCapture(chrome.storage.local, payload);
    if (enqueueResult.duplicate) {
      await showBadge("DUP", "#f9ab00");
      return { queued: false, localDuplicate: true };
    }
    if (enqueueResult.error) {
      await showBadge("ERR", "#c0392b");
      return { queued: false, error: enqueueResult.error };
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
