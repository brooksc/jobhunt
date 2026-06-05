// Pure count helpers — shared between browser (dashboard.jsx, shell.jsx) and Node tests.
// No DOM, no React, no window globals.

/**
 * Count review pairs from a JH_DUPES array.
 * Each group contributes (jobIds.length - 1) pairs (one original, rest are candidates).
 * Matches the pairs count shown in the Duplicate review page header.
 */
export function countDuplicatePairs(dupes) {
  return (dupes || []).reduce((n, g) => n + Math.max(0, (g.jobIds || []).length - 1), 0);
}

/**
 * Build daily activity rows from a jobs array.
 * "saved" counts the capture date; "applied"/"interview"/"offer"/"rejected" count
 * status-change events — so activity totals are historical and will exceed current
 * status counts once jobs move forward in the pipeline.
 *
 * Returns rows sorted newest-first: [{ date, saved, applied, interview, offer, rejected }]
 */
export function buildDailyActivity(jobs) {
  const byDate = {};

  function bump(iso, key) {
    if (!iso) return;
    const dt = new Date(iso);
    const d = `${dt.getFullYear()}-${String(dt.getMonth() + 1).padStart(2, '0')}-${String(dt.getDate()).padStart(2, '0')}`;
    if (!byDate[d]) byDate[d] = { saved: 0, applied: 0, interview: 0, offer: 0, rejected: 0 };
    byDate[d][key]++;
  }

  for (const job of jobs) {
    bump(job.capturedAt, 'saved');
    for (const ev of (job.events || [])) {
      if (ev.kind === 'status' && ev.note) {
        const s = ev.note;
        if (s === 'applied' || s === 'interview' || s === 'offer' || s === 'rejected') {
          bump(ev.at, s);
        }
      }
    }
  }

  return Object.entries(byDate)
    .sort(([a], [b]) => b.localeCompare(a))
    .map(([date, counts]) => ({ date, ...counts }));
}

/**
 * Sum a column across all activity rows (the Total row in the UI).
 */
export function activityTotal(rows, key) {
  return rows.reduce((s, r) => s + (r[key] || 0), 0);
}
