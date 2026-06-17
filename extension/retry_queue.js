(function () {
  const QUEUE_KEY = "jobhunt.captureQueue";
  const QUEUE_TTL_MS = 7 * 24 * 60 * 60 * 1000; // 7 days
  const MAX_QUEUE_SIZE = 50;
  // chrome.storage.local quota is 10 MB; keep the queue well under that.
  const MAX_ITEM_BYTES = 100 * 1024;   // 100 KB per item (trims visible_text if exceeded)
  const MAX_QUEUE_BYTES = 4 * 1024 * 1024; // 4 MB total queue

  // Serializes enqueue/flush so a flush writeback cannot overwrite a concurrent enqueue.
  let _lock = Promise.resolve();
  function withLock(fn) {
    const result = _lock.then(fn);
    _lock = result.then(() => {}, () => {});
    return result;
  }

  async function getQueue(storageArea) {
    const result = await storageArea.get({ [QUEUE_KEY]: [] });
    return Array.isArray(result[QUEUE_KEY]) ? result[QUEUE_KEY] : [];
  }

  async function setQueue(storageArea, queue) {
    await storageArea.set({ [QUEUE_KEY]: queue });
  }

  function byteSize(value) {
    return new TextEncoder().encode(JSON.stringify(value)).length;
  }

  /** Trim visible_text so the serialized item fits within MAX_ITEM_BYTES. Records truncation
   *  metadata on the payload so the queue UI, CSV export, and the synced app can tell the capture
   *  was shortened (TASK-439). */
  function fitItemToQuota(payload) {
    const item = { payload, queued_at: new Date().toISOString() };
    if (byteSize(item) <= MAX_ITEM_BYTES) return item;
    // Truncate visible_text until it fits; preserve all other fields including selected_text.
    const trimmed = Object.assign({}, payload);
    const text = trimmed.visible_text || "";
    // TASK-439: set the truncation markers BEFORE the size search so their bytes are accounted for
    // (otherwise adding them afterward could push the item back over the quota). `stored_chars` uses
    // a conservative placeholder (full length → max digit count) during the search; the real value
    // (≤ placeholder) is written after, so the final item never exceeds MAX_ITEM_BYTES.
    trimmed.visible_text_truncated = true;
    trimmed.visible_text_original_chars = text.length;
    trimmed.visible_text_stored_chars = text.length;
    let lo = 0, hi = text.length;
    while (lo < hi) {
      const mid = Math.floor((lo + hi + 1) / 2);
      trimmed.visible_text = text.slice(0, mid);
      if (byteSize({ payload: trimmed, queued_at: item.queued_at }) <= MAX_ITEM_BYTES) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    trimmed.visible_text = text.slice(0, lo);
    trimmed.visible_text_stored_chars = lo;
    return { payload: trimmed, queued_at: item.queued_at };
  }

  /** Remove items older than QUEUE_TTL_MS and trim to MAX_QUEUE_SIZE (oldest first). */
  function purgeExpired(queue) {
    const cutoff = Date.now() - QUEUE_TTL_MS;
    const fresh = queue.filter(item => {
      const ts = item.queued_at ? new Date(item.queued_at).getTime() : 0;
      return ts > cutoff;
    });
    return fresh.length > MAX_QUEUE_SIZE ? fresh.slice(-MAX_QUEUE_SIZE) : fresh;
  }

  function enqueueCapture(storageArea, payload) {
    return withLock(async () => {
      const raw = await getQueue(storageArea);
      const queue = purgeExpired(raw);
      const url = payload.canonical_url || payload.url;
      if (url && queue.some(item => (item.payload.canonical_url || item.payload.url) === url)) {
        if (queue.length !== raw.length) await setQueue(storageArea, queue);
        return { length: queue.length, duplicate: true };
      }
      const newItem = fitItemToQuota(payload);
      const totalBytes = byteSize(queue) + byteSize(newItem);
      if (totalBytes > MAX_QUEUE_BYTES) {
        return { length: queue.length, duplicate: false, error: "quota" };
      }
      queue.push(newItem);
      try {
        await setQueue(storageArea, queue);
      } catch (_err) {
        return { length: queue.length - 1, duplicate: false, error: "storage_quota" };
      }
      return { length: queue.length, duplicate: false };
    });
  }

  function flushQueue(storageArea, submitCapture) {
    return withLock(async () => {
      const raw = await getQueue(storageArea);
      const queue = purgeExpired(raw);
      const remaining = [];
      let submitted = 0;

      for (const item of queue) {
        try {
          await submitCapture(item.payload);
          submitted += 1;
        } catch (_error) {
          remaining.push(item);
        }
      }

      await setQueue(storageArea, remaining);
      return { submitted, remaining: remaining.length };
    });
  }

  globalThis.jobhuntRetryQueue = {
    QUEUE_KEY,
    QUEUE_TTL_MS,
    MAX_QUEUE_SIZE,
    MAX_ITEM_BYTES,
    MAX_QUEUE_BYTES,
    byteSize,
    fitItemToQuota,
    enqueueCapture,
    flushQueue,
    getQueue,
    purgeExpired,
    setQueue
  };
})();
