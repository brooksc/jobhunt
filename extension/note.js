const noteInput = document.getElementById("note");
const statusText = document.getElementById("status");

document.getElementById("cancel").addEventListener("click", () => {
  window.close();
});

document.getElementById("save").addEventListener("click", async () => {
  statusText.textContent = "Saving...";
  const response = await chrome.runtime.sendMessage({
    type: "captureWithNote",
    note: noteInput.value.trim()
  });

  if (response && response.ok && response.result?.queued) {
    statusText.textContent = "Queued until JobHunt is running.";
  } else if (response && response.ok) {
    statusText.textContent = "Saved.";
    window.setTimeout(() => window.close(), 500);
  } else {
    // Keep the window open so the user can retry. Pending tab context is preserved
    // in the service worker until capture succeeds.
    const detail = (response && response.error) ? `: ${response.error}` : "";
    statusText.textContent = `Could not save${detail}. Try again.`;
  }
});
