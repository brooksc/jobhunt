(function () {
  const CSV_COLUMNS = [
    ["captured_at", item => item.payload?.captured_at || item.queued_at || ""],
    ["page_title", item => item.payload?.page_title || ""],
    ["url", item => item.payload?.url || ""],
    ["canonical_url", item => item.payload?.canonical_url || ""],
    ["selected_text", item => item.payload?.selected_text || ""],
    ["visible_text", item => item.payload?.visible_text || ""],
    // TASK-439: flag captures whose visible_text was trimmed to fit the storage quota, so an
    // exported row isn't mistaken for a full capture.
    ["visible_text_truncated", item => (item.payload?.visible_text_truncated ? "true" : "")],
    ["visible_text_original_chars", item => (item.payload?.visible_text_original_chars ?? "")],
    ["user_note", item => item.payload?.user_note || ""],
    ["queued_at", item => item.queued_at || ""],
  ];

  function csvEscape(value) {
    const text = String(value ?? "");
    if (!/[",\r\n]/.test(text)) {
      return text;
    }
    return `"${text.replace(/"/g, '""')}"`;
  }

  function queueToCsv(queue) {
    const rows = [
      CSV_COLUMNS.map(([name]) => name),
      ...queue.map(item => CSV_COLUMNS.map(([, read]) => read(item))),
    ];
    return rows.map(row => row.map(csvEscape).join(",")).join("\r\n");
  }

  function csvFilename(now = new Date()) {
    const stamp = now.toISOString().slice(0, 19).replace(/[-:T]/g, "");
    return `jobhunt-captures-${stamp}.csv`;
  }

  globalThis.jobhuntCsv = {
    CSV_COLUMNS,
    csvEscape,
    csvFilename,
    queueToCsv
  };
})();
