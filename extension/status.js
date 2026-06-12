(async function () {
  const summary = document.getElementById("summary");
  const status = document.getElementById("status");
  const captures = document.getElementById("captures");
  const syncButton = document.getElementById("sync");
  const exportButton = document.getElementById("export");
  const clearButton = document.getElementById("clear");

  function setStatus(text) {
    status.textContent = text;
  }

  function render(queue) {
    const count = queue.length;
    summary.textContent = count === 1
      ? "1 capture is saved locally."
      : `${count} captures are saved locally.`;

    syncButton.disabled = count === 0;
    exportButton.disabled = count === 0;
    clearButton.disabled = count === 0;
    resetClearButton();

    if (count === 0) {
      captures.innerHTML = '<div class="capture"><div class="capture-meta">No saved captures.</div></div>';
      return;
    }

    captures.innerHTML = queue.map((item) => {
      const payload = item.payload || {};
      const title = escapeHtml(payload.page_title || payload.url || "Untitled capture");
      const url = escapeHtml(payload.url || "");
      const capturedAt = escapeHtml(payload.captured_at || item.queued_at || "");
      const note = payload.user_note ? ` · Note: ${escapeHtml(payload.user_note)}` : "";
      return `
        <article class="capture">
          <div class="capture-title">${title}</div>
          <div class="capture-meta">${capturedAt}${note}</div>
          <div class="capture-meta">${url}</div>
        </article>
      `;
    }).join("");
  }

  function escapeHtml(value) {
    return String(value)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;");
  }

  async function loadQueue() {
    const raw = await jobhuntRetryQueue.getQueue(chrome.storage.local);
    const queue = jobhuntRetryQueue.purgeExpired(raw);
    if (queue.length !== raw.length) {
      await jobhuntRetryQueue.setQueue(chrome.storage.local, queue);
    }
    render(queue);
    return queue;
  }

  async function exportCsv() {
    const queue = await jobhuntRetryQueue.getQueue(chrome.storage.local);
    if (queue.length === 0) {
      setStatus("No captures to export.");
      return;
    }

    const blob = new Blob([jobhuntCsv.queueToCsv(queue)], { type: "text/csv" });
    const url = URL.createObjectURL(blob);
    const link = document.createElement("a");
    link.href = url;
    link.download = jobhuntCsv.csvFilename();
    link.click();
    URL.revokeObjectURL(url);
    setStatus("CSV exported.");
  }

  async function syncQueue() {
    setStatus("Syncing...");
    const response = await chrome.runtime.sendMessage({ type: "flushCaptureQueue" });
    if (!response?.ok) {
      setStatus("Could not reach Jobhunt. Open the Mac app and try again.");
      return;
    }

    const result = response.result || {};
    await loadQueue();
    if ((result.submitted || 0) === 0 && (result.remaining || 0) > 0) {
      setStatus("Could not reach Jobhunt. Open the Mac app and try again.");
      return;
    }
    setStatus(`${result.submitted || 0} synced, ${result.remaining || 0} still saved locally.`);
  }

  async function clearQueue() {
    await jobhuntRetryQueue.setQueue(chrome.storage.local, []);
    render([]);
    setStatus("Queue cleared.");
  }

  let clearPending = false;
  let clearResetTimer = null;

  function resetClearButton() {
    clearPending = false;
    clearButton.textContent = "Clear queue";
    clearResetTimer = null;
  }

  syncButton.addEventListener("click", syncQueue);
  exportButton.addEventListener("click", exportCsv);
  clearButton.addEventListener("click", async () => {
    if (!clearPending) {
      clearPending = true;
      clearButton.textContent = "Confirm clear?";
      clearResetTimer = setTimeout(resetClearButton, 3000);
      return;
    }
    clearTimeout(clearResetTimer);
    resetClearButton();
    try {
      await clearQueue();
    } catch (_error) {
      setStatus("Failed to clear queue.");
    }
  });

  await loadQueue();
})();
