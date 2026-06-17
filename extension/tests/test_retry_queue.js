// Tests for extension/retry_queue.js
// Run: node --test extension/tests/test_retry_queue.js
'use strict';
const { describe, test } = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');
const fs = require('node:fs');

eval(fs.readFileSync(path.join(__dirname, '../retry_queue.js'), 'utf8'));
const q = globalThis.jobhuntRetryQueue;

function mockStorage(initial = {}) {
  const data = { ...initial };
  return {
    async get(keys) {
      if (typeof keys === 'object' && !Array.isArray(keys)) {
        const result = {};
        for (const [key, def] of Object.entries(keys)) {
          result[key] = key in data ? data[key] : def;
        }
        return result;
      }
      return { ...data };
    },
    async set(obj) { Object.assign(data, obj); },
    _data: data
  };
}

function item(url, daysAgo = 0) {
  const ts = new Date(Date.now() - daysAgo * 86400_000).toISOString();
  return { payload: { url, canonical_url: url }, queued_at: ts };
}

describe('retry_queue: enqueueCapture', () => {
  test('adds item to empty storage', async () => {
    const s = mockStorage();
    const r = await q.enqueueCapture(s, { url: 'https://example.com/job' });
    assert.equal(r.length, 1);
    assert.equal(r.duplicate, false);
  });

  test('returns duplicate:true for same URL', async () => {
    const s = mockStorage();
    await q.enqueueCapture(s, { url: 'https://example.com/job' });
    const r = await q.enqueueCapture(s, { url: 'https://example.com/job' });
    assert.equal(r.duplicate, true);
    assert.equal(r.length, 1);
  });

  test('deduplicates by canonical_url across different page URLs', async () => {
    const s = mockStorage();
    await q.enqueueCapture(s, { url: 'https://x.com/job?ref=1', canonical_url: 'https://x.com/job' });
    const r = await q.enqueueCapture(s, { url: 'https://x.com/job?ref=2', canonical_url: 'https://x.com/job' });
    assert.equal(r.duplicate, true);
  });

  test('auto-purges stale items before enqueueing', async () => {
    const s = mockStorage();
    await q.setQueue(s, [item('https://stale.com', 10)]);
    const r = await q.enqueueCapture(s, { url: 'https://fresh.com' });
    assert.equal(r.length, 1, 'stale item should be removed before counting');
    const queue = await q.getQueue(s);
    assert.equal(queue[0].payload.url, 'https://fresh.com');
  });
});

describe('retry_queue: flushQueue', () => {
  test('submits all items and clears queue on success', async () => {
    const s = mockStorage();
    await q.enqueueCapture(s, { url: 'https://a.com' });
    await q.enqueueCapture(s, { url: 'https://b.com' });
    const submitted = [];
    const r = await q.flushQueue(s, async (payload) => submitted.push(payload));
    assert.equal(r.submitted, 2);
    assert.equal(r.remaining, 0);
    assert.equal((await q.getQueue(s)).length, 0);
  });

  test('keeps failed items in queue and counts them as remaining', async () => {
    const s = mockStorage();
    await q.enqueueCapture(s, { url: 'https://fail.com' });
    await q.enqueueCapture(s, { url: 'https://ok.com' });
    const r = await q.flushQueue(s, async (payload) => {
      if (payload.url === 'https://fail.com') throw new Error('Network error');
    });
    assert.equal(r.submitted, 1);
    assert.equal(r.remaining, 1);
    const remaining = await q.getQueue(s);
    assert.equal(remaining[0].payload.url, 'https://fail.com');
  });

  test('returns submitted:0 and remaining:0 on empty queue', async () => {
    const s = mockStorage();
    const r = await q.flushQueue(s, async () => {});
    assert.equal(r.submitted, 0);
    assert.equal(r.remaining, 0);
  });
});

describe('retry_queue: byte limits', () => {
  test('oversized visible_text is truncated to fit MAX_ITEM_BYTES', async () => {
    const s = mockStorage();
    const bigText = 'x'.repeat(200 * 1024); // 200 KB — well over the 100 KB item limit
    const r = await q.enqueueCapture(s, { url: 'https://big.com', visible_text: bigText });
    assert.equal(r.duplicate, false);
    assert.ok(!r.error, 'should not fail — payload should be trimmed');
    const stored = await q.getQueue(s);
    const itemBytes = q.byteSize(stored[0]);
    assert.ok(itemBytes <= q.MAX_ITEM_BYTES, `item should be ≤ MAX_ITEM_BYTES, got ${itemBytes}`);
  });

  test('selected_text is preserved when visible_text is trimmed', async () => {
    const s = mockStorage();
    const bigText = 'x'.repeat(200 * 1024);
    await q.enqueueCapture(s, { url: 'https://sel.com', visible_text: bigText, selected_text: 'important' });
    const stored = await q.getQueue(s);
    assert.equal(stored[0].payload.selected_text, 'important');
  });

  test('returns error:quota when total queue would exceed MAX_QUEUE_BYTES', async () => {
    const s = mockStorage();
    // Fill queue with a pre-built oversized snapshot that already exceeds MAX_QUEUE_BYTES.
    const bigItem = { payload: { url: 'https://fill.com', visible_text: 'y'.repeat(100 * 1024) }, queued_at: new Date().toISOString() };
    const fakeQueue = Array.from({ length: 41 }, (_, i) => ({
      ...bigItem,
      payload: { ...bigItem.payload, url: `https://fill${i}.com` }
    }));
    await q.setQueue(s, fakeQueue);
    const r = await q.enqueueCapture(s, { url: 'https://new.com', visible_text: 'z'.repeat(100 * 1024) });
    assert.equal(r.error, 'quota');
  });

  test('returns error:storage_quota when chrome.storage.set throws', async () => {
    const s = mockStorage();
    s.set = async () => { throw new Error('QUOTA_BYTES exceeded'); };
    const r = await q.enqueueCapture(s, { url: 'https://quota.com', visible_text: 'small' });
    assert.equal(r.error, 'storage_quota');
  });
});

describe('retry_queue: atomicity', () => {
  test('enqueue during flush is not overwritten by flush writeback', async () => {
    const s = mockStorage();
    await q.enqueueCapture(s, { url: 'https://a.com' });

    // Kick off flush and enqueue concurrently without awaiting either yet.
    const flushP = q.flushQueue(s, async () => {});
    const enqueueP = q.enqueueCapture(s, { url: 'https://b.com' });

    await Promise.all([flushP, enqueueP]);

    // b.com was enqueued after flush started; it must survive the flush writeback.
    const final = await q.getQueue(s);
    assert.ok(
      final.some(i => (i.payload.canonical_url || i.payload.url) === 'https://b.com'),
      'enqueued item must not be dropped by a concurrent flush'
    );
  });
});

describe('retry_queue: purgeExpired', () => {
  test('keeps items within 7-day TTL', () => {
    const fresh = item('https://fresh.com', 6);
    assert.equal(q.purgeExpired([fresh]).length, 1);
  });

  test('removes items older than 7 days', () => {
    const stale = item('https://stale.com', 8);
    assert.equal(q.purgeExpired([stale]).length, 0);
  });

  test('trims to MAX_QUEUE_SIZE keeping newest items', () => {
    const items = Array.from({ length: 60 }, (_, i) => item(`https://x.com/${i}`, 0));
    const result = q.purgeExpired(items);
    assert.equal(result.length, q.MAX_QUEUE_SIZE);
    assert.equal(result[0].payload.url, `https://x.com/10`);
    assert.equal(result[result.length - 1].payload.url, `https://x.com/59`);
  });

  test('treats malformed items with no queued_at as expired', () => {
    const malformed = [{ payload: { url: 'https://bad.com' } }];
    assert.equal(q.purgeExpired(malformed).length, 0);
  });

  test('treats items with non-parseable queued_at as expired', () => {
    const bad = [{ payload: { url: 'https://x.com' }, queued_at: 'not-a-date' }];
    assert.equal(q.purgeExpired(bad).length, 0);
  });
});

describe('retry_queue: quota truncation marker (TASK-439)', () => {
  test('records truncation metadata when visible_text is trimmed', () => {
    const big = 'x'.repeat(200 * 1024); // > MAX_ITEM_BYTES (100KB)
    const out = q.fitItemToQuota({ url: 'https://example.com/big', visible_text: big });
    assert.equal(out.payload.visible_text_truncated, true);
    assert.equal(out.payload.visible_text_original_chars, big.length);
    assert.ok(out.payload.visible_text_stored_chars < big.length);
    assert.equal(out.payload.visible_text.length, out.payload.visible_text_stored_chars);
  });

  test('no marker when the item is under quota', () => {
    const out = q.fitItemToQuota({ url: 'https://example.com/small', visible_text: 'short' });
    assert.equal(out.payload.visible_text_truncated, undefined);
  });
});
