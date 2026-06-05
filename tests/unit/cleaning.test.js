import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { cleanDescription } from '../../server/cleaning.js';

describe('cleanDescription', () => {
  it('returns selected_text when present', () => {
    const result = cleanDescription({
      selectedText: 'Selected portion',
      visibleText: 'Full page text',
    });
    assert.equal(result, 'Selected portion');
  });

  it('prefers selected_text over structured data and visible_text', () => {
    const result = cleanDescription({
      selectedText: 'Selected',
      visibleText: 'Visible',
      structuredData: [{ '@type': 'JobPosting', description: 'Structured' }],
    });
    assert.equal(result, 'Selected');
  });

  it('falls back to visible_text when selected_text is empty', () => {
    const result = cleanDescription({
      selectedText: '',
      visibleText: 'Full page text',
    });
    assert.equal(result, 'Full page text');
  });

  it('uses visible_text when no structured data present', () => {
    const result = cleanDescription({
      visibleText: 'Job details here\nLocation: Seattle, WA',
    });
    assert.equal(result, 'Job details here\nLocation: Seattle, WA');
  });

  it('returns empty string for no input', () => {
    const result = cleanDescription({});
    assert.equal(result, '');
  });

  it('normalizes internal whitespace', () => {
    const result = cleanDescription({ visibleText: 'hello   world\n\n\nfoo' });
    assert.doesNotMatch(result, /  /);
    assert.doesNotMatch(result, /\n{3}/);
  });

  it('trims leading and trailing whitespace', () => {
    const result = cleanDescription({ visibleText: '  hello world  ' });
    assert.equal(result.trim(), result);
  });

  it('appends HTML-stripped JSON-LD description after visible text', () => {
    const result = cleanDescription({
      visibleText: 'Job title\nAbout the role',
      structuredData: [{
        '@type': 'JobPosting',
        description: '<p>Full job description with <b>important details</b>.</p>',
      }],
    });
    assert.ok(result.includes('About the role'), 'visible text included');
    assert.ok(result.includes('Full job description with important details'), 'JSON-LD description included without HTML tags');
    assert.doesNotMatch(result, /<[^>]+>/, 'no HTML tags in output');
  });

  it('strips HTML entities from JSON-LD description', () => {
    const result = cleanDescription({
      visibleText: 'Visible',
      structuredData: [{
        '@type': 'JobPosting',
        description: 'Pay: &lt;$100k &amp; $200k&gt; &quot;annually&quot;',
      }],
    });
    assert.ok(result.includes('Pay: <$100k & $200k> "annually"'));
  });

  it('converts block-level HTML tags to newlines preserving salary band label structure', () => {
    // builtinseattle wraps each salary band label in <p><b>Label:</b></p> then the value follows.
    // Stripping tags must produce "Label:\nValue" so salaryBands() can associate them.
    const result = cleanDescription({
      visibleText: 'Job title',
      structuredData: [{
        '@type': 'JobPosting',
        description: '<p><b>San Francisco Bay Area:</b></p>133,400 - 226,600 USD Annual<p><b>All Other US Locations:</b></p>116,000 - 197,000 USD Annual',
      }],
    });
    assert.ok(result.includes('San Francisco Bay Area:'), 'SF Bay Area label present');
    assert.ok(result.includes('All Other US Locations:'), 'All Other US label present');
    assert.ok(result.includes('133,400 - 226,600 USD Annual'), 'SF salary range present');
    assert.ok(result.includes('116,000 - 197,000 USD Annual'), 'other salary range present');
    // Label and value must be on separate lines for salaryBands() to associate them
    const lines = result.split('\n').map(l => l.trim()).filter(Boolean);
    const sfLabelIdx = lines.findIndex(l => l === 'San Francisco Bay Area:');
    assert.ok(sfLabelIdx >= 0, 'SF label on its own line');
    assert.ok(lines[sfLabelIdx + 1].includes('133,400'), 'SF salary on line after label');
  });

  it('includes Workday JSON-LD salary when absent from visible text', () => {
    // Workday wd1 pages have salary only in the JSON-LD description (visible text is truncated)
    const result = cleanDescription({
      visibleText: 'Technical Program Manager\nRemote - USA\nFull time',
      structuredData: [{
        '@type': 'JobPosting',
        description: 'Job duties. San Francisco Bay Area: 133,400 - 226,600 USD Annual All Other US Locations: 116,000 - 197,000 USD Annual',
      }],
    });
    assert.ok(result.includes('133,400 - 226,600 USD Annual'));
    assert.ok(result.includes('116,000 - 197,000 USD Annual'));
  });

  it('skips JSON-LD entries without a description field', () => {
    const result = cleanDescription({
      visibleText: 'Visible content',
      structuredData: [{ '@type': 'JobPosting', title: 'Engineer' }],
    });
    assert.equal(result, 'Visible content');
  });

  it('traverses @graph to find JobPosting description (builtinseattle format)', () => {
    const result = cleanDescription({
      visibleText: 'Page content',
      structuredData: [{
        '@context': 'https://schema.org',
        '@graph': [
          { '@type': 'JobPosting', description: 'Found via @graph traversal.' },
          { '@type': 'BreadcrumbList', itemListElement: [] },
        ],
      }],
    });
    assert.ok(result.includes('Found via @graph traversal'));
    assert.ok(result.includes('Page content'));
  });

  it('prepends Work arrangement: Remote when jobLocationType is TELECOMMUTE', () => {
    const result = cleanDescription({
      visibleText: 'Some visible content',
      structuredData: [{
        '@type': 'JobPosting',
        jobLocationType: 'TELECOMMUTE',
        description: 'Job details here.',
      }],
    });
    assert.ok(result.includes('Work arrangement: Remote'), 'remote line present');
    assert.ok(result.includes('Job details here'), 'description still included');
  });

  it('includes jobLocationType remote line even when no description is present', () => {
    const result = cleanDescription({
      visibleText: 'Some visible content',
      structuredData: [{ '@type': 'JobPosting', jobLocationType: 'TELECOMMUTE' }],
    });
    assert.ok(result.includes('Work arrangement: Remote'));
  });

  it('includes JobPosting description even when visible text already has job content', () => {
    // Both sources are included — accuracy over deduplication
    const result = cleanDescription({
      visibleText: 'Salary: 116K-227K Annually',
      structuredData: [{
        '@type': 'JobPosting',
        description: 'San Francisco Bay Area: 133,400 - 226,600 USD Annual All Other US Locations: 116,000 - 197,000 USD Annual',
      }],
    });
    assert.ok(result.includes('116K-227K Annually'), 'visible text salary badge present');
    assert.ok(result.includes('San Francisco Bay Area:'), 'JSON-LD band label present');
  });
});
