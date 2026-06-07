// Server-Sent Events broadcaster.
// Any route handler that wants to push a data-changed notification to all
// connected browser tabs just calls broadcastDataChanged().
const clients = new Set();

export function addSseClient(res) {
  clients.add(res);
  res.on('close', () => clients.delete(res));
}

export function broadcastDataChanged() {
  if (clients.size === 0) return;
  const msg = 'event: data-changed\ndata: {}\n\n';
  for (const res of clients) {
    try { res.write(msg); } catch { clients.delete(res); }
  }
}

// Wire up process-level events emitted by extract.js so that any completed
// LLM job, availability check, or queue state change automatically pushes to
// all connected SSE clients.  Guard against multiple createApp() calls in tests.
let _listening = false;
export function initSseBroadcaster() {
  if (_listening) return;
  _listening = true;
  process.on('jobhunt:job-ready', broadcastDataChanged);
  process.on('jobhunt:job-unavailable', broadcastDataChanged);
  process.on('jobhunt:ai-processing-complete', broadcastDataChanged);
  process.on('jobhunt:queue-auto-paused', broadcastDataChanged);
}
