// Demo database seeding — creates a representative dataset for first-run exploration.
import { copyFileSync, existsSync } from 'fs';
import { dirname, join } from 'path';
import { fileURLToPath } from 'url';
import { initDb, appConfigDir } from './db.js';

const __dirname = dirname(fileURLToPath(import.meta.url));
// Bundled seed template checked into the repo — never written to at runtime.
const SEED_DB_PATH = join(__dirname, 'demo.db');
// Writable working copy — resolved at import time so JOBHUNT_CONFIG_DIR is already set
// by electron/main.js for Electron builds (both DMG and MAS) before this module loads.
export const DEMO_DB_PATH = join(appConfigDir(), 'demo.db');

function daysAgo(n) {
  return new Date(Date.now() - n * 24 * 3600 * 1000).toISOString();
}

function uid(prefix, n) {
  return `${prefix}_${String(n).padStart(3, '0')}`;
}

// Representative job data — covers all statuses, salary ranges, remote modes, extraction states.
const SEED = {
  jobs: [
    {
      capId: uid('cap', 1), jobId: uid('job', 1), jobNum: 1,
      url: 'https://www.linkedin.com/jobs/view/4001234567',
      pageTitle: 'Senior Technical Program Manager · Stripe',
      company: 'Stripe', title: 'Senior Technical Program Manager',
      status: 'offer', remote_type: 'remote', location: 'Remote - USA',
      salary_min: 230000, salary_max: 295000, salary_currency: 'USD',
      employment_type: 'full_time', seniority: 'senior',
      summary: 'Lead cross-functional programs for Stripe\'s payment infrastructure, coordinating between engineering, product, and legal to ship global expansion initiatives.',
      requirements: 'BS/MS in CS or related. 8+ years of technical program management. Experience with distributed systems and API platforms. Strong stakeholder management.',
      skills: ['program management', 'distributed systems', 'APIs', 'OKRs', 'cross-functional leadership'],
      capturedAt: daysAgo(21), extractedAt: daysAgo(21), fit_score: 91, fit_status: 'scored',
      note: 'Verbal offer received — negotiating comp. Recruiter mentioned they can move on equity.',
    },
    {
      capId: uid('cap', 2), jobId: uid('job', 2), jobNum: 2,
      url: 'https://careers.google.com/jobs/results/98765432',
      pageTitle: 'Staff Technical Program Manager, Infrastructure · Google Careers',
      company: 'Google', title: 'Staff Technical Program Manager, Infrastructure',
      status: 'interview', remote_type: 'hybrid', location: 'Sunnyvale, CA',
      salary_min: 220000, salary_max: 310000, salary_currency: 'USD',
      employment_type: 'full_time', seniority: 'staff',
      summary: 'Drive multi-year infrastructure programs across SRE, SWE, and Cloud teams. Own program health, risk mitigation, and executive communication for planet-scale systems.',
      requirements: '10+ years TPM or engineering leadership. Experience with large-scale infra or platform programs. Excellent written and verbal communication.',
      skills: ['infrastructure', 'SRE', 'program management', 'executive communication', 'risk management'],
      capturedAt: daysAgo(18), extractedAt: daysAgo(18), fit_score: 84, fit_status: 'scored',
      note: 'Final round scheduled for Thursday — 4 interviews. Prep: system design + behavioral.',
    },
    {
      capId: uid('cap', 3), jobId: uid('job', 3), jobNum: 3,
      url: 'https://www.anthropic.com/careers/staff-tpm',
      pageTitle: 'Staff Technical Program Manager · Anthropic',
      company: 'Anthropic', title: 'Staff Technical Program Manager',
      status: 'interview', remote_type: 'hybrid', location: 'San Francisco, CA',
      salary_min: 250000, salary_max: 340000, salary_currency: 'USD',
      employment_type: 'full_time', seniority: 'staff',
      summary: 'Own delivery of safety-critical AI research and deployment programs. Partner with research leads to translate model work into product milestones.',
      requirements: 'Strong technical background (CS or equivalent). 8+ years TPM. Prior work in AI/ML or safety-focused environments a plus.',
      skills: ['AI/ML', 'safety programs', 'research coordination', 'technical program management'],
      capturedAt: daysAgo(10), extractedAt: daysAgo(10), fit_score: 79, fit_status: 'scored',
    },
    {
      capId: uid('cap', 4), jobId: uid('job', 4), jobNum: 4,
      url: 'https://www.linkedin.com/jobs/view/4009876543',
      pageTitle: 'Principal Technical Program Manager · Microsoft',
      company: 'Microsoft', title: 'Principal Technical Program Manager',
      status: 'applied', remote_type: 'hybrid', location: 'Redmond, WA',
      salary_min: 195000, salary_max: 275000, salary_currency: 'USD',
      employment_type: 'full_time', seniority: 'principal',
      summary: 'Lead Azure platform programs spanning multiple engineering orgs. Drive clarity on scope, schedule, and dependencies across 10+ teams.',
      requirements: '7+ years TPM in cloud or platform. Proven ability to drive alignment in large matrixed orgs.',
      skills: ['Azure', 'cloud platforms', 'matrixed orgs', 'program management'],
      capturedAt: daysAgo(9), extractedAt: daysAgo(9), fit_score: 76, fit_status: 'scored',
    },
    {
      capId: uid('cap', 5), jobId: uid('job', 5), jobNum: 5,
      url: 'https://www.builtinseattle.com/job/senior-tpm/9001122',
      pageTitle: 'Senior Technical Program Manager · Datadog',
      company: 'Datadog', title: 'Senior Technical Program Manager',
      status: 'applied', remote_type: 'remote', location: 'Remote - USA',
      salary_min: 185000, salary_max: 240000, salary_currency: 'USD',
      employment_type: 'full_time', seniority: 'senior',
      summary: 'Manage programs across Datadog\'s observability platform. Own delivery for infrastructure monitoring features used by tens of thousands of customers.',
      requirements: '5+ years TPM. SaaS background preferred. Familiarity with observability or monitoring tools.',
      skills: ['SaaS', 'observability', 'agile', 'program management'],
      capturedAt: daysAgo(7), extractedAt: daysAgo(7), fit_score: 82, fit_status: 'scored',
    },
    {
      capId: uid('cap', 6), jobId: uid('job', 6), jobNum: 6,
      url: 'https://openai.com/careers/technical-program-manager',
      pageTitle: 'Technical Program Manager · OpenAI',
      company: 'OpenAI', title: 'Technical Program Manager',
      status: 'saved', remote_type: 'hybrid', location: 'San Francisco, CA',
      salary_min: 250000, salary_max: 360000, salary_currency: 'USD',
      employment_type: 'full_time', seniority: 'senior',
      summary: 'Drive critical programs across OpenAI\'s research and product orgs. Manage dependencies between frontier model research and consumer/API product teams.',
      requirements: 'BS/MS in CS or engineering. 6+ years program management in fast-paced AI or product org.',
      skills: ['AI products', 'research coordination', 'program management', 'fast-paced environment'],
      capturedAt: daysAgo(5), extractedAt: daysAgo(5), fit_score: 88, fit_status: 'scored',
    },
    {
      capId: uid('cap', 7), jobId: uid('job', 7), jobNum: 7,
      url: 'https://boards.greenhouse.io/netflix/jobs/senior-pm',
      pageTitle: 'Senior Engineering Program Manager · Netflix',
      company: 'Netflix', title: 'Senior Engineering Program Manager',
      status: 'saved', remote_type: 'remote', location: 'Remote - USA',
      salary_min: 260000, salary_max: 350000, salary_currency: 'USD',
      employment_type: 'full_time', seniority: 'senior',
      summary: 'Lead delivery of high-visibility initiatives across Netflix streaming infrastructure. Drive accountability, remove blockers, and communicate program status to leadership.',
      requirements: '7+ years program management in a high-scale engineering environment.',
      skills: ['streaming infrastructure', 'program management', 'leadership communication'],
      capturedAt: daysAgo(4), extractedAt: daysAgo(4), fit_score: null, fit_status: 'none',
    },
    {
      capId: uid('cap', 8), jobId: uid('job', 8), jobNum: 8,
      url: 'https://jobs.ashbyhq.com/coinbase/tpm-senior',
      pageTitle: 'Senior Technical Program Manager · Coinbase',
      company: 'Coinbase', title: 'Senior Technical Program Manager',
      status: 'saved', remote_type: 'remote', location: 'Remote - USA',
      salary_min: 195000, salary_max: 265000, salary_currency: 'USD',
      employment_type: 'full_time', seniority: 'senior',
      summary: 'Own delivery of Coinbase platform programs including wallet, custody, and exchange reliability. Work with crypto infrastructure teams globally.',
      requirements: '5+ years TPM. Fintech or high-regulation environment experience preferred.',
      skills: ['fintech', 'crypto', 'platform', 'program management'],
      capturedAt: daysAgo(3), extractedAt: daysAgo(3), fit_score: null, fit_status: 'none',
    },
    {
      capId: uid('cap', 9), jobId: uid('job', 9), jobNum: 9,
      url: 'https://www.builtinseattle.com/job/tpm-amazon/8883344',
      pageTitle: 'Principal Technical Program Manager · Amazon',
      company: 'Amazon', title: 'Principal Technical Program Manager',
      status: 'saved', remote_type: 'hybrid', location: 'Seattle, WA',
      salary_min: 180000, salary_max: 250000, salary_currency: 'USD',
      employment_type: 'full_time', seniority: 'principal',
      summary: 'Drive technical programs for AWS reliability engineering, managing Tier-1 service health initiatives across multiple S-team goals.',
      requirements: '8+ years engineering or TPM. AWS experience strongly preferred.',
      skills: ['AWS', 'reliability engineering', 'S-team programs', 'technical leadership'],
      capturedAt: daysAgo(2), extractedAt: null, fit_score: null, fit_status: 'none',
      extraction_status: 'pending',
    },
    {
      capId: uid('cap', 10), jobId: uid('job', 10), jobNum: 10,
      url: 'https://www.linkedin.com/jobs/view/4007654321',
      pageTitle: 'Senior Technical Program Manager · Salesforce',
      company: 'Salesforce', title: 'Senior Technical Program Manager',
      status: 'saved', remote_type: 'hybrid', location: 'San Francisco, CA',
      salary_min: 190000, salary_max: 245000, salary_currency: 'USD',
      employment_type: 'full_time', seniority: 'senior',
      summary: 'Manage CRM platform programs across Salesforce Customer 360. Partner with product and engineering to deliver quarterly milestones.',
      requirements: '6+ years TPM. Enterprise SaaS background. Experience with Agile at scale.',
      skills: ['CRM', 'enterprise SaaS', 'agile at scale', 'program management'],
      capturedAt: daysAgo(1), extractedAt: null, fit_score: null, fit_status: 'none',
      extraction_status: 'pending',
    },
    {
      capId: uid('cap', 11), jobId: uid('job', 11), jobNum: 11,
      url: 'https://careers.meta.com/jobs/senior-pm-infra',
      pageTitle: 'Senior Program Manager, Infrastructure · Meta',
      company: 'Meta', title: 'Senior Program Manager, Infrastructure',
      status: 'rejected', remote_type: 'hybrid', location: 'Menlo Park, CA',
      salary_min: 210000, salary_max: 270000, salary_currency: 'USD',
      employment_type: 'full_time', seniority: 'senior',
      summary: 'Drive delivery of Meta infrastructure programs including data center expansion and network reliability.',
      requirements: '7+ years program management. Data center or network infra experience preferred.',
      skills: ['infrastructure', 'data center', 'program management'],
      capturedAt: daysAgo(30), extractedAt: daysAgo(30), fit_score: 71, fit_status: 'scored',
      note: 'Phone screen went well but they went with an internal candidate.',
    },
    {
      capId: uid('cap', 12), jobId: uid('job', 12), jobNum: 12,
      url: 'https://zoom.us/careers/tpm-senior',
      pageTitle: 'Senior Technical Program Manager · Zoom',
      company: 'Zoom', title: 'Senior Technical Program Manager',
      status: 'rejected', remote_type: 'remote', location: 'Remote - USA',
      salary_min: 155000, salary_max: 195000, salary_currency: 'USD',
      employment_type: 'full_time', seniority: 'senior',
      summary: 'Manage product delivery programs across Zoom\'s meetings and collaboration platform.',
      requirements: '5+ years TPM. Video/conferencing industry experience a plus.',
      skills: ['collaboration tools', 'product delivery', 'program management'],
      capturedAt: daysAgo(25), extractedAt: daysAgo(25), fit_score: 58, fit_status: 'scored',
      note: 'Rejected after technical screen. Salary was low end anyway.',
    },
    {
      capId: uid('cap', 13), jobId: uid('job', 13), jobNum: 13,
      url: 'https://www.lyft.com/jobs/tpm',
      pageTitle: 'Technical Program Manager · Lyft',
      company: 'Lyft', title: 'Technical Program Manager',
      status: 'archived', remote_type: 'hybrid', location: 'San Francisco, CA',
      salary_min: 170000, salary_max: 215000, salary_currency: 'USD',
      employment_type: 'full_time', seniority: 'mid',
      summary: 'Manage Lyft marketplace and pricing programs. Coordinate across data science, product, and engineering.',
      requirements: '4+ years TPM. Marketplace or two-sided platform experience preferred.',
      skills: ['marketplace', 'data science', 'program management'],
      capturedAt: daysAgo(45), extractedAt: daysAgo(45), fit_score: 62, fit_status: 'scored',
      note: 'Decided not to pursue — role is too junior and company has had layoffs.',
    },
    // Duplicate — same job as #9 (Amazon), captured again from a different URL
    {
      capId: uid('cap', 14), jobId: uid('job', 14), jobNum: 14,
      url: 'https://www.amazon.jobs/en/jobs/9988776/principal-technical-program-manager',
      pageTitle: 'Principal Technical Program Manager · Amazon Jobs',
      company: 'Amazon', title: 'Principal Technical Program Manager',
      status: 'saved', remote_type: 'hybrid', location: 'Seattle, WA',
      salary_min: 180000, salary_max: 250000, salary_currency: 'USD',
      employment_type: 'full_time', seniority: 'principal',
      summary: 'Drive technical programs for AWS reliability engineering.',
      requirements: '8+ years engineering or TPM.',
      skills: ['AWS', 'reliability engineering'],
      capturedAt: daysAgo(1), extractedAt: daysAgo(1), fit_score: null, fit_status: 'none',
      duplicate_of_job_id: uid('job', 9),
    },
    // Accidentally captured non-job page
    {
      capId: uid('cap', 15), jobId: uid('job', 15), jobNum: 15,
      url: 'https://techcrunch.com/2024/11/the-state-of-ai-hiring',
      pageTitle: 'The State of AI Hiring in 2024 · TechCrunch',
      company: null, title: null,
      status: 'archived', remote_type: null, location: null,
      salary_min: null, salary_max: null, salary_currency: null,
      employment_type: null, seniority: null, summary: null, requirements: null,
      skills: [],
      capturedAt: daysAgo(6), extractedAt: daysAgo(6), fit_score: null, fit_status: 'none',
      extraction_status: 'succeeded',
      note: 'Accidentally captured — not a job posting.',
    },
  ],

  sites: [
    { id: 'site_001', url: 'https://www.linkedin.com/jobs/search/?keywords=technical+program+manager&f_WT=2', origin: 'https://www.linkedin.com', title: 'LinkedIn Jobs — TPM Remote', interval: 7 },
    { id: 'site_002', url: 'https://www.builtinseattle.com/jobs/remote', origin: 'https://www.builtinseattle.com', title: 'Built In Seattle — Remote', interval: 7 },
    { id: 'site_003', url: 'https://levels.fyi/jobs?title=Technical+Program+Manager', origin: 'https://levels.fyi', title: 'Levels.fyi — TPM Jobs', interval: 14 },
  ],
};

export function ensureDemoDb(dbPath = DEMO_DB_PATH) {
  // Bootstrap from bundled seed template when no working copy exists yet.
  if (!existsSync(dbPath) && existsSync(SEED_DB_PATH)) {
    copyFileSync(SEED_DB_PATH, dbPath);
  }
  const db = initDb(dbPath);
  const { n } = db.prepare('SELECT COUNT(*) AS n FROM jobs').get();
  if (n > 0) return;
  seedDemoDb(db);
}

export function reseedDemoDb(dbPath = DEMO_DB_PATH) {
  const db = initDb(dbPath);
  // Wipe existing data and re-seed
  db.exec(`
    DELETE FROM llm_request_attempts;
    DELETE FROM llm_requests;
    DELETE FROM data_quality_reviews;
    DELETE FROM events;
    DELETE FROM job_actions;
    DELETE FROM duplicate_decisions;
    DELETE FROM jobs;
    DELETE FROM captures;
    DELETE FROM sites;
  `);
  seedDemoDb(db);
}

function seedDemoDb(db) {

  // Reset job_number sequence (sqlite_sequence only exists if AUTOINCREMENT is used; safe to skip)
  try { db.exec(`DELETE FROM sqlite_sequence WHERE name='jobs'`); } catch { /* no autoincrement table */ }

  const insertCapture = db.prepare(`
    INSERT INTO captures (id, url, canonical_url, page_title, visible_text, cleaned_description,
      raw_hash, cleaned_hash, captured_at, created_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  `);

  const insertJob = db.prepare(`
    INSERT INTO jobs (id, job_number, capture_id, company, title, location, remote_type,
      salary_min, salary_max, salary_currency, employment_type, seniority, status,
      extraction_status, extracted_json, extracted_at, fit_score, fit_status, fit_score_json,
      duplicate_of_job_id, created_at, updated_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  `);

  const insertEvent = db.prepare(`
    INSERT INTO events (id, job_id, event_type, note, occurred_at, created_at)
    VALUES (?, ?, ?, ?, ?, ?)
  `);

  const insertSite = db.prepare(`
    INSERT INTO sites (id, url, origin, page_title, state, interval_days, note, created_at, updated_at, next_review_at)
    VALUES (?, ?, ?, ?, 'active', ?, '', ?, ?, ?)
  `);

  db.exec('BEGIN IMMEDIATE');
  try {
  for (const j of SEED.jobs) {
      const visibleText = `${j.title || ''}\n${j.company || ''}\n${j.location || ''}\n${j.summary || ''}\n${j.requirements || ''}`;
      const rawHash = `demo_hash_${j.capId}`;
      const cleanedHash = j.duplicate_of_job_id ? `demo_dhash_dup` : `demo_chash_${j.capId}`;

      insertCapture.run(
        j.capId, j.url, j.url, j.pageTitle,
        visibleText, visibleText,
        rawHash, cleanedHash,
        j.capturedAt, j.capturedAt,
      );

      const extractedJson = (j.extraction_status !== 'pending' && j.title) ? JSON.stringify({
        company: j.company,
        title: j.title,
        location: j.location,
        remote_type: j.remote_type,
        salary_min: j.salary_min,
        salary_max: j.salary_max,
        salary_currency: j.salary_currency || 'USD',
        salary_note: j.salary_min ? `$${Math.round(j.salary_min / 1000)}K–$${Math.round(j.salary_max / 1000)}K` : null,
        employment_type: j.employment_type || 'full_time',
        seniority: j.seniority,
        summary: j.summary,
        requirements: j.requirements ? [j.requirements] : [],
        nice_to_haves: [],
        benefits: [],
        skills: j.skills || [],
        application_url: j.url,
        confidence: 0.92,
      }) : null;

      const fitScoreJson = j.fit_score ? JSON.stringify({
        score: j.fit_score,
        summary: `Strong match — ${j.fit_score >= 85 ? 'excellent' : j.fit_score >= 75 ? 'good' : 'moderate'} alignment with your background.`,
        strengths: ['Technical program management experience', 'Cross-functional leadership'],
        gaps: j.fit_score < 80 ? ['Could strengthen domain-specific experience'] : [],
      }) : null;

      insertJob.run(
        j.jobId, j.jobNum, j.capId,
        j.company, j.title, j.location, j.remote_type,
        j.salary_min, j.salary_max, j.salary_currency || 'USD',
        j.employment_type, j.seniority,
        j.status, j.extraction_status || 'succeeded',
        extractedJson, j.extractedAt,
        j.fit_score, j.fit_status || 'none', fitScoreJson,
        j.duplicate_of_job_id || null,
        j.capturedAt, j.capturedAt,
      );

      if (j.note) {
        insertEvent.run(
          `evt_${j.jobId}`, j.jobId, 'note', j.note, j.capturedAt, j.capturedAt,
        );
      }

      // Add a status change event for non-saved jobs
      if (j.status !== 'saved') {
        const statusAt = new Date(new Date(j.capturedAt).getTime() + 2 * 24 * 3600 * 1000).toISOString();
        insertEvent.run(
          `evt_status_${j.jobId}`, j.jobId, 'status_change', j.status, statusAt, statusAt,
        );
      }
    }

    const reviewedAt = daysAgo(3);
    const nextReview = new Date(Date.now() + 7 * 86400000).toISOString();
    for (const s of SEED.sites) {
      insertSite.run(s.id, s.url, s.origin, s.title, s.interval, reviewedAt, reviewedAt, nextReview);
    }
  db.exec('COMMIT');
  } catch (e) {
    try { db.exec('ROLLBACK'); } catch { /* ignore */ }
    throw e;
  }
}
