// Mirrors python/src/jobhunt/export.py

import { listDashboardJobs } from './db.js';

const CSV_COLUMNS = [
  'job_number', 'capture_id', 'job_id', 'status', 'rating', 'extraction_status',
  'company', 'title', 'location', 'remote_type', 'salary_min', 'salary_max',
  'salary_currency', 'salary_note', 'application_url', 'extraction_model',
  'source_url', 'captured_at', 'extracted_at',
];

function escapeCsv(value) {
  const s = String(value ?? '');
  if (s.includes(',') || s.includes('"') || s.includes('\n')) {
    return '"' + s.replace(/"/g, '""') + '"';
  }
  return s;
}

export function jobsCsv(dbPath) {
  const lines = [CSV_COLUMNS.join(',')];
  for (const job of listDashboardJobs(dbPath, 10000)) {
    const row = {
      job_number: job.job_number ?? '',
      capture_id: job.capture_id,
      job_id: job.job_id,
      status: job.status,
      rating: job.rating ?? '',
      extraction_status: job.extraction_status,
      company: job.company ?? '',
      title: job.title ?? job.page_title ?? '',
      location: job.location ?? '',
      remote_type: job.remote_type ?? '',
      salary_min: job.salary_min ?? '',
      salary_max: job.salary_max ?? '',
      salary_currency: job.salary_currency ?? '',
      salary_note: job.salary_note ?? '',
      application_url: job.application_url ?? '',
      extraction_model: job.extraction_model ?? '',
      source_url: job.source_url ?? '',
      captured_at: job.captured_at ?? '',
      extracted_at: job.extracted_at ?? '',
    };
    lines.push(CSV_COLUMNS.map(col => escapeCsv(row[col])).join(','));
  }
  return lines.join('\n') + '\n';
}
