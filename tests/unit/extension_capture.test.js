import { readFileSync } from 'fs';
import { resolve } from 'path';
import { runInThisContext } from 'vm';
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';

function loadCaptureScript() {
  delete globalThis.jobhuntCapture;
  const script = readFileSync(resolve('extension/capture.js'), 'utf8');
  runInThisContext(script, { filename: 'extension/capture.js' });
  return globalThis.jobhuntCapture;
}

function fakeElement({ text = '', ariaLabel = '', closestResult = null }) {
  return {
    textContent: text,
    className: '',
    id: '',
    clicked: 0,
    getAttribute(name) {
      return name === 'aria-label' ? ariaLabel : null;
    },
    closest() {
      return closestResult;
    },
    click() {
      this.clicked += 1;
    },
  };
}

// ---------------------------------------------------------------------------
// Fixture helpers
// ---------------------------------------------------------------------------

/**
 * Build a minimal fake doc/win pair sufficient for capturePage().
 * Only supply what your fixture needs; everything else is a no-op.
 */
function makeFixture({
  url = 'https://example.com/jobs/1',
  canonicalUrl = null,
  pageTitle = 'Test job',
  domText = '',               // what body.innerText returns
  ldJson = null,              // raw JSON-LD object (or null)
  nextData = null,            // window.__NEXT_DATA__
  nextF = null,               // window.__next_f array
  expandButtons = [],         // fakeElement[] with aria-expanded=false
  showMoreButtons = [],       // fakeElement[] matching "button, [role='button'], a"
} = {}) {
  const doc = {
    title: pageTitle,
    body: { innerText: domText },
    querySelector(selector) {
      if (selector === 'link[rel="canonical"]') {
        return canonicalUrl ? { href: canonicalUrl } : null;
      }
      return null;
    },
    querySelectorAll(selector) {
      if (selector === '[aria-expanded="false"]') return expandButtons;
      if (selector === "button, [role='button'], a") return showMoreButtons;
      if (selector === 'script[type="application/ld+json"]') {
        return ldJson ? [{ textContent: JSON.stringify(ldJson) }] : [];
      }
      return [];
    },
    cloneNode() { return this; },
  };
  const win = {
    location: { href: url },
    getSelection: () => ({ toString: () => '' }),
    ...(nextData != null ? { __NEXT_DATA__: nextData } : {}),
    ...(nextF != null ? { __next_f: nextF } : {}),
  };
  return { doc, win };
}

async function runCapture(fixture) {
  const previousDocument = globalThis.document;
  globalThis.document = fixture.doc;
  try {
    const capture = loadCaptureScript();
    return await capture.capturePage(fixture.win, fixture.doc);
  } finally {
    globalThis.document = previousDocument;
    delete globalThis.jobhuntCapture;
  }
}

// ---------------------------------------------------------------------------
// Original tests (behaviour / unit)
// ---------------------------------------------------------------------------

describe('extension capture expansion', () => {
  it('clicks job-description expansion controls before collecting text', async () => {
    const ariaExpanded = fakeElement({ text: 'Show more' });
    const showMoreButton = fakeElement({ text: 'Read more' });
    const layoutButton = fakeElement({ text: 'Show more', closestResult: { tagName: 'NAV' } });
    const unrelatedButton = fakeElement({ text: 'Apply now' });
    const fixture = makeFixture({
      domText: 'Visible job text after expansion',
      canonicalUrl: 'https://example.com/jobs/1',
      expandButtons: [ariaExpanded, layoutButton, unrelatedButton],
      showMoreButtons: [showMoreButton, layoutButton, unrelatedButton],
    });

    const payload = await runCapture(fixture);

    assert.equal(ariaExpanded.clicked, 1);
    assert.equal(showMoreButton.clicked, 1);
    assert.equal(layoutButton.clicked, 0);
    assert.equal(unrelatedButton.clicked, 0);
    assert.equal(payload.visible_text, 'Visible job text after expansion');
    assert.equal(payload.canonical_url, 'https://example.com/jobs/1');
  });

  it('reports preflight signals from captured text', () => {
    const capture = loadCaptureScript();
    const preflight = capture.capturePreflight({
      page_title: 'Principal Technical Program Manager',
      selected_text: 'Selected detail text',
      visible_text: 'Principal Technical Program Manager\nSeattle, WA\nRemote\nPay range $180,000 - $230,000',
      structured_data: [{ '@type': 'JobPosting' }],
    });

    assert.equal(preflight.title, true);
    assert.equal(preflight.location, true);
    assert.equal(preflight.salary, true);
    assert.equal(preflight.remote, true);
    assert.equal(preflight.structuredData, 1);
    assert.equal(preflight.selectedText, true);
    assert.equal(preflight.visibleChars > 0, true);
    delete globalThis.jobhuntCapture;
  });

  it('reports missing preflight signals for weak captures', () => {
    const capture = loadCaptureScript();
    const preflight = capture.capturePreflight({
      page_title: '',
      selected_text: '',
      visible_text: 'Apply now Login Careers',
      structured_data: [],
    });

    assert.equal(preflight.title, false);
    assert.equal(preflight.location, false);
    assert.equal(preflight.salary, false);
    assert.equal(preflight.remote, false);
    assert.equal(preflight.structuredData, 0);
    assert.equal(preflight.selectedText, false);
    delete globalThis.jobhuntCapture;
  });
});

// ---------------------------------------------------------------------------
// Job board platform fixtures
//
// Each test simulates the key structural characteristics of one platform.
// Add a new describe block when a new problematic page is found.
// Minimum assertions per fixture:
//   - visible_text.length >= MIN_CHARS (enough text for extraction)
//   - preflight signals match what the page actually contains
// ---------------------------------------------------------------------------

const MIN_CHARS = 500; // minimum meaningful JD text

describe('job board fixtures — Greenhouse', () => {
  // boards.greenhouse.io — server-rendered HTML, full text in DOM.
  // URL pattern: boards.greenhouse.io/<company>/jobs/<id>
  it('extracts full JD from server-rendered Greenhouse DOM', async () => {
    const domText = [
      'Senior Software Engineer',
      'San Francisco, CA · Remote',
      'Engineering · Full-time',
      'About the role',
      'We are looking for a Senior Software Engineer to join our team. You will design, build, and maintain high-quality software systems serving millions of users.',
      'Requirements',
      '5+ years of software engineering experience',
      'Proficiency in Python, Go, or similar languages',
      'Experience with distributed systems and cloud infrastructure',
      'Strong problem-solving and communication skills',
      'Nice to have',
      'Experience with Kubernetes and Terraform',
      'Open source contributions',
      'Compensation',
      'Base salary: $160,000 – $220,000',
      'Equity, health, dental, vision, 401k',
      'Apply for this job',
    ].join('\n');

    const ldJson = {
      '@type': 'JobPosting',
      title: 'Senior Software Engineer',
      hiringOrganization: { name: 'Acme Corp' },
      jobLocation: { address: { addressLocality: 'San Francisco', addressRegion: 'CA' } },
      baseSalary: { value: { minValue: 160000, maxValue: 220000, unitText: 'YEAR' } },
    };

    const fixture = makeFixture({
      url: 'https://boards.greenhouse.io/acme/jobs/123456',
      pageTitle: 'Senior Software Engineer at Acme Corp',
      domText,
      ldJson,
    });

    const payload = await runCapture(fixture);
    assert.ok(payload.visible_text.length >= MIN_CHARS, `too short: ${payload.visible_text.length}`);
    assert.ok(payload.visible_text.includes('Senior Software Engineer'), 'title present');
    assert.ok(payload.visible_text.includes('$160,000'), 'salary present');
    assert.ok(payload.visible_text.includes('distributed systems'), 'requirements present');
    assert.equal(payload.preflight.salary, true);
    assert.equal(payload.preflight.location, true);
  });
});

describe('job board fixtures — Lever', () => {
  // jobs.lever.co — server-rendered, clean HTML structure.
  // URL pattern: jobs.lever.co/<company>/<uuid>
  it('extracts JD from server-rendered Lever page', async () => {
    const domText = [
      'Principal Product Manager',
      'New York, NY / Remote',
      'Product · Full-Time',
      'About Acme',
      'Acme is transforming how enterprises manage their data infrastructure. We partner with Fortune 500 companies to deliver real-time analytics at scale.',
      'The Role',
      'As Principal PM you will own the roadmap for our core platform, working closely with engineering and design to ship features that delight customers.',
      'Responsibilities',
      'Define and prioritize the product roadmap in collaboration with engineering, design, and GTM teams',
      'Conduct customer research and translate insights into product requirements',
      'Partner with sales on competitive positioning and pricing strategy',
      'What We\'re Looking For',
      '7+ years of product management experience, preferably in B2B SaaS',
      'Track record of shipping 0-to-1 products at scale',
      'Strong analytical skills; comfort with SQL and product analytics tools',
      'Compensation and Benefits',
      'Salary range: $180,000 - $230,000 plus equity',
      'Unlimited PTO, top-tier health insurance, home office stipend',
      'Apply',
    ].join('\n');

    const fixture = makeFixture({
      url: 'https://jobs.lever.co/acme/abc123-def456',
      pageTitle: 'Principal Product Manager - Acme',
      domText,
    });

    const payload = await runCapture(fixture);
    assert.ok(payload.visible_text.length >= MIN_CHARS, `too short: ${payload.visible_text.length}`);
    assert.ok(payload.visible_text.includes('Principal Product Manager'), 'title present');
    assert.ok(payload.visible_text.includes('$180,000'), 'salary present');
    assert.ok(payload.visible_text.includes('roadmap'), 'responsibilities present');
    assert.equal(payload.preflight.salary, true);
    assert.equal(payload.preflight.remote, true);
  });
});

describe('job board fixtures — Workday', () => {
  // company.wd5.myworkday.com — React-rendered; content is in the DOM but
  // the description section often starts collapsed (aria-expanded=false).
  // URL pattern: <company>.wd5.myworkday.com/recruiting/job/<id>/...
  it('expands collapsed description and extracts text', async () => {
    const expandBtn = fakeElement({ text: 'View More' });
    const domText = [
      'Staff Technical Program Manager',
      'Remote, United States',
      'R-100042 · Posted 2 days ago',
      'Job Description',
      'We are seeking a Staff TPM to lead cross-functional initiatives across our AI infrastructure division.',
      'You will drive complex, multi-team programs from scoping through delivery.',
      'Minimum Qualifications',
      '8+ years of technical program management experience',
      'Experience managing programs spanning engineering, product, and operations',
      'Excellent written and verbal communication skills',
      'Preferred Qualifications',
      'Experience with ML infrastructure or LLM deployment pipelines',
      'PMP, PMI-ACP, or equivalent certification',
      'Salary Range',
      '$170,000/yr - $240,000/yr + equity + benefits',
    ].join('\n');

    const fixture = makeFixture({
      url: 'https://acme.wd5.myworkday.com/recruiting/job/R-100042',
      pageTitle: 'Staff Technical Program Manager | Acme',
      domText,
      expandButtons: [expandBtn],
    });

    const payload = await runCapture(fixture);
    assert.equal(expandBtn.clicked, 1, 'expansion button clicked');
    assert.ok(payload.visible_text.length >= MIN_CHARS, `too short: ${payload.visible_text.length}`);
    assert.ok(payload.visible_text.includes('Staff Technical Program Manager'), 'title present');
    assert.ok(payload.visible_text.includes('$170,000'), 'salary present');
    assert.equal(payload.preflight.salary, true);
    assert.equal(payload.preflight.remote, true);
  });

  it('handles Workday page with no salary disclosure', async () => {
    const domText = [
      'Engineering Program Manager II',
      'Austin, TX',
      'Job Requisition: R-200815',
      'Overview',
      'The Engineering Program Manager II will coordinate delivery across multiple product teams.',
      'Responsibilities include managing project timelines, identifying risks, and communicating status to stakeholders.',
      'Required Skills',
      '4+ years of program or project management in a software organization',
      'Proficiency with JIRA, Confluence, and related Agile tooling',
      'Nice to have',
      'Experience with SAFe or other scaled Agile frameworks',
      'Familiarity with data-driven delivery metrics and OKR planning processes',
    ].join('\n');

    const fixture = makeFixture({
      url: 'https://company.wd3.myworkday.com/recruiting/job/R-200815',
      pageTitle: 'Engineering Program Manager II',
      domText,
    });

    const payload = await runCapture(fixture);
    assert.ok(payload.visible_text.length >= MIN_CHARS, `too short: ${payload.visible_text.length}`);
    assert.equal(payload.preflight.salary, false, 'salary absent as expected');
    assert.equal(payload.preflight.location, true);
  });
});

describe('job board fixtures — Next.js CSR (Cribl pattern)', () => {
  // Pages using Next.js BAILOUT_TO_CLIENT_SIDE_RENDERING — DOM is nearly empty;
  // full JD lives in __next_f RSC payloads (entity-encoded HTML chunks).
  it('extracts JD from __next_f entity-encoded HTML chunk', async () => {
    const jobHtml = '&lt;div class="content-intro"&gt;&lt;p&gt;Join the company building the future of telemetry. We seek an ambitious Staff Technical Program Manager who puts customers first and delivers our most challenging product development programs.&lt;/p&gt;&lt;/div&gt;&lt;p&gt;&lt;strong&gt;If You\'ve Got It - We Want It&lt;/strong&gt;&lt;/p&gt;&lt;ul&gt;&lt;li&gt;5+ years of leadership experience on software teams&lt;/li&gt;&lt;li&gt;Experience delivering complex projects across organizations&lt;/li&gt;&lt;li&gt;Working knowledge of AI (e.g., machine learning, model lifecycle, data pipelines)&lt;/li&gt;&lt;/ul&gt;&lt;p&gt;&lt;strong&gt;Salary Range&lt;/strong&gt; ($134,000 - $210,000)&lt;/p&gt;&lt;p&gt;The salary for this role is dependent on geographic location.&lt;/p&gt;';

    const fixture = makeFixture({
      url: 'https://cribl.io/job-detail/5990961004/',
      pageTitle: 'Staff Technical Program Manager | Cribl',
      domText: 'Back to Careers\nENGINEERING\nREMOTE - UNITED STATES',
      nextF: [
        [1, 'c:I[12846,[],""]'],  // noise chunk — no HTML entities, no signals
        [1, jobHtml],              // real JD chunk
        [0, null],                 // non-text chunk
      ],
    });

    const payload = await runCapture(fixture);
    assert.ok(payload.visible_text.includes('$134,000'), 'salary min present');
    assert.ok(payload.visible_text.includes('$210,000'), 'salary max present');
    assert.ok(payload.visible_text.includes('leadership experience'), 'requirements present');
    assert.equal(payload.preflight.salary, true);
  });

  it('extracts JD from __NEXT_DATA__ page props when __next_f is absent', async () => {
    // Some Next.js pages populate __NEXT_DATA__ (classic pages router) instead of RSC.
    const fixture = makeFixture({
      url: 'https://example.com/careers/senior-engineer',
      pageTitle: 'Senior Engineer | Example',
      domText: 'Loading…',
      nextData: {
        props: {
          pageProps: {
            job: {
              title: 'Senior Software Engineer',
              location: 'Remote – United States',
              description: 'We are building the next generation of developer tooling. This is a remote position open to candidates across the United States. You will join a small, high-impact team responsible for our core platform. Requirements include 5+ years of experience in distributed systems, strong Python or Go skills, and a track record of delivering complex projects. Salary range: $150,000 – $200,000 USD.',
              department: 'Engineering',
            },
          },
        },
      },
    });

    const payload = await runCapture(fixture);
    // Title is short (<80 chars) and filtered by extractStrings; it appears in page_title not visible_text.
    // Assert on description content and salary which are in the long description string.
    assert.ok(payload.visible_text.includes('distributed systems'), 'description present');
    assert.ok(payload.visible_text.includes('$150,000'), 'salary present');
    assert.ok(payload.visible_text.includes('next generation'), 'description content present');
    assert.equal(payload.preflight.salary, true);
    assert.equal(payload.preflight.remote, true);
  });
});

describe('job board fixtures — LinkedIn', () => {
  // www.linkedin.com/jobs/view/<id> — complex DOM, server-rendered core with
  // hydration. Full text typically available in body.innerText.
  it('extracts JD from LinkedIn server-rendered DOM', async () => {
    const domText = [
      'Director of Engineering',
      'Acme · Seattle, WA (Hybrid)',
      'Full-time · Director',
      '200+ applicants',
      'About the job',
      'Acme is hiring a Director of Engineering to lead our Seattle-based platform team.',
      'You will manage 4 engineering managers and 30+ engineers across backend, data, and infrastructure.',
      'Responsibilities',
      '· Set technical direction and own the roadmap for the platform org',
      '· Partner with product and design on quarterly planning',
      '· Drive hiring, performance management, and career development for direct reports',
      '· Represent engineering in cross-functional leadership forums',
      'Qualifications',
      '· 8+ years of engineering experience, 3+ in engineering management',
      '· Experience scaling distributed systems to millions of users',
      '· BS/MS in Computer Science or equivalent',
      'Salary',
      '$220,000/yr – $280,000/yr',
    ].join('\n');

    const fixture = makeFixture({
      url: 'https://www.linkedin.com/jobs/view/3987654321/',
      pageTitle: 'Director of Engineering | Acme | LinkedIn',
      domText,
    });

    const payload = await runCapture(fixture);
    assert.ok(payload.visible_text.length >= MIN_CHARS, `too short: ${payload.visible_text.length}`);
    assert.ok(payload.visible_text.includes('Director of Engineering'), 'title present');
    assert.ok(payload.visible_text.includes('$220,000'), 'salary present');
    assert.ok(payload.visible_text.includes('roadmap'), 'responsibilities present');
    assert.equal(payload.preflight.salary, true);
    assert.equal(payload.preflight.location, true);
  });
});

describe('job board fixtures — Indeed', () => {
  // www.indeed.com/viewjob — server-rendered with occasional JS enhancement.
  // Core JD is in the DOM.
  it('extracts JD from Indeed server-rendered DOM', async () => {
    const domText = [
      'Principal Data Engineer',
      'DataCo · Remote',
      '$160,000 - $190,000 a year · Full-time',
      'Job details',
      'Pay: $160,000 - $190,000 a year',
      'Job type: Full-time',
      'Remote',
      'Full job description',
      'DataCo is growing its data platform team and looking for a Principal Data Engineer to lead the design and implementation of our next-generation data lakehouse.',
      'Responsibilities',
      'Design and build scalable data pipelines handling 10B+ events per day',
      'Lead technical reviews and set engineering standards for the data org',
      'Collaborate with ML and analytics teams on feature engineering and model serving infrastructure',
      'Qualifications',
      '7+ years of data engineering experience',
      'Deep expertise in Spark, dbt, Airflow, and cloud data warehouses (Snowflake, BigQuery, or Redshift)',
      'Experience with streaming systems (Kafka, Flink, or Kinesis)',
      'Report this job',
    ].join('\n');

    const fixture = makeFixture({
      url: 'https://www.indeed.com/viewjob?jk=abc123def456',
      pageTitle: 'Principal Data Engineer - DataCo - Indeed.com',
      domText,
    });

    const payload = await runCapture(fixture);
    assert.ok(payload.visible_text.length >= MIN_CHARS, `too short: ${payload.visible_text.length}`);
    assert.ok(payload.visible_text.includes('Principal Data Engineer'), 'title present');
    assert.ok(payload.visible_text.includes('$160,000'), 'salary present');
    assert.ok(payload.visible_text.includes('data lakehouse'), 'description present');
    assert.equal(payload.preflight.salary, true);
    assert.equal(payload.preflight.remote, true);
  });
});

describe('job board fixtures — Ashby', () => {
  // jobs.ashbyhq.com — React CSR; content comes via __NEXT_DATA__ page props.
  it('extracts JD from Ashby __NEXT_DATA__ page props', async () => {
    const fixture = makeFixture({
      url: 'https://jobs.ashbyhq.com/acme/senior-pm',
      pageTitle: 'Senior Product Manager | Acme',
      domText: 'Acme Jobs',
      nextData: {
        props: {
          pageProps: {
            jobPosting: {
              title: 'Senior Product Manager',
              locationName: 'Remote – USA',
              employmentType: 'FullTime',
              descriptionPlain: 'We are seeking a Senior PM to own our enterprise product line. This role is fully remote within the United States. You will lead discovery, define requirements, and work daily with engineering to ship. Requirements: 5+ years of product management in B2B SaaS, strong data skills (SQL, analytics), and experience with complex stakeholder environments. Salary: $155,000 – $195,000 plus equity and benefits.',
              team: { name: 'Product' },
            },
          },
        },
      },
    });

    const payload = await runCapture(fixture);
    // Title is short (<80 chars); description is the long string captured from __NEXT_DATA__.
    assert.ok(payload.visible_text.includes('enterprise product line'), 'description present');
    assert.ok(payload.visible_text.includes('$155,000'), 'salary present');
    assert.ok(payload.visible_text.includes('complex stakeholder'), 'description content present');
    assert.equal(payload.preflight.salary, true);
    assert.equal(payload.preflight.remote, true);
  });
});

describe('job board fixtures — BuiltIn', () => {
  // builtinseattle.com / builtin.com — Next.js with RSC payloads.
  it('extracts JD from BuiltIn RSC payload', async () => {
    const jobHtml = '&lt;p&gt;Senior Technical Program Manager&lt;/p&gt;&lt;p&gt;Remote - United States&lt;/p&gt;&lt;p&gt;We are seeking an experienced Technical Program Manager to drive delivery of our largest cross-functional initiatives. You will partner with engineering leads, product managers, and executives to define scope, manage risk, and keep programs on track.&lt;/p&gt;&lt;ul&gt;&lt;li&gt;7+ years of technical program management&lt;/li&gt;&lt;li&gt;Experience with large-scale distributed systems&lt;/li&gt;&lt;li&gt;Strong facilitation and executive communication skills&lt;/li&gt;&lt;/ul&gt;&lt;p&gt;Salary: $160,000 – $210,000 USD&lt;/p&gt;';

    const fixture = makeFixture({
      url: 'https://www.builtinseattle.com/job/senior-technical-program-manager/9319678',
      pageTitle: 'Senior Technical Program Manager - BuiltIn Seattle',
      domText: 'Jobs in Seattle\nBuiltIn Seattle',
      nextF: [
        [1, 'routing:noise:chunk'],
        [1, jobHtml],
      ],
    });

    const payload = await runCapture(fixture);
    assert.ok(payload.visible_text.includes('Technical Program Manager'), 'title present');
    assert.ok(payload.visible_text.includes('$160,000'), 'salary present');
    assert.ok(payload.visible_text.includes('cross-functional'), 'description present');
    assert.equal(payload.preflight.salary, true);
    assert.equal(payload.preflight.remote, true);
  });
});

describe('job board fixtures — JSON-LD structured data', () => {
  // Many job boards (Greenhouse, smart recruiters, company sites) emit a
  // JobPosting JSON-LD block. The extension reads it via querySelectorAll.
  it('surfaces structured data count in preflight', async () => {
    const ldJson = {
      '@context': 'https://schema.org',
      '@type': 'JobPosting',
      title: 'Engineering Manager',
      description: 'Lead a team of backend engineers...',
      hiringOrganization: { name: 'Acme' },
      baseSalary: {
        '@type': 'MonetaryAmount',
        currency: 'USD',
        value: { '@type': 'QuantitativeValue', minValue: 170000, maxValue: 230000, unitText: 'YEAR' },
      },
    };

    const fixture = makeFixture({
      url: 'https://company.com/careers/em-backend',
      pageTitle: 'Engineering Manager | Acme',
      domText: 'Engineering Manager\nRemote – USA\nAcme is hiring an Engineering Manager to lead our backend team. Responsibilities include technical direction, hiring, and delivery. 5+ years of experience required. Salary $170,000–$230,000.',
      ldJson,
    });

    const payload = await runCapture(fixture);
    assert.ok(payload.structured_data.length > 0, 'structured data captured');
    assert.equal(payload.structured_data[0]['@type'], 'JobPosting');
    assert.equal(payload.preflight.structuredData, 1);
    assert.equal(payload.preflight.salary, true);
  });
});
