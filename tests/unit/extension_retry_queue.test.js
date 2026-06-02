import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'fs';
import { runInThisContext } from 'vm';
import { resolve } from 'path';

function loadRetryQueue() {
  delete globalThis.jobhuntRetryQueue;
  const script = readFileSync(resolve('extension/retry_queue.js'), 'utf8');
  runInThisContext(script, { filename: 'extension/retry_queue.js' });
  return globalThis.jobhuntRetryQueue;
}

function fakeStorage(initial = {}) {
  const state = { ...initial };
  return {
    state,
    async get(defaults) {
      return { ...defaults, ...state };
    },
    async set(values) {
      Object.assign(state, values);
    },
  };
}

describe('extension retry queue', () => {
  it('stores captures in Chrome-compatible storage shape', async () => {
    const queue = loadRetryQueue();
    const storage = fakeStorage();

    const length = await queue.enqueueCapture(storage, { url: 'https://example.com/job' });
    const items = await queue.getQueue(storage);

    assert.equal(length, 1);
    assert.equal(items.length, 1);
    assert.equal(items[0].payload.url, 'https://example.com/job');
    assert.match(items[0].queued_at, /^\d{4}-\d{2}-\d{2}T/);
  });

  it('flushes successful captures and keeps failed captures queued', async () => {
    const queue = loadRetryQueue();
    const storage = fakeStorage({
      [queue.QUEUE_KEY]: [
        { payload: { url: 'https://example.com/ok' }, queued_at: '2026-06-01T12:00:00Z' },
        { payload: { url: 'https://example.com/fail' }, queued_at: '2026-06-01T12:01:00Z' },
      ],
    });

    const result = await queue.flushQueue(storage, async (payload) => {
      if (payload.url.includes('fail')) {
        throw new Error('server unavailable');
      }
    });

    const remaining = await queue.getQueue(storage);
    assert.deepEqual(result, { submitted: 1, remaining: 1 });
    assert.equal(remaining.length, 1);
    assert.equal(remaining[0].payload.url, 'https://example.com/fail');
  });
});
