// Pure transform helpers — usable from both Node tests and browser scripts.
// Browser: loaded via <script type="module"> in index.html, exposed as window._JHT.
// Tests: imported directly as an ES module.

export function toStringArray(v) {
  if (Array.isArray(v)) return v;
  if (v == null || v === '') return [];
  return [String(v)];
}

export function mapStatus(s) {
  const map = {
    saved: 'saved', interested: 'saved',
    applied: 'applied',
    interviewing: 'interview',
    offer: 'offer',
    rejected: 'rejected',
    closed: 'archived', ignored: 'archived',
    duplicate: 'duplicate',
  };
  return map[s] || s;
}

export function mapRemote(r) {
  if (!r) return '—';
  return { remote: 'Remote', hybrid: 'Hybrid', onsite: 'Onsite', unknown: '—' }[r] || r;
}

export function mapEmployment(raw) {
  if (!raw) return '—';
  const map = {
    full_time: 'Full-time', fulltime: 'Full-time', 'full-time': 'Full-time',
    part_time: 'Part-time', parttime: 'Part-time', 'part-time': 'Part-time',
    contract: 'Contract', contractor: 'Contract',
    freelance: 'Freelance', internship: 'Internship', intern: 'Internship',
    temporary: 'Temporary', temp: 'Temporary',
  };
  const key = raw.toLowerCase().replace(/\s+/g, '_');
  return map[key] || map[raw.toLowerCase()] || (raw.charAt(0).toUpperCase() + raw.slice(1));
}

export function mapExtractionStatus(s) {
  if (s === 'succeeded') return 'ok';
  if (s === 'failed') return 'fail';
  return 'pending';
}

// Transform a single raw DB job row into the frontend job shape.
// extracted: pre-parsed extracted_json object (or null).
export function mapJobFields(j, extracted) {
  return {
    id: j.job_id,
    jobNumber: j.job_number,
    status: mapStatus(j.status),
    company: j.company || 'Unknown',
    title: j.title || j.page_title || 'Unknown',
    salaryMin: j.salary_min || null,
    salaryMax: j.salary_max || null,
    currency: j.salary_currency || null,
    salaryNote: j.salary_note || extracted?.salary_note || null,
    workMode: mapRemote(j.remote_type),
    employment: mapEmployment(extracted?.employment_type),
    seniority: extracted?.seniority || null,
    extraction: {
      status: mapExtractionStatus(j.extraction_status),
      at: j.extracted_at || null,
      model: j.extraction_model || null,
      error: j.extraction_error || null,
    },
    fit: {
      score: j.fit_score ?? null,
      status: j.fit_status || 'none',
    },
    skills: toStringArray(extracted?.skills),
    summary: extracted?.summary || null,
    requirements: toStringArray(extracted?.requirements),
    niceToHaves: toStringArray(extracted?.nice_to_haves),
    benefits: toStringArray(extracted?.benefits),
    unread: !!j.unread,
  };
}
