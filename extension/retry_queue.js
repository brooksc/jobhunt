(function () {
  const QUEUE_KEY = "jobhunt.captureQueue";

  async function getQueue(storageArea) {
    const result = await storageArea.get({ [QUEUE_KEY]: [] });
    return Array.isArray(result[QUEUE_KEY]) ? result[QUEUE_KEY] : [];
  }

  async function setQueue(storageArea, queue) {
    await storageArea.set({ [QUEUE_KEY]: queue });
  }

  async function enqueueCapture(storageArea, payload) {
    const queue = await getQueue(storageArea);
    queue.push({
      payload,
      queued_at: new Date().toISOString()
    });
    await setQueue(storageArea, queue);
    return queue.length;
  }

  async function flushQueue(storageArea, submitCapture) {
    const queue = await getQueue(storageArea);
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
    return {
      submitted,
      remaining: remaining.length
    };
  }

  globalThis.jobhuntRetryQueue = {
    QUEUE_KEY,
    enqueueCapture,
    flushQueue,
    getQueue,
    setQueue
  };
})();
