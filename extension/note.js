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
    statusText.textContent = "Queued until Jobhunt is running.";
  } else if (response && response.ok) {
    statusText.textContent = "Saved.";
    window.setTimeout(() => window.close(), 500);
  } else {
    statusText.textContent = "Could not save.";
  }
});
