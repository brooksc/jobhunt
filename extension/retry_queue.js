(function () {
  const QUEUE_KEY = "jobhunt.captureQueue";
  // Captures the app has permanently refused. Kept out of the retry queue so they stop being
  // presented as "can't reach Jobhunt", and kept AT ALL so the user can see what was lost and why —
  // silently dropping a capture the user made is worse than showing a rejected one.
  const REJECTED_KEY = "jobhunt.rejectedCaptures";
  const MAX_REJECTED = 20;
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

  async function getRejected(storageArea) {
    const result = await storageArea.get({ [REJECTED_KEY]: [] });
    return Array.isArray(result[REJECTED_KEY]) ? result[REJECTED_KEY] : [];
  }

  async function clearRejected(storageArea) {
    await storageArea.set({ [REJECTED_KEY]: [] });
  }

  /** Flush the queue, separating permanent rejections from retryable failures.
   *
   *  Submission already classifies a permanent 4xx (everything except 408/429) via `error.permanent`
   *  — TASK-438 uses it to avoid enqueueing a fresh capture that was refused. The flush path ignored
   *  it and pushed every failure back onto the queue, so an already-queued capture that the app
   *  refuses (400 validation, 413 too large) retried forever while the status page reported "Could
   *  not reach Jobhunt". Wrong twice: it isn't a connectivity problem, and it never resolves. */
  function flushQueue(storageArea, submitCapture) {
    return withLock(async () => {
      const raw = await getQueue(storageArea);
      const queue = purgeExpired(raw);
      const remaining = [];
      const newlyRejected = [];
      let submitted = 0;

      for (const item of queue) {
        try {
          await submitCapture(item.payload);
          submitted += 1;
        } catch (error) {
          if (error && error.permanent) {
            newlyRejected.push({
              payload: item.payload,
              queued_at: item.queued_at,
              rejected_at: new Date().toISOString(),
              status: error.status || null,
              error: error.message || "Rejected by Jobhunt"
            });
          } else {
            remaining.push(item);
          }
        }
      }

      await setQueue(storageArea, remaining);
      if (newlyRejected.length) {
        const existing = await getRejected(storageArea);
        // Newest last, bounded — this list is a diagnostic, not a second queue.
        const merged = existing.concat(newlyRejected).slice(-MAX_REJECTED);
        await storageArea.set({ [REJECTED_KEY]: merged });
      }
      return { submitted, remaining: remaining.length, rejected: newlyRejected.length };
    });
  }

  globalThis.jobhuntRetryQueue = {
    QUEUE_KEY,
    REJECTED_KEY,
    MAX_REJECTED,
    getRejected,
    clearRejected,
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
