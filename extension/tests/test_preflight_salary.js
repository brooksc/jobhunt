// The preflight's Salary field must recognise the range formats real boards publish — not just the
// one shape with a "$" glued to both amounts.
// Run: node --test extension/tests/test_preflight_salary.js
const { describe, it } = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');

const CAPTURE_PATH = path.join(__dirname, '../capture.js');

function loadCapture() {
    const source = fs.readFileSync(CAPTURE_PATH, 'utf8');
    const sandbox = {};
    const chrome = { runtime: { getManifest: () => ({ version: '0.0.0' }) } };
    const fn = new Function('globalThis', 'chrome', 'window', 'document', source);
    fn(sandbox, chrome, undefined, undefined);
    return sandbox.jobhuntCapture;
}

const { capturePreflight } = loadCapture();

function salaryFor(visible) {
    return capturePreflight({
        page_title: 'Some Role',
        visible_text: visible,
        selected_text: '',
        structured_data: [],
    }).salaryVal;
}

describe('capture.js: preflight Salary', () => {
    // Reported: this Workday posting showed "(missing)" even though the range is right there. No "$"
    // anywhere, currency code as a suffix, and glued to the first amount with no space.
    it('reads a currency-suffix range with no dollar sign (Amgen/Workday)', () => {
        const found = salaryFor('Please contact us to request accommodation. . Salary Range 162,048.25USD -219,241.75 USD');
        assert.ok(found, 'expected a salary, got null');
        assert.match(found, /162,048\.25/);
        assert.match(found, /219,241\.75/);
    });

    // The same page that broke the Swift-side parser: the code repeats BEFORE each "$".
    it('reads a repeated currency code before each amount (GitHub)', () => {
        const found = salaryFor('The base salary range for this job is USD $140,400.00 - USD $372,300.00 /Yr.');
        assert.ok(found, 'expected a salary, got null');
        assert.match(found, /140,400\.00/);
        assert.match(found, /372,300\.00/);
    });

    it('still reads the formats it always did', () => {
        assert.match(salaryFor('$133,400 - $226,600 per year'), /133,400/);
        assert.match(salaryFor('Base pay: $120k – $150k'), /120k/i);
        assert.match(salaryFor('Compensation is 120k - 150k depending on level'), /120k/i);
        assert.match(salaryFor('Salary of 133,400 - 226,600 USD annually'), /133,400/);
        assert.match(salaryFor('We pay $185,000 for this role'), /185,000/);
    });

    it('handles an en dash, an em dash and the word "to"', () => {
        for (const sep of ['-', '–', '—', 'to']) {
            const found = salaryFor(`Range: USD 100,000 ${sep} USD 150,000`);
            assert.ok(found, `expected a match for separator ${JSON.stringify(sep)}`);
            assert.match(found, /100,000/);
        }
    });

    // The amount pattern alone would happily read these as pay; requiring a currency marker (or
    // k-notation) is what keeps them out.
    it('does not read plain number ranges as salary', () => {
        assert.equal(salaryFor('We want 3 - 5 years of experience.'), null);
        assert.equal(salaryFor('Requisition 250807 - 250810 posted this quarter.'), null);
        assert.equal(salaryFor('Fiscal years 2026 - 2027 planning experience.'), null);
    });

    it('reports nothing when the posting names no pay at all', () => {
        assert.equal(salaryFor('A great role on a great team. Apply today.'), null);
    });
});

describe('capture.js: preflight Salary from structured data', () => {
    function salaryFrom(structured, visible = 'A great role on a great team.') {
        return capturePreflight({
            page_title: 'Some Role',
            visible_text: visible,
            selected_text: '',
            structured_data: structured,
        }).salaryVal;
    }

    // Job #906 (Ashby): the pay is ONLY in JSON-LD — the visible text names no figure at all — and
    // the preflight reported "(missing)" while the app extracted 200,000–225,000 correctly.
    it('reads baseSalary when the prose names no pay', () => {
        const found = salaryFrom([
            {
                '@type': 'JobPosting',
                title: 'Principal Product Manager - Content',
                baseSalary: {
                    '@type': 'MonetaryAmount',
                    currency: 'USD',
                    value: { '@type': 'QuantitativeValue', minValue: 200000, maxValue: 225000, unitText: 'YEAR' },
                },
            },
        ]);
        assert.equal(found, 'USD 200,000 – 225,000/yr');
    });

    // That same capture carries two JobPosting blocks, only one with pay.
    it('skips a JobPosting whose baseSalary is null', () => {
        const found = salaryFrom([
            { '@type': 'JobPosting', title: 'A', baseSalary: null },
            {
                '@type': 'JobPosting',
                title: 'A',
                baseSalary: { currency: 'USD', value: { minValue: 200000, maxValue: 225000, unitText: 'YEAR' } },
            },
        ]);
        assert.equal(found, 'USD 200,000 – 225,000/yr');
    });

    it('handles a single value and an hourly unit', () => {
        assert.equal(
            salaryFrom([{ '@type': 'JobPosting', baseSalary: { currency: 'USD', value: { value: 185000, unitText: 'YEAR' } } }]),
            'USD 185,000/yr'
        );
        assert.equal(
            salaryFrom([{ '@type': 'JobPosting', baseSalary: { currency: 'USD', value: { minValue: 60, maxValue: 80, unitText: 'HOUR' } } }]),
            'USD 60 – 80/hr'
        );
    });

    // The text is the better source when it exists — it carries the qualifiers a bare number can't.
    it('prefers a salary stated in the text', () => {
        const found = salaryFrom(
            [{ '@type': 'JobPosting', baseSalary: { currency: 'USD', value: { minValue: 1, maxValue: 2, unitText: 'YEAR' } } }],
            'The base salary range for this job is USD $140,400.00 - USD $372,300.00 /Yr.'
        );
        assert.match(found, /140,400/);
    });

    it('reports nothing when structured data carries no usable amount', () => {
        assert.equal(salaryFrom([{ '@type': 'JobPosting', baseSalary: { currency: 'USD', value: {} } }]), null);
        assert.equal(salaryFrom([{ '@type': 'WebSite' }]), null);
        assert.equal(salaryFrom([]), null);
    });
});

describe('capture.js: preflight Salary in nested structured data', () => {
    function salaryFrom(structured) {
        return capturePreflight({
            page_title: 'Some Role',
            visible_text: 'A great role on a great team.',
            selected_text: '',
            structured_data: structured,
        }).salaryVal;
    }

    const baseSalary = {
        currency: 'USD',
        value: { minValue: 200000, maxValue: 225000, unitText: 'YEAR' },
    };

    // Real boards publish all three of these shapes; matching only a top-level string @type reported
    // "(missing)" while the app's own extraction read them fine (TASK-683).
    it('finds a posting inside @graph', () => {
        assert.equal(
            salaryFrom([{ '@context': 'https://schema.org', '@graph': [{ '@type': 'JobPosting', baseSalary }] }]),
            'USD 200,000 – 225,000/yr'
        );
    });

    it('finds a posting with an array-valued @type', () => {
        assert.equal(
            salaryFrom([{ '@type': ['JobPosting', 'Thing'], baseSalary }]),
            'USD 200,000 – 225,000/yr'
        );
    });

    it('finds a posting nested in an array', () => {
        assert.equal(
            salaryFrom([[{ '@type': 'JobPosting', baseSalary }]]),
            'USD 200,000 – 225,000/yr'
        );
    });

    it('still ignores payloads with no JobPosting', () => {
        assert.equal(salaryFrom([{ '@graph': [{ '@type': 'Organization', name: 'Acme' }] }]), null);
    });

    // Bounded, not unbounded: structured data comes from parsed JSON so it can't contain a cycle,
    // but it can be arbitrarily deep, and the scan should give up rather than walk it forever.
    it('gives up on absurdly deep nesting instead of walking it', () => {
        let node = { '@type': 'JobPosting', baseSalary };
        for (let i = 0; i < 20; i += 1) node = { '@graph': [node] };
        assert.equal(salaryFrom([node]), null);
    });
});
