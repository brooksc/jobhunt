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

describe('extension capture expansion', () => {
  it('clicks job-description expansion controls before collecting text', async () => {
    const ariaExpanded = fakeElement({ text: 'Show more' });
    const showMoreButton = fakeElement({ text: 'Read more' });
    const layoutButton = fakeElement({ text: 'Show more', closestResult: { tagName: 'NAV' } });
    const unrelatedButton = fakeElement({ text: 'Apply now' });
    const doc = {
      title: 'Example job',
      body: { innerText: 'Visible job text after expansion' },
      querySelector(selector) {
        if (selector === 'link[rel="canonical"]') return { href: 'https://example.com/jobs/1' };
        return null;
      },
      querySelectorAll(selector) {
        if (selector === '[aria-expanded="false"]') return [ariaExpanded, layoutButton, unrelatedButton];
        if (selector === "button, [role='button'], a") return [showMoreButton, layoutButton, unrelatedButton];
        if (selector === 'script[type="application/ld+json"]') return [];
        return [];
      },
    };
    const win = {
      location: { href: 'https://example.com/jobs/1' },
      getSelection: () => ({ toString: () => '' }),
    };
    const previousDocument = globalThis.document;
    globalThis.document = doc;

    try {
      const capture = loadCaptureScript();
      const payload = await capture.capturePage(win, doc);

      assert.equal(ariaExpanded.clicked, 1);
      assert.equal(showMoreButton.clicked, 1);
      assert.equal(layoutButton.clicked, 0);
      assert.equal(unrelatedButton.clicked, 0);
      assert.equal(payload.visible_text, 'Visible job text after expansion');
      assert.equal(payload.canonical_url, 'https://example.com/jobs/1');
    } finally {
      globalThis.document = previousDocument;
      delete globalThis.jobhuntCapture;
    }
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

  it('supplements sparse DOM text with Next.js RSC payload containing salary', async () => {
    // Simulates a page like Cribl that uses BAILOUT_TO_CLIENT_SIDE_RENDERING:
    // body.innerText is just nav (~950 chars), salary is in __next_f RSC chunks.
    const jobHtml = '&lt;div class="content-intro"&gt;&lt;p&gt;Join the company building the future of telemetry. We seek an ambitious Staff Technical Program Manager who puts customers first and delivers our most challenging product development programs.&lt;/p&gt;&lt;/div&gt;&lt;p&gt;&lt;strong&gt;If You\'ve Got It - We Want It&lt;/strong&gt;&lt;/p&gt;&lt;ul&gt;&lt;li&gt;5+ years of leadership experience on software teams&lt;/li&gt;&lt;li&gt;Experience delivering complex projects across organizations&lt;/li&gt;&lt;li&gt;Working knowledge of AI (e.g., machine learning, model lifecycle, data pipelines)&lt;/li&gt;&lt;/ul&gt;&lt;p&gt;&lt;br&gt;&lt;strong&gt;Salary Range&lt;/strong&gt; ($134,000 - $210,000)&lt;/p&gt;&lt;p&gt;The salary for this role is dependent on geographic location. The salary offered within the range described will be based on the individual candidate\'s job-related knowledge, skills, and experience.&lt;/p&gt;';
    const doc = {
      title: 'Staff TPM',
      body: { innerText: 'Back to Careers\nENGINEERING\nREMOTE - UNITED STATES' },
      querySelector(selector) {
        if (selector === 'link[rel="canonical"]') return null;
        return null;
      },
      querySelectorAll(selector) {
        if (selector === '[aria-expanded="false"]') return [];
        if (selector === "button, [role='button'], a") return [];
        if (selector === 'script[type="application/ld+json"]') return [];
        return [];
      },
      cloneNode() { return this; },
    };
    const win = {
      location: { href: 'https://example.com/jobs/123' },
      getSelection: () => ({ toString: () => '' }),
      __next_f: [
        [1, 'c:I[12846,[],""]'],  // RSC wire format noise (no HTML entities, filtered out)
        [1, jobHtml],              // Job description HTML chunk with salary
        [0, null],                 // Non-text chunk, filtered out
      ],
    };
    const previousDocument = globalThis.document;
    globalThis.document = doc;

    try {
      const capture = loadCaptureScript();
      const payload = await capture.capturePage(win, doc);

      assert.ok(payload.visible_text.includes('$134,000'), 'salary in visible_text');
      assert.ok(payload.visible_text.includes('$210,000'), 'salary max in visible_text');
      assert.equal(payload.preflight.salary, true, 'preflight salary detected');
    } finally {
      globalThis.document = previousDocument;
      delete globalThis.jobhuntCapture;
    }
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
