// Behaviour test for openApp()'s fallback when the Mac app doesn't answer (TASK-697).
//
// The fallback used to open `serverUrl("/") + "#/jobs/N"` — a route on the React web UI the app
// served before the Swift rewrite, deleted in the cutover (TASK-064). JobhuntServer has no `/`
// route, so the branch that
// fires precisely when the user needs a clear signal opened a dead tab instead.
//
// Asserted as behaviour rather than by grepping the source: a string match would pass whether or not
// the branch is reachable, which is the failure mode this whole area keeps producing.
//
// Run: node --test extension/tests/test_open_app_fallback.js
//
// Deliberately NOT 'use strict' — strict mode gives `eval` its own scope, so the worker's top-level
// functions would never reach the tests. Same reason as the other worker harnesses here.
const { describe, test, beforeEach } = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');
const fs = require('node:fs');

function makeChromeStorage() {
  let data = {};
  return {
    async get(keys) {
      if (typeof keys === 'string') return { [keys]: data[keys] };
      if (Array.isArray(keys)) {
        const out = {};
        keys.forEach((k) => { if (k in data) out[k] = data[k]; });
        return out;
      }
      const out = {};
      for (const [k, def] of Object.entries(keys || {})) out[k] = k in data ? data[k] : def;
      return out;
    },
    async set(obj) { Object.assign(data, obj); },
    async remove(key) {
      (Array.isArray(key) ? key : [key]).forEach((k) => delete data[k]);
    },
    reset() { data = {}; },
  };
}

let createdTabs = [];
let badges = [];
let titles = [];

global.importScripts = () => {};
global.chrome = {
  action: {
    setTitle: async ({ title }) => { titles.push(title); },
    setBadgeText: async ({ text }) => { if (text) badges.push(text); },
    setBadgeBackgroundColor: async () => {},
    onClicked: { addListener: () => {} },
  },
  contextMenus: { create: () => {}, update: async () => {}, onClicked: { addListener: () => {} } },
  runtime: {
    onInstalled: { addListener: () => {} },
    onStartup: { addListener: () => {} },
    onMessage: { addListener: () => {} },
    getURL: (p) => `chrome-extension://test/${p}`,
  },
  storage: { session: makeChromeStorage(), local: makeChromeStorage() },
  scripting: { executeScript: async () => [{ result: {} }] },
  tabs: {
    create: async (opts) => { createdTabs.push(opts); return { id: createdTabs.length, windowId: 1 }; },
    remove: async () => {},
    query: async () => [],
    // No pre-existing status tab, so openQueueStatus falls through and creates one.
    get: async () => { throw new Error('no such tab'); },
    update: async () => {},
  },
  windows: { update: async () => {} },
  commands: { getAll: async () => [], onCommand: { addListener: () => {} } },
  downloads: { download: async () => 1 },
};

eval(fs.readFileSync(path.join(__dirname, '../retry_queue.js'), 'utf8'));
eval(fs.readFileSync(path.join(__dirname, '../export_csv.js'), 'utf8'));
eval(fs.readFileSync(path.join(__dirname, '../service_worker.js'), 'utf8'));

describe('openApp fallback when the Mac app is unreachable', () => {
  beforeEach(() => {
    createdTabs = [];
    badges = [];
    titles = [];
    // Every port probe and the focus POST fail: the app is not running.
    global.fetch = async () => { throw new Error('connection refused'); };
  });

  // The port must RESOLVE for this to test anything. With every probe failing, `serverUrl()` throws
  // before the old code could open its tab, so the assertion passed against the bug — a decorative
  // test. The real shape of the failure is: the server is reachable (the app was running, or is
  // starting), but /api/app/focus does not answer. So the ping succeeds and only focus fails.
  test('never opens a URL on the local server, even when the port resolves', async () => {
    global.fetch = async (url) => {
      if (String(url).includes('/api/app/focus')) throw new Error('focus failed');
      return { ok: true, json: async () => ({ app: 'jobhunt' }) };
    };

    await openApp(42);

    const serverTabs = createdTabs.filter((t) => /^https?:/i.test(t.url || ''));
    assert.deepEqual(
      serverTabs, [],
      'the Swift server serves no HTML — opening one of its URLs is a dead tab (TASK-697)'
    );
    assert.ok(
      createdTabs.some((t) => (t.url || '').endsWith('/status.html')),
      'expected the status page instead'
    );
  });

  test('opens the extension-owned status page, which always loads', async () => {
    await openApp(42);

    assert.ok(
      createdTabs.some((t) => (t.url || '').endsWith('/status.html')),
      'expected the status page, which explains what works without the Mac app'
    );
  });

  test('signals the failure rather than failing silently', async () => {
    await openApp(42);

    assert.ok(badges.includes('ERR'), 'expected an ERR badge');
    assert.ok(
      titles.some((t) => /isn't running/i.test(t || '')),
      'expected the action title to say the app is not running'
    );
  });

  test('behaves the same with no job number', async () => {
    await openApp(undefined);

    assert.deepEqual(createdTabs.filter((t) => /^https?:/i.test(t.url || '')), []);
    assert.ok(createdTabs.some((t) => (t.url || '').endsWith('/status.html')));
  });
});
