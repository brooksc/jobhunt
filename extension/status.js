(async function () {
  const summary = document.getElementById("summary");
  const queue = await jobhuntRetryQueue.getQueue(chrome.storage.local);
  const count = queue.length;

  summary.textContent = count === 1
    ? "1 capture is waiting for the Jobhunt Mac app."
    : `${count} captures are waiting for the Jobhunt Mac app.`;
})();
