// Jobhunt — LLM request queue

function parseQueuePaused(value) {
  if (typeof value === "boolean") return value;
  if (value == null) return false;
  return String(value).toLowerCase() === "true";
}

function queueStatusTheme(status) {
  const map = {
    queued: { label: "Queued", color: "var(--st-screening)", text: "Pending" },
    running: { label: "Running", color: "var(--st-offer)", text: "Running" },
    failed: { label: "Failed", color: "var(--st-rejected)", text: "Failed" },
    canceled: { label: "Canceled", color: "var(--fg-faint)", text: "Canceled" },
  };
  return map[status] || { label: status, color: "var(--fg-faint)", text: status };
}

function hostFromSourceUrl(rawSourceUrl) {
  try {
    if (typeof rawSourceUrl !== "string") return "";
    return new URL(rawSourceUrl).hostname || "";
  } catch {
    return String(rawSourceUrl || "");
  }
}

function fmtQueueDuration(ms) {
  if (ms == null || Number.isNaN(Number(ms))) return "—";
  const totalSeconds = Math.max(0, Math.round(Number(ms) / 1000));
  if (totalSeconds < 60) return `${totalSeconds}s`;
  const minutes = Math.floor(totalSeconds / 60);
  const seconds = totalSeconds % 60;
  if (minutes < 60) return `${minutes}m ${seconds}s`;
  const hours = Math.floor(minutes / 60);
  return `${hours}h ${minutes % 60}m`;
}

function runningFor(item) {
  if (!item.started_at) return "—";
  const startedMs = new Date(item.started_at).getTime();
  if (!Number.isFinite(startedMs)) return "—";
  return fmtQueueDuration(Date.now() - startedMs);
}

function requestModelLabel(item) {
  return item.model || item.last_attempt_model_returned || item.last_attempt_model_requested || "—";
}

function lastAttemptSummary(item) {
  if (item.status === "queued" && item.last_attempt_status) {
    const bits = [`Previous run: ${item.last_attempt_status}`];
    if (item.last_attempt_response_format) bits.push(item.last_attempt_response_format);
    if (item.last_attempt_duration_ms != null) bits.push(fmtQueueDuration(item.last_attempt_duration_ms));
    return bits.join(" · ");
  }
  const bits = [];
  if (item.last_attempt_status) bits.push(item.last_attempt_status);
  if (item.last_attempt_response_format) bits.push(item.last_attempt_response_format);
  if (item.last_attempt_duration_ms != null) bits.push(fmtQueueDuration(item.last_attempt_duration_ms));
  return bits.length ? bits.join(" · ") : "No attempt history";
}

function attemptColumnLabel(item) {
  if (item.status === "queued" && item.last_attempt_status) return "Previous run";
  if (item.status === "running") return "Current attempt";
  return "Latest attempt";
}

function openQueuedJob(item) {
  if (!item?.job_number) return;
  window.location.hash = `#/jobs/${item.job_number}`;
}

function LlmQueuePage() {
  const [items, setItems] = React.useState(window.JH_LLM_QUEUE || []);
  const [queueFilter, setQueueFilter] = React.useState("all");
  const [loading, setLoading] = React.useState(true);
  const [error, setError] = React.useState(null);
  const [paused, setPaused] = React.useState(() => parseQueuePaused(window.JH_SETTINGS?.llm_queue_paused));
  const [actionId, setActionId] = React.useState(null);
  const [processing, setProcessing] = React.useState(false);
  const [expandedErrors, setExpandedErrors] = React.useState(() => new Set());
  const [attemptsByRequest, setAttemptsByRequest] = React.useState(() => ({}));
  const [sel, setSel] = React.useState(() => new Set());
  const [confirmCancelAll, setConfirmCancelAll] = React.useState(false);
  const selectAllRef = React.useRef(null);
  const lastSelectionRef = React.useRef(null);
  const pollInFlightRef = React.useRef(false);

  const [pendingUnqueued, setPendingUnqueued] = React.useState(0);
  const total = items.length;

  // Keep select-all checkbox indeterminate state in sync
  const queuedCount = items.filter((q) => q.status === "queued").length;
  const runningCount = items.filter((q) => q.status === "running").length;
  const failedCount = items.filter((q) => q.status === "failed").length;
  const runningItems = items.filter((q) => q.status === "running");
  const visibleItems = items.filter((item) => {
    if (queueFilter === "all") return true;
    if (queueFilter === "fit") return item.request_type === "fit_score";
    if (queueFilter === "extract") return item.request_type !== "fit_score";
    return item.status === queueFilter;
  });
  const visibleIds = new Set(visibleItems.map((item) => item.id));
  const visibleSelectedCount = [...sel].filter((id) => visibleIds.has(id)).length;

  React.useEffect(() => {
    if (!selectAllRef.current) return;
    selectAllRef.current.indeterminate = visibleSelectedCount > 0 && visibleSelectedCount < visibleItems.length;
  }, [visibleSelectedCount, visibleItems.length]);

  function toggleSelection(id, checked, shiftKey = false) {
    if (shiftKey && lastSelectionRef.current) {
      const start = visibleItems.findIndex((item) => item.id === lastSelectionRef.current);
      const end = visibleItems.findIndex((item) => item.id === id);
      if (start !== -1 && end !== -1) {
        const next = new Set(sel);
        const [from, to] = start < end ? [start, end] : [end, start];
        visibleItems.slice(from, to + 1).forEach((item) => {
          if (checked) next.add(item.id);
          else next.delete(item.id);
        });
        setSel(next);
        lastSelectionRef.current = id;
        return;
      }
    }
    const next = new Set(sel);
    checked ? next.add(id) : next.delete(id);
    setSel(next);
    lastSelectionRef.current = id;
  }

  async function refreshQueue(options = {}) {
    const { showSpinner = false } = options;
    try {
      if (showSpinner) {
        setLoading(true);
      }
      setError(null);
      const data = await window.JH_API.getLlmQueue();
      const next = Array.isArray(data?.items) ? data.items : [];
      setItems(next);
      setPaused(Boolean(data?.paused));
      setPendingUnqueued(data?.counts?.pending_unqueued || 0);
      window.JH_LLM_QUEUE = next;
      window.JH_QUEUE_STATS = {
        totalOutstanding: next.length + (data?.counts?.pending_unqueued || 0),
        queued: data?.counts?.queued || 0,
        running: data?.counts?.running || 0,
        failed: data?.counts?.failed || 0,
        pending_unqueued: data?.counts?.pending_unqueued || 0,
      };
      window.dispatchEvent(new Event(window.JH_LLM_QUEUE_REFRESH_EVENT || "jobhunt:llm-queue-refreshed"));
    } catch (e) {
      setError(e.message || String(e));
    } finally {
      if (showSpinner) {
        setLoading(false);
      }
    }
  }

  async function handlePause(nextPaused) {
    const wasPaused = paused;
    setPaused(nextPaused);
    try {
      await window.JH_API.setLlmQueuePaused(nextPaused);
      window.JH_SETTINGS.llm_queue_paused = String(nextPaused);
      await refreshQueue();
      if (wasPaused && !nextPaused) {
        // Queue was just resumed — kick off processing immediately
        processOutstanding();
      }
    } catch (e) {
      setPaused(wasPaused);
      window.JH_TOAST?.show(e.message || "Failed to update queue state", "error");
    }
  }

  async function cancelRequest(id) {
    setActionId(id);
    try {
      await window.JH_API.cancelLlmQueueRequest(id);
      await refreshQueue();
      window.JH_TOAST?.show("Request canceled");
    } catch (e) {
      window.JH_TOAST?.show(e.message || "Cancel request failed", "error");
    } finally {
      setActionId(null);
    }
  }

  async function cancelAllRequests() {
    const totalOutstanding = items.length;
    if (!totalOutstanding) return;
    setConfirmCancelAll(false);
    setActionId("__all__");
    try {
      const data = await window.JH_API.cancelAllLlmQueueRequests();
      await refreshQueue();
      window.JH_TOAST?.show(`Canceled ${data?.canceled || 0} request(s)`);
    } catch (e) {
      window.JH_TOAST?.show(e.message || "Cancel all requests failed", "error");
    } finally {
      setActionId(null);
    }
  }

  async function processOutstanding() {
    if (processing) return;
    setProcessing(true);
    const selectedIds = sel.size > 0 ? [...sel] : [];
    try {
      const result = await window.JH_API.processSelected(selectedIds);
      await refreshQueue();
      await window.JH_REFRESH_UI_DATA?.();
      setSel(new Set());
      const scope = selectedIds.length > 0 ? `${selectedIds.length} selected` : "all";
      window.JH_TOAST?.show(`Processed ${scope}: ${result?.succeeded || 0} succeeded, ${result?.failed || 0} failed`);
    } catch (e) {
      window.JH_TOAST?.show(e.message || "Process queue failed", "error");
    } finally {
      setProcessing(false);
    }
  }

  async function resetRunRequest(id) {
    setActionId(id);
    try {
      const result = await window.JH_API.resetRunLlmQueueRequest(id);
      await refreshQueue();
      await window.JH_REFRESH_UI_DATA?.();
      window.JH_TOAST?.show(`Processed request: ${result?.succeeded || 0} succeeded, ${result?.failed || 0} failed`);
    } catch (e) {
      window.JH_TOAST?.show(e.message || "Reset and run failed", "error");
    } finally {
      setActionId(null);
    }
  }

  async function toggleError(id) {
    const next = new Set(expandedErrors);
    if (next.has(id)) {
      next.delete(id);
    } else {
      next.add(id);
      if (!attemptsByRequest[id]) {
        try {
          const data = await window.JH_API.getLlmQueueAttempts(id);
          setAttemptsByRequest(prev => ({ ...prev, [id]: data?.attempts || [] }));
        } catch (e) {
          setAttemptsByRequest(prev => ({ ...prev, [id]: [{ status: "failed", error: e.message || String(e) }] }));
        }
      }
    }
    setExpandedErrors(next);
  }

  React.useEffect(() => {
    (async () => {
      await refreshQueue({ showSpinner: true });
      // Auto-enqueue any pending jobs so they're visible in the table
      const unqueued = window.JH_QUEUE_STATS?.pending_unqueued || 0;
      if (unqueued > 0) {
        try {
          await window.JH_API.enqueueAllPending();
          await refreshQueue();
        } catch { /* queue may already be running */ }
      }
    })();
  }, []);

  React.useEffect(() => {
    const POLL_MS = 5000;
    const poll = async () => {
      if (document.hidden || pollInFlightRef.current) {
        return;
      }
      pollInFlightRef.current = true;
      try {
        await refreshQueue();
      } finally {
        pollInFlightRef.current = false;
      }
    };

    const timerId = setInterval(poll, POLL_MS);

    const visibilityHandler = () => {
      if (!document.hidden) {
        poll();
      }
    };
    document.addEventListener("visibilitychange", visibilityHandler);

    return () => {
      clearInterval(timerId);
      document.removeEventListener("visibilitychange", visibilityHandler);
    };
  }, []);

  React.useEffect(() => {
    const refreshEvent = window.JH_SITE_UI_REFRESH_EVENT || "jobhunt:ui-data-refreshed";
    const refreshFromEvent = () => refreshQueue();
    window.addEventListener(refreshEvent, refreshFromEvent);
    return () => window.removeEventListener(refreshEvent, refreshFromEvent);
  }, []);

  return (
    <div style={{ overflow: "auto", flex: 1, minHeight: 0 }}>
      <div style={{ padding: "16px 16px 20px" }}>
        <div className="jh-row" style={{ gap: 8, alignItems: "center", marginBottom: 12, flexWrap: "wrap" }}>
          <div style={{ display: "flex", alignItems: "center", gap: 8, minWidth: 260 }}>
            <h2 style={{ margin: 0, color: "var(--fg-strong)", fontSize: 16 }}>LLM request queue</h2>
            <span className="jh-tag">{total + pendingUnqueued} outstanding</span>
          </div>
          <Btn
            kind="ghost"
            size="sm"
            icon={<Icon.Refresh size={12} />}
            onClick={() => refreshQueue({ showSpinner: true })}
            disabled={loading}
          >
            {loading ? "Refreshing…" : "Refresh"}
          </Btn>
          <Btn
            size="sm"
            kind="accent"
            icon={<Icon.Sparkles size={12} />}
            onClick={processOutstanding}
            disabled={processing || actionId !== null || (total === 0 && pendingUnqueued === 0)}
          >
            {processing ? "Running…" : sel.size > 0 ? `Run AI extraction (${sel.size})` : "Run AI extraction"}
          </Btn>
          <Btn
            size="sm"
            kind={paused ? "accent" : "ghost"}
            onClick={() => handlePause(!paused)}
            disabled={actionId !== null}
          >
            {paused ? "Resume queue" : "Pause queue"}
          </Btn>
          <Btn
            size="sm"
            kind="danger"
            icon={<Icon.Trash size={12} />}
            onClick={() => setConfirmCancelAll(true)}
            disabled={actionId !== null || total === 0}
          >
            Cancel all
          </Btn>
        </div>

        {paused && (
          <div className="jh-queue-paused-banner">
            <Icon.AlertTriangle size={14} style={{ flexShrink: 0 }} />
            <span>
              {failedCount >= 2
                ? <><strong>Queue auto-paused.</strong> Two consecutive extraction failures stopped processing to prevent repeated errors. Review the failed requests below, fix any provider or model issues in Settings, then resume.</>
                : <><strong>Queue paused.</strong> Processing is stopped — no new extractions will run until you resume.</>
              }
            </span>
            <Btn size="sm" kind="accent" onClick={() => handlePause(false)} disabled={actionId !== null}>
              Resume queue
            </Btn>
          </div>
        )}

        <div className="jh-row" style={{ gap: 8, marginBottom: 12, flexWrap: "wrap", color: "var(--fg-faint)", fontSize: 12 }}>
          <span>Queued: <span style={{ color: "var(--st-screening)", fontWeight: 600 }}>{queuedCount}</span></span>
          <span>Running: <span style={{ color: "var(--st-offer)", fontWeight: 600 }}>{runningCount}</span></span>
          <span>Failed: <span style={{ color: "var(--st-rejected)", fontWeight: 600 }}>{failedCount}</span></span>
          {pendingUnqueued > 0 && (
            <span style={{ display: "inline-flex", alignItems: "center", gap: 6 }}>
              <span>Pending (unqueued): <span style={{ color: "var(--fg-mute)", fontWeight: 600 }}>{pendingUnqueued}</span></span>
              <Btn size="sm" kind="ghost" onClick={async () => {
                try {
                  const res = await window.JH_API.enqueueAllPending();
                  window.JH_TOAST?.show(`${res.enqueued} job${res.enqueued !== 1 ? "s" : ""} added to queue`);
                  await refreshQueue();
                } catch (e) {
                  window.JH_TOAST?.show(e.message || "Failed to queue pending jobs", "error");
                }
              }}>Queue all</Btn>
            </span>
          )}
        </div>

        <div className="jh-toolbar" style={{ paddingLeft: 0, paddingRight: 0, borderTop: 0, marginBottom: 10 }}>
          {[
            ["all", "All", total],
            ["running", "Running", runningCount],
            ["failed", "Failed", failedCount],
            ["queued", "Queued", queuedCount],
            ["fit", "Fit", items.filter((i) => i.request_type === "fit_score").length],
            ["extract", "Extract", items.filter((i) => i.request_type !== "fit_score").length],
          ].map(([key, label, count]) => (
            <button
              key={key}
              className="jh-filter"
              data-active={queueFilter === key ? "true" : undefined}
              onClick={() => setQueueFilter(key)}
            >
              <span className="label">{label}</span>
              <span className="val">{count}</span>
            </button>
          ))}
        </div>

        {error && (
          <div style={{ marginBottom: 10, color: "var(--st-rejected)", background: "rgba(199,98,98,0.1)", border: "1px solid rgba(199,98,98,0.28)", borderRadius: 4, padding: 8, fontSize: 12 }}>
            {error}
          </div>
        )}

        {runningItems.length > 0 && (
          <div style={{
            marginBottom: 10,
            border: "1px solid rgba(78,145,96,0.35)",
            background: "rgba(78,145,96,0.10)",
            borderRadius: 6,
            padding: "9px 10px",
            display: "grid",
            gap: 6,
          }}>
            <div style={{ display: "flex", alignItems: "center", gap: 8, color: "var(--fg-strong)", fontSize: 12.5, fontWeight: 600 }}>
              <span style={{ width: 7, height: 7, borderRadius: 50, background: "var(--st-offer)" }}></span>
              Now running
            </div>
            {runningItems.map((item) => (
              <div key={item.id} style={{ display: "grid", gridTemplateColumns: "minmax(220px, 1fr) 90px 160px 160px", gap: 10, alignItems: "center", color: "var(--fg)", fontSize: 12 }}>
                <div style={{ minWidth: 0, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>
                  <span style={{ color: "var(--fg-strong)" }}>{item.title || "(untitled)"}</span>
                  <span style={{ color: "var(--fg-mute)" }}> · #{item.job_number || item.job_id}</span>
                </div>
                <span data-mono>{runningFor(item)}</span>
                <span data-mono title={requestModelLabel(item)} style={{ overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>{requestModelLabel(item)}</span>
                <span style={{ color: "var(--fg-mute)", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>{attemptColumnLabel(item)} · {lastAttemptSummary(item)}</span>
              </div>
            ))}
          </div>
        )}

        <div className="jh-tablewrap" style={{ maxHeight: "calc(100vh - 205px)" }}>
          <table className="jh-table" style={{ tableLayout: "fixed" }}>
            <colgroup>
              <col style={{ width: 32 }} />
              <col style={{ width: 92 }} />
              <col />
              <col style={{ width: 74 }} />
              <col style={{ width: 170 }} />
              <col style={{ width: 190 }} />
              <col style={{ width: 260 }} />
              <col style={{ width: 1, whiteSpace: "nowrap" }} />
            </colgroup>
            <thead>
              <tr>
                <th style={{ padding: "0 0 0 12px" }}>
                  <input
                    type="checkbox"
                    ref={selectAllRef}
                    className="jh-checkbox"
                    checked={visibleItems.length > 0 && visibleSelectedCount === visibleItems.length}
                    onChange={(e) => {
                      if (e.target.checked) {
                        setSel(new Set([...sel, ...visibleItems.map(i => i.id)]));
                      } else {
                        const next = new Set(sel);
                        visibleItems.forEach((item) => next.delete(item.id));
                        setSel(next);
                      }
                      lastSelectionRef.current = null;
                    }}
                    aria-label="Select all"
                  />
                </th>
                <th>Status</th>
                <th>Job</th>
                <th>Attempt</th>
                <th>Started</th>
                <th>Request attempt</th>
                <th>Error / details</th>
                <th>Actions</th>
              </tr>
            </thead>
            <tbody>
              {loading && items.length === 0 ? (
                <tr>
                  <td colSpan="8" style={{ color: "var(--fg-faint)", padding: "24px", textAlign: "center" }}>Loading queue…</td>
                </tr>
              ) : visibleItems.length === 0 ? (
                <tr>
                  <td colSpan="8" style={{ color: "var(--fg-faint)", padding: "24px", textAlign: "center" }}>
                    {items.length === 0 ? "No outstanding requests." : "No requests match this filter."}
                  </td>
                </tr>
              ) : (
                visibleItems.map((item) => {
                  const status = queueStatusTheme(item.status);
                  const isOpen = expandedErrors.has(item.id);
                  const displayError = item.error || item.last_attempt_error || "";
                  const hasError = !!displayError;
                  const attempts = attemptsByRequest[item.id] || [];
                  const isActionInFlight = actionId === item.id;
                  const isSelected = sel.has(item.id);
                  return (
                    <React.Fragment key={item.id}>
                      <tr data-selected={isSelected || undefined}>
                        <td style={{ padding: "0 0 0 12px" }}>
                          <input
                            type="checkbox"
                            className="jh-checkbox"
                            checked={isSelected}
                            onChange={(e) => toggleSelection(item.id, e.target.checked, e.nativeEvent.shiftKey)}
                            aria-label={`Select ${item.title || item.id}`}
                          />
                        </td>
                        <td>
                          <span style={{ display: "inline-flex", alignItems: "center", gap: 6 }}>
                            <span style={{ width: 6, height: 6, borderRadius: 50, background: status.color }}></span>
                            <span style={{ color: status.color }}>{status.label}</span>
                          </span>
                        </td>
                        <td style={{ color: "var(--fg)", minWidth: 0 }}>
                          <div style={{ display: "flex", flexDirection: "column", gap: 2, minWidth: 0 }}>
                            <span style={{ display: "inline-flex", alignItems: "center", gap: 6, minWidth: 0, color: "var(--fg-strong)", overflow: "hidden" }}>
                              <span
                                className="jh-tag"
                                style={{ height: 15, fontSize: 9.5, flexShrink: 0, textTransform: "uppercase", letterSpacing: 0.3 }}
                                title={item.request_type === "fit_score" ? "Resume fit scoring" : "Job extraction"}
                              >
                                {item.request_type === "fit_score" ? "Fit" : "Extract"}
                              </span>
                              <button
                                type="button"
                                onClick={() => openQueuedJob(item)}
                                title={`Open job #${item.job_number || item.job_id}`}
                                aria-label={`Open job #${item.job_number || item.job_id}`}
                                style={{
                                  minWidth: 0,
                                  display: "inline-block",
                                  maxWidth: "100%",
                                  flexShrink: 1,
                                  overflow: "hidden",
                                  textOverflow: "ellipsis",
                                  whiteSpace: "nowrap",
                                  color: "var(--fg-strong)",
                                  cursor: item.job_number ? "pointer" : "default",
                                  textAlign: "left",
                                }}
                              >
                                {item.title || "(untitled)"}
                              </button>
                              {item.source_url && (
                                <span style={{ color: "var(--fg-mute)", fontFamily: "var(--font-mono)", fontSize: 10.5 }} title={item.source_url}>
                                  · {hostFromSourceUrl(item.source_url)}
                                </span>
                              )}
                            </span>
                            <span style={{ display: "inline-flex", alignItems: "center", gap: 5, minWidth: 0, fontSize: 11, color: "var(--fg-faint)", fontFamily: "var(--font-mono)", whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>
                              <span>Request {item.id.slice(0, 8)}… ·</span>
                              <button
                                type="button"
                                onClick={() => openQueuedJob(item)}
                                aria-label={`Open job #${item.job_number || item.job_id}`}
                                style={{ color: "var(--fg-mute)", cursor: item.job_number ? "pointer" : "default", fontFamily: "var(--font-mono)", display: "inline-block", flexShrink: 0 }}
                                title={`Open job #${item.job_number || item.job_id}`}
                              >
                                #{item.job_number || item.job_id}
                              </button>
                            </span>
                          </div>
                        </td>
                        <td style={{ color: "var(--fg)", fontVariantNumeric: "tabular-nums" }}>{item.attempt || 1}</td>
                        <td className="col-mono">
                          <div style={{ display: "flex", flexDirection: "column", gap: 2 }}>
                            <span>{item.started_at ? fmtDateTime(item.started_at) : "—"}</span>
                            {item.status === "running" && <span style={{ color: "var(--st-offer)" }}>running {runningFor(item)}</span>}
                          </div>
                        </td>
                        <td>
                          <div style={{ display: "flex", flexDirection: "column", gap: 2, minWidth: 0 }}>
                            <span style={{ color: "var(--fg-faint)", fontSize: 10.5 }}>
                              {attemptColumnLabel(item)}
                            </span>
                            <span style={{ color: item.last_attempt_status === "failed" || item.last_attempt_status === "retry_exhausted" ? "var(--st-rejected)" : "var(--fg)", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>
                              {lastAttemptSummary(item)}
                            </span>
                            <span data-mono style={{ color: "var(--fg-mute)", fontSize: 10.5, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }} title={requestModelLabel(item)}>
                              {requestModelLabel(item)}
                            </span>
                          </div>
                        </td>
                        <td>
                          {!hasError ? (
                            <div>
                              <div style={{ display: "flex", alignItems: "center", gap: 6 }}>
                              <span style={{ color: "var(--fg-faint)", fontSize: 11 }}>—</span>
                              <Btn size="sm" kind="ghost" onClick={() => toggleError(item.id)}>
                                {isOpen ? "Hide details" : "Details"}
                              </Btn>
                              </div>
                              {isOpen && (
                                <pre style={{ margin: "6px 0 0", padding: 10, whiteSpace: "pre-wrap", overflow: "auto", maxHeight: 160, borderRadius: 4, background: "var(--bg-elev-2)", border: "1px solid var(--border)", color: "var(--fg)", fontSize: 11.5, fontFamily: "var(--font-mono)", lineHeight: 1.35 }}>
                                  {[
                                    item.model ? `model:   ${item.model}` : null,
                                    `type:    ${item.request_type || "extract"}`,
                                    `attempt: ${item.attempt || 1}`,
                                    item.last_attempt_response_format ? `format:  ${item.last_attempt_response_format}` : null,
                                    item.last_attempt_duration_ms != null ? `last:    ${fmtQueueDuration(item.last_attempt_duration_ms)}` : null,
                                    attempts.length ? `\nAttempt history:\n${attempts.map(a => [
                                      `#${a.attempt || "?"} ${a.status || "unknown"} ${a.duration_ms != null ? fmtQueueDuration(a.duration_ms) : ""}`.trim(),
                                      a.model_requested || a.model_returned ? `  model: ${a.model_requested || "?"}${a.model_returned ? ` -> ${a.model_returned}` : ""}` : null,
                                      a.response_format ? `  response_format: ${a.response_format}` : null,
                                      a.error ? `  error: ${a.error}` : null,
                                      a.response_preview ? `  response: ${a.response_preview}` : null,
                                    ].filter(Boolean).join("\n")).join("\n")}` : "\nAttempt history: no debug records yet",
                                  ].filter(l => l !== null).join("\n")}
                                </pre>
                              )}
                            </div>
                          ) : (
                            <div>
                              <div style={{ display: "flex", alignItems: "center", gap: 6 }}>
                                <span style={{ color: status.color, fontSize: 11, fontFamily: "var(--font-mono)", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap", minWidth: 0 }} title={displayError}>
                                  {displayError}
                                </span>
                                <Btn size="sm" kind="ghost" onClick={() => toggleError(item.id)}>
                                  {isOpen ? "Hide details" : "Show details"}
                                </Btn>
                              </div>
                              {isOpen && (
                                <pre style={{ margin: "6px 0 0", padding: 10, whiteSpace: "pre-wrap", overflow: "auto", maxHeight: 160, borderRadius: 4, background: "var(--bg-elev-2)", border: "1px solid var(--border)", color: "var(--fg)", fontSize: 11.5, fontFamily: "var(--font-mono)", lineHeight: 1.35 }}>
                                  {[
                                    item.model ? `model:   ${item.model}` : null,
                                    `type:    ${item.request_type || "extract"}`,
                                    `attempt: ${item.attempt || 1}`,
                                    item.last_attempt_response_format ? `format:  ${item.last_attempt_response_format}` : null,
                                    item.last_attempt_duration_ms != null ? `last:    ${fmtQueueDuration(item.last_attempt_duration_ms)}` : null,
                                    ``,
                                    displayError,
                                    attempts.length ? `\nAttempt history:\n${attempts.map(a => [
                                      `#${a.attempt || "?"} ${a.status || "unknown"} ${a.duration_ms != null ? fmtQueueDuration(a.duration_ms) : ""}`.trim(),
                                      a.model_requested || a.model_returned ? `  model: ${a.model_requested || "?"}${a.model_returned ? ` -> ${a.model_returned}` : ""}` : null,
                                      a.response_format ? `  response_format: ${a.response_format}` : null,
                                      a.error ? `  error: ${a.error}` : null,
                                      a.response_preview ? `  response: ${a.response_preview}` : null,
                                    ].filter(Boolean).join("\n")).join("\n")}` : "\nAttempt history: no debug records yet",
                                  ].filter(l => l !== null).join("\n")}
                                </pre>
                              )}
                            </div>
                          )}
                        </td>
                        <td style={{ whiteSpace: "nowrap" }}>
                          <div className="row-actions" style={{ visibility: "visible", justifyContent: "flex-end", gap: 4 }}>
                            <Btn
                              size="sm"
                              kind="ghost"
                              icon={<Icon.External size={11} />}
                              onClick={() => openQueuedJob(item)}
                              disabled={!item.job_number}
                              title={`Open job #${item.job_number || item.job_id}`}
                              aria-label={`Open queue job #${item.job_number || item.job_id}`}
                            >
                              Open job
                            </Btn>
                            {item.status === "failed" && (
                              <Btn
                                size="sm"
                                kind="ghost"
                                icon={<Icon.Refresh size={11} />}
                                onClick={() => resetRunRequest(item.id)}
                                disabled={isActionInFlight}
                                title="Reset attempts and run this request now"
                              >
                                {isActionInFlight ? "Running…" : "Reset + run"}
                              </Btn>
                            )}
                            <Btn
                              size="sm"
                              kind="danger"
                              icon={<Icon.Trash size={11} />}
                              onClick={() => cancelRequest(item.id)}
                              disabled={isActionInFlight || item.status === "canceled"}
                            >
                              {isActionInFlight ? "Canceling…" : "Cancel"}
                            </Btn>
                          </div>
                        </td>
                      </tr>
                    </React.Fragment>
                  );
                })
              )}
            </tbody>
          </table>
        </div>
        {confirmCancelAll && (
          <AppDialog
            title="Cancel all requests"
            onClose={() => setConfirmCancelAll(false)}
            actions={[
              { label: "Keep requests", kind: "ghost", onClick: () => setConfirmCancelAll(false) },
              { label: "Cancel all", kind: "danger", onClick: cancelAllRequests, disabled: actionId !== null },
            ]}
          >
            <p style={{ margin: 0, color: "var(--fg-mute)", lineHeight: 1.5 }}>
              Cancel all {items.length} outstanding request{items.length !== 1 ? "s" : ""}?
            </p>
          </AppDialog>
        )}
      </div>
    </div>
  );
}

Object.assign(window, { LlmQueuePage });
