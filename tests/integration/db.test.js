import { describe, it, before, after } from 'node:test';
import assert from 'node:assert/strict';
import {
  initDb, getSettings, setSetting, SETTINGS_DEFAULTS,
  insertCapture, updateJobStatus, addJobNote, JOB_STATUSES,
  getLlmQueueForProcessing, MAX_LLM_ATTEMPTS, resetJobExtraction,
  markLlmRequestRunning, startLlmRequestAttempt, finishLlmRequestAttempt,
  getLlmRequestAttempts, resetLlmRequestsForManualRun, getOutstandingLlmRequests,
  markExtractionSucceeded, markDataQualityReviewed, clearDataQualityReviewed, queueBulkLlmJobs,
  decideDuplicateGroup, detectDomainDuplicateJobs, decideDuplicateLinks,
  markJobRead, countUnreadJobs, markFitSucceeded, markFitFailed,
  addResume, listResumes, getActiveResumes, getResume, renameResume,
  updateResumeText, setResumeActive, deleteResume,
  queueFitScoreForJob, queueFitScoresForAllResumes, getLlmRequestsByIds,
} from '../../server/db.js';
import { runExtractionForSelected } from '../../server/extract.js';
import { tempDbPath, cleanupDb, CAPTURE, CAPTURE2 } from '../helpers.js';

// Each describe block gets its own isolated DB.

describe('getSettings / setSetting', () => {
  let dbPath;
  before(() => { dbPath = tempDbPath(); });
  after(() => cleanupDb(dbPath));

  it('returns defaults for a fresh database', () => {
    const db = initDb(dbPath);
    const settings = getSettings(db);
    assert.equal(settings.llm_base_url, SETTINGS_DEFAULTS.llm_base_url);
    assert.equal(settings.llm_model, SETTINGS_DEFAULTS.llm_model);
  });

  it('persists a setting across calls', () => {
    const db = initDb(dbPath);
    setSetting(db, 'llm_model', 'my-custom-model');
    const settings = getSettings(db);
    assert.equal(settings.llm_model, 'my-custom-model');
  });

  it('overwrites an existing setting', () => {
    const db = initDb(dbPath);
    setSetting(db, 'llm_model', 'model-v1');
    setSetting(db, 'llm_model', 'model-v2');
    const settings = getSettings(db);
    assert.equal(settings.llm_model, 'model-v2');
  });
});

describe('insertCapture', () => {
  let dbPath;
  before(() => { dbPath = tempDbPath(); initDb(dbPath); });
  after(() => cleanupDb(dbPath));

  it('creates a capture and job for a new URL', () => {
    const result = insertCapture(CAPTURE, dbPath);
    assert.ok(result.capture_id, 'capture_id should be set');
    assert.equal(result.duplicate, false);
    assert.equal(result.duplicate_of_job_id, null);
    assert.equal(result.created, true);
    assert.ok(result.job_id);
    assert.equal(result.job_number, 1);
  });

  it('immediately queues new job for extraction in llm_requests', () => {
    const localDbPath = tempDbPath();
    try {
      initDb(localDbPath);
      const result = insertCapture({ ...CAPTURE, url: 'https://example.com/queue-on-save' }, localDbPath);
      const db = initDb(localDbPath);
      const req = db.prepare("SELECT request_type, status FROM llm_requests WHERE job_id=?").get(result.job_id);
      assert.ok(req, 'llm_request should be created on save');
      assert.equal(req.request_type, 'extract');
      assert.equal(req.status, 'queued');
    } finally {
      cleanupDb(localDbPath);
    }
  });

  it('returns duplicate:false when re-capturing the same URL (existing job, not a new duplicate)', () => {
    const result = insertCapture(CAPTURE, dbPath);
    assert.equal(result.duplicate, false);
    assert.equal(result.created, false);
    assert.equal(result.job_number, 1);
  });

  it('treats different URLs with different content as separate jobs', () => {
    const result = insertCapture(CAPTURE2, dbPath);
    assert.equal(result.duplicate, false);
  });

  it('auto-increments job_number', () => {
    const dbPath2 = tempDbPath();
    try {
      initDb(dbPath2);
      const r1 = insertCapture(CAPTURE, dbPath2);
      const r2 = insertCapture(CAPTURE2, dbPath2);
      const db = initDb(dbPath2);
      const j1 = db.prepare('SELECT job_number FROM jobs WHERE capture_id=?').get(r1.capture_id);
      const j2 = db.prepare('SELECT job_number FROM jobs WHERE capture_id=?').get(r2.capture_id);
      assert.equal(j2.job_number, j1.job_number + 1);
    } finally {
      cleanupDb(dbPath2);
    }
  });

  it('requires visible_text or selected_text (not enforced in db layer)', () => {
    // db.insertCapture accepts empty text; validation is the API layer's job.
    // A capture with empty visible_text still inserts but cleaned_description is empty.
    const result = insertCapture({ url: 'https://empty.com/job', page_title: 'Empty', visible_text: '' }, dbPath);
    assert.ok(result.capture_id);
  });

  it('updates the original job when a different URL resolves to the same canonical URL', () => {
    const localDbPath = tempDbPath();
    try {
      initDb(localDbPath);
      const canonicalUrl = 'https://www.levels.fyi/jobs/title/technical-program-manager?jobId=138073367340032710';
      const first = insertCapture({
        url: 'https://www.levels.fyi/jobs/company/airbnb?jobId=138073367340032710',
        canonical_url: canonicalUrl,
        page_title: 'Senior Manager, Technical Program Management',
        visible_text: 'Old Levels capture for Airbnb TPM',
      }, localDbPath);
      const second = insertCapture({
        url: 'https://www.levels.fyi/jobs/title/technical-program-manager?jobId=138073367340032710',
        canonical_url: canonicalUrl,
        page_title: 'Sr. Staff Technical Program Manager - DoW',
        visible_text: 'Updated Levels capture for Zscaler TPM with full JD',
      }, localDbPath);
      const db = initDb(localDbPath);
      const jobs = db.prepare('SELECT id, capture_id, job_number, extraction_status FROM jobs ORDER BY job_number').all();
      const capture = db.prepare('SELECT url, canonical_url, cleaned_description FROM captures WHERE id=?').get(first.capture_id);
      const events = db.prepare("SELECT event_type FROM events WHERE job_id=? ORDER BY created_at").all(jobs[0].id);

      assert.equal(second.capture_id, first.capture_id);
      assert.equal(second.duplicate, false);
      assert.equal(second.created, false);
      assert.equal(jobs.length, 1);
      assert.equal(jobs[0].extraction_status, 'pending');
      assert.equal(capture.url, 'https://www.levels.fyi/jobs/title/technical-program-manager?jobId=138073367340032710');
      assert.equal(capture.canonical_url, canonicalUrl);
      assert.match(capture.cleaned_description, /Updated Levels capture/);
      assert.ok(events.some(e => e.event_type === 'recaptured'));
    } finally {
      cleanupDb(localDbPath);
    }
  });
});

describe('updateJobStatus', () => {
  let dbPath;
  let jobId;

  before(() => {
    dbPath = tempDbPath();
    initDb(dbPath);
    const result = insertCapture(CAPTURE, dbPath);
    const db = initDb(dbPath);
    const row = db.prepare('SELECT id FROM jobs WHERE capture_id=?').get(result.capture_id);
    jobId = row.id;
  });
  after(() => cleanupDb(dbPath));

  it('updates status to a valid value', () => {
    updateJobStatus(jobId, 'applied', dbPath);
    const db = initDb(dbPath);
    const row = db.prepare('SELECT status FROM jobs WHERE id=?').get(jobId);
    assert.equal(row.status, 'applied');
  });

  it('records a status_changed event', () => {
    updateJobStatus(jobId, 'interview', dbPath);
    const db = initDb(dbPath);
    const events = db.prepare("SELECT event_type, note FROM events WHERE job_id=? ORDER BY occurred_at").all(jobId);
    const statusEvents = events.filter(e => e.event_type === 'status_changed');
    assert.ok(statusEvents.length >= 1);
  });

  it('throws on an invalid status', () => {
    assert.throws(
      () => updateJobStatus(jobId, 'nonsense', dbPath),
      /invalid status/
    );
  });

  it('throws when job does not exist', () => {
    assert.throws(
      () => updateJobStatus('job_doesnotexist', 'saved', dbPath),
      /job not found/
    );
  });
});

describe('addJobNote', () => {
  let dbPath;
  let jobId;

  before(() => {
    dbPath = tempDbPath();
    initDb(dbPath);
    const result = insertCapture(CAPTURE, dbPath);
    const db = initDb(dbPath);
    const row = db.prepare('SELECT id FROM jobs WHERE capture_id=?').get(result.capture_id);
    jobId = row.id;
  });
  after(() => cleanupDb(dbPath));

  it('inserts a note_added event', () => {
    addJobNote(jobId, 'Great company culture', dbPath);
    const db = initDb(dbPath);
    const row = db.prepare("SELECT note FROM events WHERE job_id=? AND event_type='note_added'").get(jobId);
    assert.equal(row.note, 'Great company culture');
  });

  it('throws on empty note', () => {
    assert.throws(() => addJobNote(jobId, '', dbPath), /cannot be empty/);
    assert.throws(() => addJobNote(jobId, '   ', dbPath), /cannot be empty/);
  });

  it('throws when job does not exist', () => {
    assert.throws(
      () => addJobNote('job_missing', 'hello', dbPath),
      /job not found/
    );
  });
});

describe('extraction provenance persistence', () => {
  let dbPath;
  let jobId;

  before(() => {
    dbPath = tempDbPath();
    initDb(dbPath);
    const result = insertCapture({ ...CAPTURE, url: 'https://example.com/provenance' }, dbPath);
    const db = initDb(dbPath);
    jobId = db.prepare('SELECT id FROM jobs WHERE capture_id=?').get(result.capture_id).id;
  });
  after(() => cleanupDb(dbPath));

  it('persists model, application URL, confidence, and extracted JSON', () => {
    markExtractionSucceeded(jobId, {
      company: 'Acme',
      title: 'Principal TPM',
      location: 'Seattle, WA',
      remote_type: 'hybrid',
      salary_min: 120000,
      salary_max: 220000,
      salary_currency: 'USD',
      salary_note: '$120k-$220k',
      employment_type: 'full_time',
      seniority: 'principal',
      skills: ['technical program management'],
      summary: 'Owns delivery.',
      requirements: ['10+ years experience'],
      nice_to_haves: [],
      benefits: [],
      application_url: 'https://apply.example.com/jobs/provenance',
      confidence: { title: 0.9, company: 0.8, salary: 0.7 },
    }, dbPath, null, 'test-model-e2b', 0.8);

    const db = initDb(dbPath);
    const row = db.prepare(`SELECT extraction_status, extraction_model, application_url,
      extraction_confidence, extracted_json FROM jobs WHERE id=?`).get(jobId);
    const extracted = JSON.parse(row.extracted_json);

    assert.equal(row.extraction_status, 'succeeded');
    assert.equal(row.extraction_model, 'test-model-e2b');
    assert.equal(row.application_url, 'https://apply.example.com/jobs/provenance');
    assert.equal(row.extraction_confidence, 0.8);
    assert.equal(extracted.application_url, 'https://apply.example.com/jobs/provenance');
    assert.deepEqual(extracted.confidence, { title: 0.9, company: 0.8, salary: 0.7 });
  });
});

describe('duplicate decisions', () => {
  let dbPath;
  let cleanedHash;
  let jobIds;

  before(() => {
    dbPath = tempDbPath();
    initDb(dbPath);
    for (let i = 0; i < 3; i++) {
      insertCapture({
        url: `https://dupes.example.com/jobs/${i}`,
        page_title: `Duplicate ${i}`,
        visible_text: 'Same cleaned duplicate body',
      }, dbPath);
    }
    const db = initDb(dbPath);
    const rows = db.prepare(`SELECT jobs.id, captures.cleaned_hash
      FROM jobs JOIN captures ON captures.id=jobs.capture_id
      ORDER BY jobs.job_number`).all();
    jobIds = rows.map(r => r.id);
    cleanedHash = rows[0].cleaned_hash;
    assert.equal(new Set(rows.map(r => r.cleaned_hash)).size, 1);
  });
  after(() => cleanupDb(dbPath));

  it('merges groups larger than two while keeping the selected job', () => {
    const keepJobId = jobIds[1];
    decideDuplicateGroup(cleanedHash, 'merged', keepJobId, 'keep middle candidate', dbPath);

    const db = initDb(dbPath);
    const jobs = db.prepare('SELECT id, status, duplicate_of_job_id, duplicate_confidence FROM jobs ORDER BY job_number').all();
    const decision = db.prepare('SELECT decision, keep_job_id, note FROM duplicate_decisions WHERE cleaned_hash=?').get(cleanedHash);
    const events = db.prepare("SELECT job_id, event_type, note FROM events WHERE event_type='duplicate_decided'").all();

    assert.equal(decision.decision, 'merged');
    assert.equal(decision.keep_job_id, keepJobId);
    assert.equal(decision.note, 'keep middle candidate');
    assert.equal(jobs.find(j => j.id === keepJobId).status, 'saved');
    assert.equal(jobs.find(j => j.id === keepJobId).duplicate_of_job_id, null);
    for (const job of jobs.filter(j => j.id !== keepJobId)) {
      assert.equal(job.status, 'duplicate');
      assert.equal(job.duplicate_of_job_id, keepJobId);
      assert.equal(job.duplicate_confidence, 1);
    }
    assert.equal(events.length, 3);
    assert.ok(events.every(e => e.note === 'merged'));
  });

  it('marks a group as not duplicate and clears duplicate links', () => {
    decideDuplicateGroup(cleanedHash, 'not_duplicate', null, '', dbPath);

    const db = initDb(dbPath);
    const jobs = db.prepare('SELECT duplicate_of_job_id, duplicate_confidence FROM jobs ORDER BY job_number').all();
    const decision = db.prepare('SELECT decision, keep_job_id FROM duplicate_decisions WHERE cleaned_hash=?').get(cleanedHash);

    assert.equal(decision.decision, 'not_duplicate');
    assert.equal(decision.keep_job_id, null);
    assert.ok(jobs.every(j => j.duplicate_of_job_id === null));
    assert.ok(jobs.every(j => j.duplicate_confidence === null));
  });
});

describe('domain duplicate detection', () => {
  let dbPath;
  before(() => { dbPath = tempDbPath(); initDb(dbPath); });
  after(() => cleanupDb(dbPath));

  function capturedJob(url, pageTitle, visibleText) {
    const result = insertCapture({ url, page_title: pageTitle, visible_text: visibleText }, dbPath);
    const db = initDb(dbPath);
    return db.prepare('SELECT id FROM jobs WHERE capture_id=?').get(result.capture_id).id;
  }

  const staffEngineerDescription = [
    'Lead distributed telemetry pipeline development for enterprise customers.',
    'Design scalable data processing services using JavaScript, TypeScript, SQL, and cloud infrastructure.',
    'Partner with product managers, security engineers, support teams, and reliability specialists.',
    'Own incident response, architecture reviews, performance tuning, roadmap planning, and mentoring.',
  ].join(' ');

  it('links the weaker source-domain match for duplicate review', () => {
    const companyJob = capturedJob(
      'https://cribl.io/careers/jobs/staff-engineer',
      'Staff Engineer - CRIBL',
      staffEngineerDescription,
    );
    const boardJob = capturedJob(
      'https://www.builtinseattle.com/job/staff-engineer-cribl',
      'Staff Engineer at CRIBL',
      `${staffEngineerDescription} Built In Seattle listing metadata.`,
    );

    markExtractionSucceeded(companyJob, {
      company: 'CRIBL',
      title: 'Staff Engineer',
      location: 'Remote',
      remote_type: 'remote',
      salary_min: 180000,
      salary_max: 220000,
      salary_currency: 'USD',
    }, dbPath);
    markExtractionSucceeded(boardJob, {
      company: 'CRIBL',
      title: 'Staff Engineer',
      location: 'Remote',
      remote_type: 'remote',
      salary_min: 180000,
      salary_max: 220000,
      salary_currency: 'USD',
    }, dbPath);

    const db = initDb(dbPath);
    const rows = db.prepare('SELECT id, status, duplicate_of_job_id, duplicate_confidence FROM jobs WHERE id IN (?, ?) ORDER BY id').all(companyJob, boardJob);
    const preferred = rows.find(row => row.id === companyJob);
    const candidate = rows.find(row => row.id === boardJob);

    assert.equal(preferred.status, 'saved');
    assert.equal(preferred.duplicate_of_job_id, null);
    assert.equal(candidate.status, 'saved');
    assert.equal(candidate.duplicate_of_job_id, companyJob);
    assert.ok(candidate.duplicate_confidence > 0.9);
  });

  it('marks reviewed duplicate candidates as duplicate', () => {
    const companyJob = capturedJob(
      'https://reviewed.example.com/careers/jobs/platform-engineer',
      'Platform Engineer',
      staffEngineerDescription,
    );
    const boardJob = capturedJob(
      'https://boards.example.net/reviewed/platform-engineer',
      'Platform Engineer',
      staffEngineerDescription,
    );

    markExtractionSucceeded(companyJob, {
      company: 'Reviewed',
      title: 'Platform Engineer',
      location: 'Remote',
      remote_type: 'remote',
    }, dbPath);
    markExtractionSucceeded(boardJob, {
      company: 'Reviewed',
      title: 'Platform Engineer',
      location: 'Remote',
      remote_type: 'remote',
    }, dbPath);
    decideDuplicateLinks([companyJob, boardJob], 'merged', companyJob, 'reviewed duplicate', dbPath);

    const db = initDb(dbPath);
    const duplicate = db.prepare('SELECT status, duplicate_of_job_id FROM jobs WHERE id=?').get(boardJob);

    assert.equal(duplicate.status, 'duplicate');
    assert.equal(duplicate.duplicate_of_job_id, companyJob);
  });

  it('does not link candidates with conflicting critical fields', () => {
    const companyJob = capturedJob(
      'https://salarycheck.example.com/careers/jobs/staff-engineer',
      'Staff Engineer',
      staffEngineerDescription,
    );
    const boardJob = capturedJob(
      'https://jobs.example.org/salarycheck/staff-engineer',
      'Staff Engineer',
      staffEngineerDescription,
    );

    markExtractionSucceeded(companyJob, {
      company: 'Salarycheck',
      title: 'Staff Engineer',
      location: 'Remote',
      remote_type: 'remote',
      salary_min: 180000,
      salary_max: 220000,
      salary_currency: 'USD',
    }, dbPath);
    markExtractionSucceeded(boardJob, {
      company: 'Salarycheck',
      title: 'Staff Engineer',
      location: 'Remote',
      remote_type: 'remote',
      salary_min: 120000,
      salary_max: 150000,
      salary_currency: 'USD',
    }, dbPath);

    const db = initDb(dbPath);
    const rows = db.prepare('SELECT status, duplicate_of_job_id FROM jobs WHERE id IN (?, ?)').all(companyJob, boardJob);

    assert.ok(rows.every(row => row.status === 'saved'));
    assert.ok(rows.every(row => row.duplicate_of_job_id === null));
  });

  it('leaves ambiguous equal-score matches untouched', () => {
    const firstJob = capturedJob(
      'https://jobs.example.com/acme/staff-engineer',
      'Staff Engineer at Acme',
      'Acme staff engineer listing from the first site.',
    );
    const secondJob = capturedJob(
      'https://boards.example.org/acme/staff-engineer',
      'Staff Engineer at Acme',
      'Acme staff engineer listing from the second site.',
    );

    markExtractionSucceeded(firstJob, {
      company: 'Acme',
      title: 'Staff Engineer',
      location: 'Remote',
      remote_type: 'remote',
    }, dbPath);
    markExtractionSucceeded(secondJob, {
      company: 'Acme',
      title: 'Staff Engineer',
      location: 'Remote',
      remote_type: 'remote',
    }, dbPath);

    const summary = detectDomainDuplicateJobs(dbPath);
    const db = initDb(dbPath);
    const rows = db.prepare('SELECT status, duplicate_of_job_id FROM jobs WHERE id IN (?, ?)').all(firstJob, secondJob);

    assert.equal(summary.jobs_marked, 0);
    assert.ok(rows.every(row => row.status === 'saved'));
    assert.ok(rows.every(row => row.duplicate_of_job_id === null));
  });

  it('groups jobs whose company names differ only by legal suffix (e.g. "Akamai Technologies" vs "Akamai")', () => {
    const desc = staffEngineerDescription;
    const jobA = capturedJob('https://jobs.akamai.com/job/2695', 'Senior TPM - Akamai', desc);
    const jobB = capturedJob('https://www.builtinseattle.com/job/senior-tpm-akamai', 'Senior TPM at Akamai Technologies', `${desc} BuiltIn listing.`);

    markExtractionSucceeded(jobA, { company: 'Akamai', title: 'Senior Technical Program Manager', location: 'Remote', remote_type: 'remote' }, dbPath);
    markExtractionSucceeded(jobB, { company: 'Akamai Technologies', title: 'Senior Technical Program Manager', location: 'Remote', remote_type: 'remote' }, dbPath);

    detectDomainDuplicateJobs(dbPath);
    const db = initDb(dbPath);
    const rows = db.prepare('SELECT status, duplicate_of_job_id FROM jobs WHERE id IN (?, ?)').all(jobA, jobB);
    const hasLink = rows.some(r => r.duplicate_of_job_id !== null);
    assert.ok(hasLink, 'one job should be linked as duplicate of the other despite suffix difference');
  });
});

describe('data quality review persistence', () => {
  let dbPath;
  let jobId;

  before(() => {
    dbPath = tempDbPath();
    initDb(dbPath);
    const result = insertCapture({ ...CAPTURE, url: 'https://example.com/data-quality-review' }, dbPath);
    const db = initDb(dbPath);
    jobId = db.prepare('SELECT id FROM jobs WHERE capture_id=?').get(result.capture_id).id;
  });
  after(() => cleanupDb(dbPath));

  it('marks and clears reviewed data-quality rows', () => {
    const marked = markDataQualityReviewed([jobId], 'checked manually', dbPath);
    assert.equal(marked.updated, 1);

    const db = initDb(dbPath);
    const row = db.prepare('SELECT note, reviewed_at FROM data_quality_reviews WHERE job_id=?').get(jobId);
    assert.equal(row.note, 'checked manually');
    assert.ok(row.reviewed_at);

    const cleared = clearDataQualityReviewed([jobId], dbPath);
    assert.equal(cleared.updated, 1);
    assert.equal(db.prepare('SELECT COUNT(*) AS n FROM data_quality_reviews WHERE job_id=?').get(jobId).n, 0);
  });
});

describe('bulk LLM queueing', () => {
  let dbPath;
  let completeJobId;
  let missingJobId;

  before(() => {
    dbPath = tempDbPath();
    initDb(dbPath);
    const complete = insertCapture({ ...CAPTURE, url: 'https://example.com/bulk-llm-complete' }, dbPath);
    const missing = insertCapture({ ...CAPTURE2, url: 'https://example.com/bulk-llm-missing' }, dbPath);
    const db = initDb(dbPath);
    completeJobId = db.prepare('SELECT id FROM jobs WHERE capture_id=?').get(complete.capture_id).id;
    missingJobId = db.prepare('SELECT id FROM jobs WHERE capture_id=?').get(missing.capture_id).id;
    markExtractionSucceeded(completeJobId, {
      company: 'Complete Co',
      title: 'Complete TPM',
      location: 'Seattle, WA',
      remote_type: 'hybrid',
      salary_min: 150000,
      salary_max: 220000,
      salary_currency: 'USD',
      salary_note: '$150k-$220k',
      employment_type: 'full_time',
      seniority: 'senior',
      skills: [],
      summary: '',
      requirements: [],
      nice_to_haves: [],
      benefits: [],
      application_url: null,
      confidence: {},
    }, dbPath, null, 'test-model', 0.9);
  });
  after(() => cleanupDb(dbPath));

  it('queues only selected jobs missing AI fields in missing_fields mode', () => {
    const result = queueBulkLlmJobs([completeJobId, missingJobId], 'missing_fields', dbPath);
    assert.equal(result.requested, 2);
    assert.equal(result.queued, 1);
    assert.equal(result.skipped, 1);

    const db = initDb(dbPath);
    const request = db.prepare("SELECT job_id, request_type, status, attempt FROM llm_requests WHERE job_id=?").get(missingJobId);
    assert.equal(request.request_type, 'extract');
    assert.equal(request.status, 'queued');
    assert.equal(request.attempt, 1);
  });

  it('queues fit scoring only for extracted jobs, one request per active resume', () => {
    addResume(dbPath, { name: 'R1', text: 'resume one text' });
    addResume(dbPath, { name: 'R2', text: 'resume two text' });
    const result = queueBulkLlmJobs([completeJobId, missingJobId], 'fit_score', dbPath);
    assert.equal(result.requested, 2);
    assert.equal(result.queued, 1);   // only the extracted job
    assert.equal(result.skipped, 1);
    assert.equal(result.request_ids.length, 2); // fanned out across 2 resumes

    const db = initDb(dbPath);
    const requests = db.prepare("SELECT resume_id, status, attempt FROM llm_requests WHERE job_id=? AND request_type='fit_score'").all(completeJobId);
    assert.equal(requests.length, 2);
    assert.ok(requests.every(r => r.resume_id && r.status === 'queued' && r.attempt === 1));
  });
});

describe('LLM queue retry limit', () => {
  let dbPath;
  let jobId;

  before(() => {
    dbPath = tempDbPath();
    initDb(dbPath);
    const result = insertCapture(CAPTURE, dbPath);
    const db = initDb(dbPath);
    jobId = db.prepare('SELECT id FROM jobs WHERE capture_id=?').get(result.capture_id).id;
  });
  after(() => cleanupDb(dbPath));

  it('does not return requests that exceeded max attempts for processing', () => {
    resetJobExtraction(jobId, dbPath);
    const db = initDb(dbPath);
    db.prepare("UPDATE llm_requests SET status='queued', attempt=? WHERE job_id=? AND request_type='extract'")
      .run(MAX_LLM_ATTEMPTS + 1, jobId);

    const requests = getLlmQueueForProcessing(dbPath, 10);
    assert.equal(requests.some(r => r.job_id === jobId), false);

    const request = db.prepare("SELECT status, attempt, error FROM llm_requests WHERE job_id=? AND request_type='extract'").get(jobId);
    assert.equal(request.status, 'failed');
    assert.equal(request.attempt, MAX_LLM_ATTEMPTS);
    assert.match(request.error, /Retry limit reached/);
  });

  it('records durable attempt history for a failed request', () => {
    const result = insertCapture({ ...CAPTURE2, url: 'https://example.com/debug-attempt' }, dbPath);
    const db = initDb(dbPath);
    const debugJobId = db.prepare('SELECT id FROM jobs WHERE capture_id=?').get(result.capture_id).id;
    const requestId = resetJobExtraction(debugJobId, dbPath);
    assert.equal(markLlmRequestRunning(requestId, dbPath), true);

    const attemptId = startLlmRequestAttempt(dbPath, requestId, {
      baseUrl: 'http://127.0.0.1:1234',
      modelRequested: 'test-model',
      promptChars: 123,
    });
    finishLlmRequestAttempt(dbPath, attemptId, {
      status: 'failed',
      modelReturned: 'test-model',
      responseFormat: 'json_schema',
      error: 'LLM response did not contain a JSON object',
      responsePreview: 'not json',
      responseChars: 8,
    });

    const attempts = getLlmRequestAttempts(dbPath, requestId);
    assert.equal(attempts.length, 1);
    assert.equal(attempts[0].status, 'failed');
    assert.equal(attempts[0].model_requested, 'test-model');
    assert.equal(attempts[0].response_format, 'json_schema');
    assert.equal(attempts[0].response_preview, 'not json');
    assert.match(attempts[0].error, /JSON object/);
  });

  it('resets exhausted requests for an explicit manual run', () => {
    const result = insertCapture({ ...CAPTURE2, url: 'https://example.com/manual-retry' }, dbPath);
    const db = initDb(dbPath);
    const manualJobId = db.prepare('SELECT id FROM jobs WHERE capture_id=?').get(result.capture_id).id;
    const requestId = resetJobExtraction(manualJobId, dbPath);
    db.prepare("UPDATE llm_requests SET status='failed', attempt=?, error='Retry limit reached' WHERE id=?")
      .run(MAX_LLM_ATTEMPTS, requestId);

    const reset = resetLlmRequestsForManualRun(dbPath, [requestId]);
    assert.equal(reset, 1);

    const request = db.prepare("SELECT status, attempt, error FROM llm_requests WHERE id=?").get(requestId);
    assert.equal(request.status, 'queued');
    assert.equal(request.attempt, 1);
    assert.equal(request.error, null);
    assert.equal(markLlmRequestRunning(requestId, dbPath), true);
  });

  it('lists running requests before queued requests in the visible queue', () => {
    const localDbPath = tempDbPath();
    try {
      initDb(localDbPath);
      const first = insertCapture({ ...CAPTURE, url: 'https://example.com/queue-first' }, localDbPath);
      const second = insertCapture({ ...CAPTURE2, url: 'https://example.com/queue-running' }, localDbPath);
      const db = initDb(localDbPath);
      const firstJobId = db.prepare('SELECT id FROM jobs WHERE capture_id=?').get(first.capture_id).id;
      const secondJobId = db.prepare('SELECT id FROM jobs WHERE capture_id=?').get(second.capture_id).id;
      resetJobExtraction(firstJobId, localDbPath);
      const runningRequestId = resetJobExtraction(secondJobId, localDbPath);
      assert.equal(markLlmRequestRunning(runningRequestId, localDbPath), true);

      const requests = getOutstandingLlmRequests(localDbPath, ['queued', 'running', 'failed'], null);
      assert.equal(requests[0].id, runningRequestId);
      assert.equal(requests[0].status, 'running');
    } finally {
      cleanupDb(localDbPath);
    }
  });

  it('processes selected extraction and fit-score requests through the queue state machine', async () => {
    const result = insertCapture({ ...CAPTURE2, url: 'https://example.com/selected-processing' }, dbPath);
    const db = initDb(dbPath);
    const selectedJobId = db.prepare('SELECT id FROM jobs WHERE capture_id=?').get(result.capture_id).id;
    const extractRequestId = resetJobExtraction(selectedJobId, dbPath);

    const extractSummary = await runExtractionForSelected({
      dbPath,
      requestIds: [extractRequestId],
      extractor: {
        baseUrl: 'http://127.0.0.1:1234',
        model: 'fake-extractor',
        async extract() {
          return {
            modelName: 'fake-extractor',
            responseFormatType: 'json_schema',
            extracted: {
              company: 'Queue Co',
              title: 'Queue TPM',
              location: 'Remote',
              remote_type: 'remote',
              salary_min: 170000,
              salary_max: 230000,
              salary_currency: 'USD',
              salary_note: '$170k-$230k',
              employment_type: 'full_time',
              seniority: 'senior',
              skills: ['program management'],
              summary: 'Queue processing.',
              requirements: [],
              nice_to_haves: [],
              benefits: [],
              application_url: null,
              confidence: { location: 0.9 },
            },
          };
        },
      },
      scorer: null,
    });
    assert.deepEqual(extractSummary, { processed: 1, succeeded: 1, failed: 0 });

    const extracted = db.prepare("SELECT extraction_status, location FROM jobs WHERE id=?").get(selectedJobId);
    assert.equal(extracted.extraction_status, 'succeeded');
    assert.equal(extracted.location, 'Remote');
    assert.equal(db.prepare("SELECT status FROM llm_requests WHERE id=?").get(extractRequestId).status, 'succeeded');

    addResume(dbPath, { name: 'TPM resume', text: 'Principal technical program manager resume' });
    const fitQueue = queueBulkLlmJobs([selectedJobId], 'fit_score', dbPath);
    const fitRequestId = fitQueue.request_ids[0];
    const fitSummary = await runExtractionForSelected({
      dbPath,
      requestIds: [fitRequestId],
      extractor: null,
      scorer: {
        baseUrl: 'http://127.0.0.1:1234',
        model: 'fake-scorer',
        async score() {
          return {
            modelName: 'fake-scorer',
            responseFormatType: 'json_schema',
            fit: {
              overall_score: 91,
              summary: 'Strong fit.',
              dimensions: [{ name: 'skills', score: 90, rationale: 'Relevant skills.' }],
              requirements_met: ['TPM'],
              requirements_not_met: [],
            },
          };
        },
      },
    });

    assert.deepEqual(fitSummary, { processed: 1, succeeded: 1, failed: 0 });
    const fit = db.prepare("SELECT fit_status, fit_score FROM jobs WHERE id=?").get(selectedJobId);
    assert.equal(fit.fit_status, 'succeeded');
    assert.equal(fit.fit_score, 91);
    assert.equal(db.prepare("SELECT status FROM llm_requests WHERE id=?").get(fitRequestId).status, 'succeeded');
  });
});

describe('unread badge tracking', () => {
  let dbPath;
  before(() => { dbPath = tempDbPath(); initDb(dbPath); });
  after(() => cleanupDb(dbPath));

  it('starts at 0 unread for a fresh DB', () => {
    assert.equal(countUnreadJobs(dbPath), 0);
  });

  it('markFitSucceeded sets unread=1 and countUnreadJobs reflects it', () => {
    const { job_id } = insertCapture(CAPTURE, dbPath);
    const resume = addResume(dbPath, { name: 'R', text: 'resume text' });
    markFitSucceeded(job_id, resume.id, {
      overall_score: 75, summary: 'Good fit.', dimensions: [],
      requirements_met: [], requirements_not_met: [],
    }, dbPath, null, 'test-model');

    assert.equal(countUnreadJobs(dbPath), 1);
    const db = initDb(dbPath);
    assert.equal(db.prepare('SELECT unread FROM jobs WHERE id=?').get(job_id).unread, 1);
    assert.equal(db.prepare('SELECT fit_score FROM jobs WHERE id=?').get(job_id).fit_score, 75);
  });

  it('markJobRead clears unread and countUnreadJobs decrements', () => {
    const db = initDb(dbPath);
    const jobs = db.prepare('SELECT id FROM jobs WHERE unread=1').all();
    assert.ok(jobs.length > 0);
    markJobRead(jobs[0].id, dbPath);
    assert.equal(db.prepare('SELECT unread FROM jobs WHERE id=?').get(jobs[0].id).unread, 0);
    assert.equal(countUnreadJobs(dbPath), 0);
  });

  it('markJobRead on already-read job is a no-op', () => {
    const db = initDb(dbPath);
    const { job_id } = insertCapture(CAPTURE2, dbPath);
    markJobRead(job_id, dbPath);
    assert.equal(db.prepare('SELECT unread FROM jobs WHERE id=?').get(job_id).unread, 0);
    assert.equal(countUnreadJobs(dbPath), 0);
  });
});
