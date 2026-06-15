// Contract tests for service_worker.js behaviors:
//   offline queuing, capture submission, header requirements, badge states.
//
// Strategy: mock the chrome.* APIs and capture the onMessage listener during
// service_worker.js eval. Tests then invoke that listener with synthetic messages.
// This avoids a real Chrome profile (AC#5) while still exercising the integration
// between service_worker.js, retry_queue.js, and the fetch-based capture path.
//
// Run: node --test extension/tests/test_service_worker_contract.js
'use strict';
const { describe, test, beforeEach } = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');
const fs = require('node:fs');

// --- Storage mock -------------------------------------------------------

function makeChromeStorage() {
  let data = {};
  return {
    async get(keysOrStr) {
      if (typeof keysOrStr === 'string') {
        return { [keysOrStr]: data[keysOrStr] };
      }
      const result = {};
      for (const [k, def] of Object.entries(keysOrStr)) {
        result[k] = k in data ? data[k] : def;
      }
      return result;
    },
    async set(obj) { Object.assign(data, obj); },
    async remove(key) {
      const keys = Array.isArray(key) ? key : [key];
      keys.forEach(k => delete data[k]);
    },
    reset() { data = {}; }
  };
}

const sessionStorage = makeChromeStorage();
const localChrome = makeChromeStorage();

// --- Badge capture -------------------------------------------------------

let badgeText = '';
let badgeColor = '';

// --- Chrome mock ---------------------------------------------------------

let messageListener = null;
let contextMenuListener = null;

global.importScripts = () => {}; // deps loaded separately below

global.chrome = {
  action: {
    setTitle: async () => {},
    setBadgeText: async ({ text }) => { badgeText = text; },
    setBadgeBackgroundColor: async ({ color }) => { badgeColor = color; },
    onClicked: { addListener: () => {} }
  },
  contextMenus: {
    create: () => {},
    update: async () => {},
    onClicked: { addListener: (fn) => { contextMenuListener = fn; } }
  },
  runtime: {
    onInstalled: { addListener: () => {} },
    onMessage: { addListener: (fn) => { messageListener = fn; } },
    getURL: (p) => `chrome-extension://test/${p}`
  },
  storage: {
    session: sessionStorage,
    local: localChrome
  },
  scripting: {
    executeScript: async () => [{ result: { url: 'https://example.com/job', page_title: 'Job', preflight: {} } }]
  },
  tabs: { create: async () => {} },
  downloads: { download: async () => {} }
};

// --- Load dependencies and service_worker --------------------------------

eval(fs.readFileSync(path.join(__dirname, '../retry_queue.js'), 'utf8'));
eval(fs.readFileSync(path.join(__dirname, '../export_csv.js'), 'utf8'));
eval(fs.readFileSync(path.join(__dirname, '../service_worker.js'), 'utf8'));

assert.ok(messageListener, 'service_worker.js must register a chrome.runtime.onMessage listener');

// --- Helpers -------------------------------------------------------------

function sendMessage(message) {
  return new Promise((resolve, reject) => {
    const returned = messageListener(message, null, (response) => resolve(response));
    // If the listener returned false, it will not call sendResponse async — resolve immediately.
    if (returned === false) resolve(null);
    // Guard against test hanging: reject after 5 s
    setTimeout(() => reject(new Error('sendResponse never called')), 5000).unref();
  });
}

function queuedItem(url = 'https://example.com/job') {
  return { payload: { url, canonical_url: url }, queued_at: new Date().toISOString() };
}

// --- Tests ---------------------------------------------------------------

describe('service_worker: message handler', () => {
  beforeEach(() => {
    sessionStorage.reset();
    localChrome.reset();
    badgeText = '';
    badgeColor = '';
    global.fetch = undefined;
  });

  test('null message returns false (no async handler)', async () => {
    const result = await sendMessage(null);
    assert.equal(result, null);
  });

  test('unknown message type returns false', async () => {
    const result = await sendMessage({ type: 'notARealMessage' });
    assert.equal(result, null);
  });

  describe('flushCaptureQueue — server available', () => {
    test('submits queued items and clears queue', async () => {
      await localChrome.set({ 'jobhunt.captureQueue': [queuedItem()] });

      let captureCallCount = 0;
      global.fetch = async (url) => {
        if (url.includes('/ping')) {
          return { ok: true, json: async () => ({ app: 'jobhunt' }) };
        }
        captureCallCount++;
        return { ok: true, json: async () => ({ job_number: 1, duplicate: false }) };
      };

      const result = await sendMessage({ type: 'flushCaptureQueue' });

      assert.ok(result.ok, `response.ok should be true, got: ${JSON.stringify(result)}`);
      assert.equal(result.result.submitted, 1);
      assert.equal(result.result.remaining, 0);
      assert.equal(captureCallCount, 1, 'submitCapture should be called once');

      const remaining = await localChrome.get({ 'jobhunt.captureQueue': [] });
      assert.equal(remaining['jobhunt.captureQueue'].length, 0, 'queue should be empty after successful flush');
    });

    test('sets content-type: application/json on the capture POST', async () => {
      await localChrome.set({ 'jobhunt.captureQueue': [queuedItem()] });

      let capturedHeaders = null;
      global.fetch = async (url, options) => {
        if (url.includes('/ping')) {
          return { ok: true, json: async () => ({ app: 'jobhunt' }) };
        }
        capturedHeaders = options?.headers;
        return { ok: true, json: async () => ({ job_number: 1, duplicate: false }) };
      };

      await sendMessage({ type: 'flushCaptureQueue' });

      assert.ok(capturedHeaders, 'fetch should have been called with options');
      assert.equal(capturedHeaders['content-type'], 'application/json',
        'capture POST must include content-type: application/json');
    });
  });

  describe('flushCaptureQueue — server unavailable', () => {
    test('keeps items in queue when all fetches fail', async () => {
      await localChrome.set({ 'jobhunt.captureQueue': [queuedItem()] });

      global.fetch = async () => { throw new Error('Connection refused'); };

      const result = await sendMessage({ type: 'flushCaptureQueue' });

      assert.ok(result.ok);
      assert.equal(result.result.submitted, 0);
      assert.equal(result.result.remaining, 1, 'failed item must remain in queue');

      const queue = await localChrome.get({ 'jobhunt.captureQueue': [] });
      assert.equal(queue['jobhunt.captureQueue'].length, 1);
    });

    test('partial failure: submitted items cleared, failed items kept', async () => {
      await localChrome.set({
        'jobhunt.captureQueue': [
          queuedItem('https://fail.com'),
          queuedItem('https://ok.com'),
        ]
      });

      global.fetch = async (url, opts) => {
        if (url.includes('/ping')) {
          return { ok: true, json: async () => ({ app: 'jobhunt' }) };
        }
        const body = opts?.body ? JSON.parse(opts.body) : {};
        if (body.url === 'https://fail.com') throw new Error('server error');
        return { ok: true, json: async () => ({ job_number: 2, duplicate: false }) };
      };

      const result = await sendMessage({ type: 'flushCaptureQueue' });

      assert.equal(result.result.submitted, 1);
      assert.equal(result.result.remaining, 1);
    });
  });

  describe('captureWithNote — pending context lifecycle', () => {
    beforeEach(() => {
      sessionStorage.reset();
      localChrome.reset();
      badgeText = '';
    });

    test('clears pendingNoteTabId after successful capture', async () => {
      await sessionStorage.set({ pendingNoteTabId: 42 });
      global.fetch = async (url) => {
        if (url.includes('/ping')) return { ok: true, json: async () => ({ app: 'jobhunt' }) };
        return { ok: true, json: async () => ({ job_number: 1, duplicate: false }) };
      };

      const result = await sendMessage({ type: 'captureWithNote', note: 'great role' });

      assert.equal(result.ok, true);
      const after = await sessionStorage.get('pendingNoteTabId');
      assert.equal(after.pendingNoteTabId, undefined, 'pendingNoteTabId must be cleared after success');
    });

    test('preserves pendingNoteTabId when script injection fails', async () => {
      await sessionStorage.set({ pendingNoteTabId: 42 });
      // Make executeScript throw to simulate injection failure.
      const orig = global.chrome.scripting.executeScript;
      global.chrome.scripting.executeScript = async () => { throw new Error('Cannot access tab'); };

      const result = await sendMessage({ type: 'captureWithNote', note: 'test' });

      global.chrome.scripting.executeScript = orig;
      assert.equal(result.ok, false, 'capture must report failure');
      const after = await sessionStorage.get('pendingNoteTabId');
      assert.equal(after.pendingNoteTabId, 42, 'pendingNoteTabId must be preserved for retry after injection failure');
    });

    test('returns error detail on failure', async () => {
      await sessionStorage.set({ pendingNoteTabId: 42 });
      const orig = global.chrome.scripting.executeScript;
      global.chrome.scripting.executeScript = async () => { throw new Error('Tab not found'); };

      const result = await sendMessage({ type: 'captureWithNote', note: 'test' });

      global.chrome.scripting.executeScript = orig;
      assert.ok(result.error && result.error.includes('Tab not found'), 'error detail must be returned');
    });
  });

  // TASK-438: permanent (4xx) capture failures must NOT be queued for retry; retryable failures must.
  describe('captureWithNote — permanent vs retryable failures', () => {
    beforeEach(() => {
      sessionStorage.reset();
      localChrome.reset();
    });

    test('a permanent 413 failure is not queued', async () => {
      await sessionStorage.set({ pendingNoteTabId: 7 });
      global.fetch = async (url) => {
        if (url.includes('/ping')) return { ok: true, json: async () => ({ app: 'jobhunt' }) };
        if (url.includes('/captures')) return { ok: false, status: 413, json: async () => ({}) };
        throw new Error(`unexpected ${url}`);
      };
      await sendMessage({ type: 'captureWithNote', note: 'too big' });
      const queue = await localChrome.get({ 'jobhunt.captureQueue': [] });
      assert.equal(queue['jobhunt.captureQueue'].length, 0, '413 must not be queued for retry');
    });

    test('a retryable 503 failure is queued', async () => {
      await sessionStorage.set({ pendingNoteTabId: 7 });
      global.fetch = async (url) => {
        if (url.includes('/ping')) return { ok: true, json: async () => ({ app: 'jobhunt' }) };
        if (url.includes('/captures')) return { ok: false, status: 503, json: async () => ({}) };
        throw new Error(`unexpected ${url}`);
      };
      await sendMessage({ type: 'captureWithNote', note: 'server busy' });
      const queue = await localChrome.get({ 'jobhunt.captureQueue': [] });
      assert.equal(queue['jobhunt.captureQueue'].length, 1, '503 must be queued for later retry');
    });
  });

  // TASK-436: the Mark-Site-Reviewed payload must stay decodable by the Swift server's
  // SiteReviewRequest model (server/swift/JobhuntServer.swift). This fails if the extension
  // payload keys drift from the server request model again.
  describe('markSiteReviewed — payload contract with the Swift server', () => {
    // snake_case keys the server's SiteReviewRequest accepts (its CodingKeys raw values).
    const SERVER_SITE_REVIEW_KEYS = new Set([
      'url', 'site_url', 'site_origin', 'page_title', 'note', 'reviewed_at', 'next_review_at', 'interval_days'
    ]);
    // Extension-only fields the server intentionally ignores (e.g. payload versioning).
    const EXTENSION_ONLY_KEYS = new Set(['schema_version']);

    test('Mark Site Reviewed posts a body the server can decode', async () => {
      assert.ok(contextMenuListener, 'service_worker must register a contextMenus.onClicked listener');

      let siteReviewBody = null;
      global.fetch = async (url, opts) => {
        if (url.includes('/ping')) return { ok: true, json: async () => ({ app: 'jobhunt' }) };
        if (url.includes('/site-reviews')) {
          siteReviewBody = opts && opts.body ? JSON.parse(opts.body) : null;
          return { ok: true, json: async () => ({ ok: true, site_review_id: 'sr-1' }) };
        }
        throw new Error(`unexpected fetch: ${url}`);
      };

      await contextMenuListener(
        { menuItemId: 'mark-site-reviewed' },
        { id: 1, url: 'https://boards.example.com/careers', title: 'Careers' }
      );

      assert.ok(siteReviewBody, 'Mark Site Reviewed must POST a body to /site-reviews');
      assert.ok(siteReviewBody.site_url, 'payload must include site_url (server resolvedURL)');
      for (const key of Object.keys(siteReviewBody)) {
        assert.ok(
          SERVER_SITE_REVIEW_KEYS.has(key) || EXTENSION_ONLY_KEYS.has(key),
          `payload key "${key}" is not in the server SiteReviewRequest model — extension/server contract drift`
        );
      }
    });
  });
});
