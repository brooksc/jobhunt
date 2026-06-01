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
