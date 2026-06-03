importScripts("capture.js");
importScripts("retry_queue.js");
importScripts("export_csv.js");

const BUILD_DATE = "2026-06-02";

// Show build date in the icon tooltip so it's easy to confirm the loaded version
chrome.action.setTitle({ title: `Capture job [${BUILD_DATE}]` });

// Ports to probe when looking for the jobhunt server (must match electron/main.js PREFERRED_PORTS
// plus the CLI default). The extension tries each in order and caches the winner.
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

const SAVE_WITH_NOTE_MENU_ID = "save-job-with-note";
const MARK_SITE_REVIEWED_MENU_ID = "mark-site-reviewed";
const OPEN_CAPTURE_QUEUE_MENU_ID = "open-capture-queue";
const SYNC_QUEUE_MENU_ID = "sync-queue";
const EXPORT_CSV_MENU_ID = "export-csv";
const CHECK_SERVER_MENU_ID = "check-server";
const OPEN_APP_MENU_ID = "open-app";

chrome.runtime.onInstalled.addListener(() => {
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
});

chrome.action.onClicked.addListener(async (tab) => {
  try {
    await captureCurrentTab(tab);
  } catch (error) {
    console.error("[jobhunt] capture error:", error);
    await showBadge(String(error?.message || "").includes("canceled") ? "CAN" : "ERR", "#b00020");
  }
});

chrome.contextMenus.onClicked.addListener(async (info, tab) => {
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
  await chrome.scripting.executeScript({
    target: { tabId },
    files: ["Readability.js"]
  });

  await chrome.scripting.executeScript({
    target: { tabId },
    files: ["capture.js"]
  });

  const [injection] = await chrome.scripting.executeScript({
    target: { tabId },
    func: async () => {
      const payload = await globalThis.jobhuntCapture.capturePage(window, document);
      const action = await globalThis.jobhuntCapture.showCapturePreflight(payload.preflight);
      return action ? { payload, action } : null;
    }
  });
  if (!injection.result) {
    throw new Error("Capture canceled");
  }
  const { payload, action } = injection.result;
  return {
    payload: { ...payload, user_note: userNote },
    action,
  };
}

async function submitOrQueue(payload) {
  await flushQueuedCaptures();

  // Debug: log what was captured so you can inspect in the service worker console
  console.log("[jobhunt] captured:", {
    url: payload.url,
    title: payload.page_title,
    visible_text_length: payload.visible_text?.length,
    visible_text_head: payload.visible_text?.slice(0, 500),
    structured_data_count: payload.structured_data?.length,
  });

  try {
    const result = await submitCapture(payload);
    await showBadge(result.duplicate ? "DUP" : "OK", "#137333");
    return result;
  } catch (_error) {
    const { length, duplicate } = await jobhuntRetryQueue.enqueueCapture(chrome.storage.local, payload);
    if (duplicate) {
      await showBadge("DUP", "#f9ab00");
      return { queued: false, localDuplicate: true };
    }
    await showBadge("Q", "#f9ab00");
    await showQueuedStatus(length);
    return { queued: true, queueLength: length };
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

  await chrome.storage.session.remove("pendingNoteTabId");
  const { payload } = await captureTabPayload(tabId, note);
  return submitOrQueue(payload);
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
    throw new Error(`Capture failed: ${response.status}`);
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
  await openQueueStatus();
}

async function openQueueStatus() {
  await chrome.tabs.create({
    url: chrome.runtime.getURL("status.html"),
    active: true
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
