#!/usr/bin/env node

import assert from 'node:assert/strict';
import { defaultDbPath, getSettings, initDb } from '../../server/db.js';
import { computeOverallFitScore, LMStudioExtractor, FitScorer } from '../../server/extract.js';

const DEFAULT_TIMEOUT_SECONDS = 300;

const extractionFixtures = [
  {
    name: 'remote salary bands and application URL',
    pending: {
      url: 'https://jobs.example.com/platform-tpm',
      canonical_url: 'https://jobs.example.com/platform-tpm',
      page_title: 'Principal Technical Program Manager, AI Platform - ExampleCloud Careers',
      description: `
ExampleCloud
Principal Technical Program Manager, AI Platform
Remote - United States
Full-time
Senior level

This role is fully remote within the United States. You will lead cross-functional delivery for
LLM inference, API reliability, eval pipelines, and developer productivity programs.

Required qualifications:
- 8+ years of technical program management experience.
- Experience leading cloud infrastructure, distributed systems, or AI platform programs.
- Strong executive communication and cross-functional planning.

Preferred qualifications:
- Experience with LLM platforms, model evaluation, or developer tooling.
- Experience defining reliability metrics and operational reviews.

Salary range: $185,000 - $245,000 USD base salary. San Francisco and New York range:
$210,000 - $285,000 USD.

Benefits include equity, medical/dental/vision, 401k match, flexible PTO, and a learning budget.
Apply at https://jobs.example.com/apply/platform-tpm
      `.trim(),
    },
    expect: {
      company: 'ExampleCloud',
      titleIncludes: 'Principal Technical Program Manager',
      locationIncludes: ['Remote', 'United States'],
      remote_type: 'remote',
      salary_min: 185000,
      salary_max: 285000,
      salary_currency: 'USD',
      employment_type: 'full_time',
      seniorityIncludes: ['Senior'],
      application_url: 'https://jobs.example.com/apply/platform-tpm',
      skillsIncludeAny: ['LLM', 'AI platform', 'developer productivity', 'distributed systems', 'reliability'],
      requirementsIncludeAny: ['8+', 'technical program management', 'cloud infrastructure', 'distributed systems', 'AI platform'],
      niceToHavesIncludeAny: ['LLM', 'model evaluation', 'developer tooling', 'reliability metrics'],
      benefitsIncludeAny: ['equity', 'medical', '401k', 'PTO', 'learning'],
    },
  },
  {
    name: 'hybrid location and hourly conversion',
    pending: {
      url: 'https://careers.example.org/jobs/123',
      canonical_url: 'https://careers.example.org/jobs/123',
      page_title: 'Technical Program Manager, Payments',
      description: `
PayWorks
Technical Program Manager, Payments
Seattle, WA
Work site: 3 days/week in-office
Contract

The Payments team needs a Technical Program Manager to coordinate partner integrations,
launch readiness, risk tracking, and incident follow-up for payment processing systems.

Must have:
- 5+ years technical program management experience.
- Payment systems or fintech experience.
- Ability to manage vendor dependencies and launch plans.

Nice to have:
- SQL familiarity.
- Experience with fraud or risk systems.

Pay: $85/hr - $105/hr on W2 contract.
      `.trim(),
    },
    expect: {
      company: 'PayWorks',
      titleIncludes: 'Technical Program Manager',
      locationIncludes: ['Seattle', 'WA'],
      remote_type: 'hybrid',
      salary_min: 176800,
      salary_max: 218400,
      salary_currency: 'USD',
      employment_type: 'contract',
      skillsIncludeAny: ['payments', 'fintech', 'vendor', 'launch', 'risk', 'SQL'],
      requirementsIncludeAny: ['5+', 'payment', 'fintech', 'vendor', 'launch'],
      niceToHavesIncludeAny: ['SQL', 'fraud', 'risk'],
    },
  },
  {
    name: 'Microsoft general US pay band with higher metro band',
    pending: {
      url: 'https://apply.careers.microsoft.com/careers?pid=fixture-ms-product',
      canonical_url: 'https://apply.careers.microsoft.com/careers?pid=fixture-ms-product',
      page_title: 'Senior Product Manager | Microsoft Careers',
      description: `
Microsoft
Senior Product Manager
United States, Multiple Locations, Multiple Locations
Work site 0 days / week in-office - remote
Full-Time

Product Management IC4 - The typical base pay range for this role across the U.S. is USD $119,800 - $234,700 per year.
There is a different range applicable to specific work locations, within the San Francisco Bay area and New York City
metropolitan area, and the base pay range for this role in those locations is USD $158,400 - $258,000 per year.

Responsibilities:
- Drive product strategy and execution across Microsoft 365 experiences.
- Partner with engineering, design, and research teams.

Required qualifications:
- 4+ years product or technical program management experience.
- Experience managing cross-functional product delivery.
      `.trim(),
    },
    expect: {
      company: 'Microsoft',
      titleIncludes: 'Senior Product Manager',
      locationIncludes: ['United States'],
      remote_type: 'remote',
      salary_min: 119800,
      salary_max: 234700,
      salary_currency: 'USD',
      employment_type: 'full_time',
      skillsIncludeAny: ['product strategy', 'cross-functional', 'product delivery'],
      requirementsIncludeAny: ['4+', 'product', 'technical program management', 'cross-functional'],
      niceToHavesIncludeAny: ['product', 'engineering', 'design'],
      salaryNoteIncludes: ['$119,800', '$234,700', '$158,400', '$258,000'],
    },
  },
  {
    name: 'Instacart state-specific pay bands prefer WA',
    pending: {
      url: 'https://careers.instacart.com/jobs/fixture-sr-tpm',
      canonical_url: 'https://careers.instacart.com/jobs/fixture-sr-tpm',
      page_title: 'Senior Technical Program Manager | Instacart Careers',
      description: `
Instacart
Senior Technical Program Manager
Remote - United States

For US based candidates, the base pay ranges for a successful candidate are listed below.

CA, NY, CT, NJ
$214,000-$216,500 USD

WA
$205,000-$216,500 USD

OR, DE, ME, MA, MD, NH, RI, VT, DC, PA, VA, CO, TX, IL, HI
$196,000-$207,000 USD

All other states
$178,000-$188,000 USD

Required qualifications:
- 7+ years technical program management experience.
- Experience leading marketplace, logistics, or consumer platform programs.
      `.trim(),
    },
    expect: {
      company: 'Instacart',
      titleIncludes: 'Senior Technical Program Manager',
      locationIncludes: ['Remote', 'United States'],
      remote_type: 'remote',
      salary_min: 205000,
      salary_max: 216500,
      salary_currency: 'USD',
      employment_type: 'unknown',
      skillsIncludeAny: ['marketplace', 'logistics', 'platform', 'technical program management'],
      requirementsIncludeAny: ['7+', 'technical program management', 'marketplace', 'logistics'],
      niceToHavesIncludeAny: ['marketplace', 'logistics', 'consumer'],
      salaryNoteIncludes: ['WA', '$205,000', '$216,500', '$178,000', '$188,000'],
    },
  },
  {
    name: 'hourly range with currency after number',
    pending: {
      url: 'https://www.g2i.co/jobs/fixture-tpm',
      canonical_url: 'https://www.g2i.co/jobs/fixture-tpm',
      page_title: 'Technical Program Manager (TPM) | G2i',
      description: `
G2i
Technical Program Manager (TPM)
Remote
Contract

This contract role coordinates AI coding assistant delivery programs, customer onboarding,
and engineering partner milestones.

Compensation: 50 - 150USD/Hr, based on experience and location.

Required qualifications:
- Technical program management experience.
- Experience coordinating software engineering delivery.
      `.trim(),
    },
    expect: {
      company: 'G2i',
      titleIncludes: 'Technical Program Manager',
      locationIncludes: ['Remote'],
      remote_type: 'remote',
      salary_min: 104000,
      salary_max: 312000,
      salary_hourly_min: 50,
      salary_hourly_max: 150,
      salary_currency: 'USD',
      employment_type: 'contract',
      skillsIncludeAny: ['AI coding', 'customer onboarding', 'engineering delivery'],
      requirementsIncludeAny: ['technical program management', 'software engineering'],
      niceToHavesIncludeAny: ['AI', 'customer onboarding', 'engineering'],
      salaryNoteIncludes: ['50', '150', 'USD/Hr'],
    },
  },
  {
    name: 'multi-currency salary bands keep USD band',
    pending: {
      url: 'https://www.mercury.com/jobs/fixture-api-banking',
      canonical_url: 'https://www.mercury.com/jobs/fixture-api-banking',
      page_title: 'Senior Product Manager - API & Agentic Banking | Mercury',
      description: `
Mercury
Senior Product Manager - API & Agentic Banking
Remote - United States or Canada
Full-time

The target new hire base salary ranges for this role are the following:
US employees (any location): $200,700 - $250,900
Canadian employees (any location): CAD 189,700 - 237,100

You will lead API banking product strategy, agentic workflows, and developer platform launches.

Required qualifications:
- Product management experience for APIs or developer platforms.
- Experience with fintech, banking, or payments products.
      `.trim(),
    },
    expect: {
      company: 'Mercury',
      titleIncludes: 'Senior Product Manager',
      locationIncludes: ['Remote', 'United States'],
      remote_type: 'remote',
      salary_min: 200700,
      salary_max: 250900,
      salary_currency: 'USD',
      employment_type: 'full_time',
      skillsIncludeAny: ['API', 'banking', 'developer platform', 'fintech', 'payments'],
      requirementsIncludeAny: ['product management', 'API', 'developer platform', 'fintech', 'banking'],
      niceToHavesIncludeAny: ['agentic', 'developer platform', 'payments'],
      salaryNoteIncludes: ['$200,700', '$250,900', 'CAD 189,700'],
    },
  },
];

const fitFixture = {
  name: 'AI platform TPM ranking',
  context: {
    company: 'ExampleCloud',
    title: 'Principal Technical Program Manager, AI Platform',
    extracted: {
      company: 'ExampleCloud',
      title: 'Principal Technical Program Manager, AI Platform',
      seniority: 'Principal / Senior',
      summary: 'Lead cross-functional delivery for LLM inference, API reliability, eval pipelines, and developer productivity programs.',
      requirements: [
        '8+ years of technical program management experience',
        'Experience leading cloud infrastructure, distributed systems, or AI platform programs',
        'Strong executive communication and cross-functional planning',
      ],
      nice_to_haves: [
        'Experience with LLM platforms, model evaluation, or developer tooling',
        'Experience defining reliability metrics and operational reviews',
      ],
      skills: ['technical program management', 'AI platform', 'LLM inference', 'developer productivity', 'API reliability', 'model evaluation'],
    },
  },
  strongResume: `
Principal Technical Program Manager with 11 years leading AI infrastructure, LLM platform,
developer productivity, and cloud reliability programs. Led cross-functional roadmap and execution
for inference APIs, model evaluation pipelines, incident review processes, executive operating
reviews, and multi-team launch planning at Meta and Microsoft. Deep experience with distributed
systems, API governance, platform reliability metrics, and engineering productivity.
  `.trim(),
  weakResume: `
Marketing operations manager with 4 years of experience planning webinars, managing campaign
calendars, and coordinating vendor invoices. Some exposure to project tracking tools and stakeholder
communications. No hands-on experience with cloud infrastructure, AI platforms, developer tooling,
distributed systems, or technical program management.
  `.trim(),
};

function parseArgs(argv) {
  const args = {
    baseUrl: null,
    model: null,
    timeout: null,
    json: false,
    dbPath: null,
    preferredLocations: 'Seattle, WA, Remote, United States',
  };
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (arg === '--json') args.json = true;
    else if (arg === '--base-url') args.baseUrl = argv[++i];
    else if (arg === '--model') args.model = argv[++i];
    else if (arg === '--timeout') args.timeout = Number(argv[++i]);
    else if (arg === '--db') args.dbPath = argv[++i];
    else if (arg === '--preferred-locations') args.preferredLocations = argv[++i];
    else if (arg === '--help' || arg === '-h') {
      printHelp();
      process.exit(0);
    } else {
      throw new Error(`Unknown argument: ${arg}`);
    }
  }
  return args;
}

function printHelp() {
  console.log(`Usage: npm run eval:llm -- [options]

Runs live LM Studio model evaluations for extraction and fit scoring.

Options:
  --model <name>                 Model identifier to test. Defaults to app settings.
  --base-url <url>               LM Studio base URL. Defaults to app settings.
  --timeout <seconds>            Request timeout. Defaults to app settings or ${DEFAULT_TIMEOUT_SECONDS}.
  --preferred-locations <list>   Location preference context for extraction fixtures.
  --db <path>                    Settings DB to read defaults from.
  --json                         Print machine-readable JSON only.
`);
}

function readRuntimeSettings(dbPath) {
  try {
    const db = initDb(dbPath || defaultDbPath());
    return getSettings(db);
  } catch {
    return {};
  }
}

function normalize(value) {
  return String(value || '').toLowerCase();
}

function arrayText(values) {
  return Array.isArray(values) ? values.join('\n').toLowerCase() : '';
}

function includesAll(value, needles) {
  const haystack = normalize(value);
  return needles.every(needle => haystack.includes(normalize(needle)));
}

function includesAny(values, needles) {
  const haystack = arrayText(values);
  return needles.some(needle => haystack.includes(normalize(needle)));
}

function includesText(value, needles) {
  const haystack = normalize(value);
  return needles.every(needle => haystack.includes(normalize(needle)));
}

function scoreCheck(condition, label, actual, expected, weight = 1) {
  return {
    label,
    passed: Boolean(condition),
    actual,
    expected,
    weight,
  };
}

function scoreExtraction(extracted, expected) {
  const checks = [
    scoreCheck(normalize(extracted.company).includes(normalize(expected.company)), 'company', extracted.company, expected.company, 2),
    scoreCheck(normalize(extracted.title).includes(normalize(expected.titleIncludes)), 'title', extracted.title, expected.titleIncludes, 2),
    scoreCheck(includesAll(extracted.location, expected.locationIncludes), 'location', extracted.location, expected.locationIncludes.join(' + '), 2),
    scoreCheck(extracted.remote_type === expected.remote_type, 'remote_type', extracted.remote_type, expected.remote_type, 2),
    scoreCheck(extracted.salary_min === expected.salary_min, 'salary_min', extracted.salary_min, expected.salary_min, 2),
    scoreCheck(extracted.salary_max === expected.salary_max, 'salary_max', extracted.salary_max, expected.salary_max, 2),
    scoreCheck(expected.salary_hourly_min == null || extracted.salary_hourly_min === expected.salary_hourly_min, 'salary_hourly_min', extracted.salary_hourly_min, expected.salary_hourly_min),
    scoreCheck(expected.salary_hourly_max == null || extracted.salary_hourly_max === expected.salary_hourly_max, 'salary_hourly_max', extracted.salary_hourly_max, expected.salary_hourly_max),
    scoreCheck(normalize(extracted.salary_currency) === normalize(expected.salary_currency), 'salary_currency', extracted.salary_currency, expected.salary_currency),
    scoreCheck(!expected.salaryNoteIncludes || includesText(extracted.salary_note, expected.salaryNoteIncludes), 'salary_note', extracted.salary_note, expected.salaryNoteIncludes?.join(' + ') || '(not asserted)', 2),
    scoreCheck(extracted.employment_type === expected.employment_type, 'employment_type', extracted.employment_type, expected.employment_type),
    scoreCheck(!expected.seniorityIncludes || expected.seniorityIncludes.some(v => normalize(extracted.seniority).includes(normalize(v))), 'seniority', extracted.seniority, expected.seniorityIncludes?.join(' or ') || '(not asserted)'),
    scoreCheck(!expected.application_url || extracted.application_url === expected.application_url, 'application_url', extracted.application_url, expected.application_url),
    scoreCheck(includesAny(extracted.skills, expected.skillsIncludeAny), 'skills', extracted.skills, expected.skillsIncludeAny.join(' or ')),
    scoreCheck(includesAny(extracted.requirements, expected.requirementsIncludeAny), 'requirements', extracted.requirements, expected.requirementsIncludeAny.join(' or '), 2),
    scoreCheck(includesAny(extracted.nice_to_haves, expected.niceToHavesIncludeAny), 'nice_to_haves', extracted.nice_to_haves, expected.niceToHavesIncludeAny.join(' or ')),
    scoreCheck(!expected.benefitsIncludeAny || includesAny(extracted.benefits, expected.benefitsIncludeAny), 'benefits', extracted.benefits, expected.benefitsIncludeAny?.join(' or ') || '(not asserted)'),
  ];
  const possible = checks.reduce((sum, check) => sum + check.weight, 0);
  const earned = checks.reduce((sum, check) => sum + (check.passed ? check.weight : 0), 0);
  return { score: Math.round((earned / possible) * 100), checks };
}

function hasDimensionScores(fit) {
  if (!Array.isArray(fit.dimensions) || fit.dimensions.length !== 5) return false;
  return fit.dimensions.every(d => typeof d.name === 'string' && Number.isInteger(d.score) && d.score >= 0 && d.score <= 100);
}

function scoreFit(strongFit, weakFit) {
  const strongOverall = computeOverallFitScore(strongFit.dimensions);
  const weakOverall = computeOverallFitScore(weakFit.dimensions);
  const checks = [
    scoreCheck(hasDimensionScores(strongFit), 'strong fit has complete dimensions', strongFit.dimensions, '5 dimension scores', 2),
    scoreCheck(hasDimensionScores(weakFit), 'weak fit has complete dimensions', weakFit.dimensions, '5 dimension scores', 2),
    scoreCheck(strongFit.overall_score === strongOverall, 'strong overall uses weighted dimensions', strongFit.overall_score, strongOverall),
    scoreCheck(weakFit.overall_score === weakOverall, 'weak overall uses weighted dimensions', weakFit.overall_score, weakOverall),
    scoreCheck(strongFit.overall_score >= 85, 'strong resume scores high', strongFit.overall_score, '>= 85', 2),
    scoreCheck(weakFit.overall_score <= 55, 'weak resume scores low', weakFit.overall_score, '<= 55', 2),
    scoreCheck(strongFit.overall_score - weakFit.overall_score >= 30, 'strong resume outranks weak resume', `${strongFit.overall_score} vs ${weakFit.overall_score}`, 'gap >= 30', 2),
    scoreCheck((strongFit.requirements_met || []).length >= 2, 'strong fit names met requirements', strongFit.requirements_met, 'at least 2'),
    scoreCheck((weakFit.requirements_not_met || []).length >= 2, 'weak fit names missing requirements', weakFit.requirements_not_met, 'at least 2', 2),
  ];
  const possible = checks.reduce((sum, check) => sum + check.weight, 0);
  const earned = checks.reduce((sum, check) => sum + (check.passed ? check.weight : 0), 0);
  return { score: Math.round((earned / possible) * 100), checks };
}

async function evaluateModel({ baseUrl, model, timeout, preferredLocations }) {
  const extractor = new LMStudioExtractor({
    baseUrl,
    model,
    timeout,
    preferredLocations,
    allowRemote: true,
    allowHybrid: true,
    allowOnsite: true,
  });
  const scorer = new FitScorer({ baseUrl, model, timeout });
  const extractionResults = [];

  for (const fixture of extractionFixtures) {
    const started = Date.now();
    try {
      const { extracted, modelName, responseFormatType } = await extractor.extract(fixture.pending);
      const scored = scoreExtraction(extracted, fixture.expect);
      extractionResults.push({
        name: fixture.name,
        ok: scored.score >= 85,
        score: scored.score,
        elapsed_ms: Date.now() - started,
        model_returned: modelName,
        response_format: responseFormatType,
        checks: scored.checks,
        extracted,
      });
    } catch (error) {
      extractionResults.push({
        name: fixture.name,
        ok: false,
        score: 0,
        elapsed_ms: Date.now() - started,
        error: String(error),
      });
    }
  }

  const fitStarted = Date.now();
  let fitResult;
  try {
    const strong = await scorer.score(fitFixture.context, fitFixture.strongResume);
    const weak = await scorer.score(fitFixture.context, fitFixture.weakResume);
    const scored = scoreFit(strong.fit, weak.fit);
    fitResult = {
      name: fitFixture.name,
      ok: scored.score >= 85,
      score: scored.score,
      elapsed_ms: Date.now() - fitStarted,
      model_returned: strong.modelName || weak.modelName,
      response_format: strong.responseFormatType || weak.responseFormatType,
      checks: scored.checks,
      strong_fit: strong.fit,
      weak_fit: weak.fit,
    };
  } catch (error) {
    fitResult = {
      name: fitFixture.name,
      ok: false,
      score: 0,
      elapsed_ms: Date.now() - fitStarted,
      error: String(error),
    };
  }

  const allScores = [...extractionResults.map(r => r.score), fitResult.score];
  const overall = Math.round(allScores.reduce((sum, score) => sum + score, 0) / allScores.length);
  return {
    model,
    base_url: baseUrl,
    timeout_seconds: timeout,
    ok: overall >= 85 && extractionResults.every(r => r.ok) && fitResult.ok,
    overall_score: overall,
    extraction: extractionResults,
    fit: fitResult,
  };
}

function printResult(result) {
  const status = result.ok ? 'PASS' : 'FAIL';
  console.log(`${status} ${result.model} overall=${result.overall_score}/100`);
  console.log(`Base URL: ${result.base_url}`);
  console.log('');

  for (const extraction of result.extraction) {
    console.log(`${extraction.ok ? 'PASS' : 'FAIL'} extraction: ${extraction.name} (${extraction.score}/100, ${extraction.elapsed_ms}ms)`);
    printFailedChecks(extraction.checks);
    if (extraction.error) console.log(`  error: ${extraction.error}`);
  }

  console.log(`${result.fit.ok ? 'PASS' : 'FAIL'} fit ranking: ${result.fit.name} (${result.fit.score}/100, ${result.fit.elapsed_ms}ms)`);
  printFailedChecks(result.fit.checks);
  if (result.fit.error) console.log(`  error: ${result.fit.error}`);
  if (result.fit.strong_fit && result.fit.weak_fit) {
    console.log(`  strong=${result.fit.strong_fit.overall_score}, weak=${result.fit.weak_fit.overall_score}`);
  }
}

function printFailedChecks(checks = []) {
  const failed = checks.filter(check => !check.passed);
  for (const check of failed) {
    console.log(`  - ${check.label}: got ${JSON.stringify(check.actual)}; expected ${JSON.stringify(check.expected)}`);
  }
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const settings = readRuntimeSettings(args.dbPath);
  const baseUrl = (args.baseUrl || settings.llm_base_url || 'http://127.0.0.1:1234').replace(/\/$/, '');
  const model = args.model || settings.llm_model;
  const timeout = args.timeout || Number(settings.llm_timeout || DEFAULT_TIMEOUT_SECONDS);

  assert.ok(model, 'No model configured. Pass --model or set one in Settings.');

  const result = await evaluateModel({
    baseUrl,
    model,
    timeout,
    preferredLocations: args.preferredLocations,
  });

  if (args.json) {
    console.log(JSON.stringify(result, null, 2));
  } else {
    printResult(result);
  }

  process.exitCode = result.ok ? 0 : 1;
}

main().catch(error => {
  console.error(String(error?.stack || error));
  process.exit(1);
});
