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

  it('falls back to visible_text when selected_text is empty', () => {
    const result = cleanDescription({
      selectedText: '',
      visibleText: 'Full page text',
    });
    assert.equal(result, 'Full page text');
  });

  it('prepends detected location metadata for visible-text-only Microsoft captures', () => {
    const result = cleanDescription({
      visibleText: `Search jobs
Technical Program Manager
United States, Washington, Redmond +2 more
Apply now
Job description`,
    });

    assert.match(result, /^Location: United States, Washington, Redmond \+2 more/);
  });

  it('focuses Microsoft search-page captures on the selected job detail', () => {
    const result = cleanDescription({
      visibleText: `Search jobs
Technical Program Manager
United States, Washington, Redmond + 2 more
Posted 2 months ago
Principal Technical Program Manager - Quantum
United States, Washington, Redmond
Posted a month ago
1 of 63
Technical Program Manager
United States, Washington, Redmond
+2 more
Apply now
Job description
Job number
200011325
Work site
4 days / week in-office
Overview
This is the selected detail body.`,
    });

    assert.match(result, /^Location: United States, Washington, Redmond/);
    assert.match(result, /Technical Program Manager/);
    assert.match(result, /This is the selected detail body/);
    assert.doesNotMatch(result, /Principal Technical Program Manager - Quantum/);
  });

  it('does not turn long description lines into salary metadata', () => {
    const result = cleanDescription({
      visibleText: `1 of 63
Technical Program Manager
United States, Washington, Redmond
Job description
Job number
200011325
Work site
4 days / week in-office
OverviewAt Microsoft AI this long body line mentions Technical Program Management IC5 - The typical base pay range for this role across the U.S. is USD $139,900 - $274,800 per year but it is not header metadata.`,
    });

    assert.doesNotMatch(result, /^Salary range:/m);
  });

  it('prepends BuiltIn remote metadata from early page badges', () => {
    const result = cleanDescription({
      visibleText: `Principal Technical Program Manager
Zscaler
Remote
Hiring Remotely in USA
$200,000
About Zscaler
This role offers the flexibility to work remotely within the United States.`,
    });

    assert.match(result, /^Work arrangement: Remote/m);
    assert.match(result, /Hiring Remotely in USA/);
    assert.match(result, /Principal Technical Program Manager/);
  });

  it('keeps Levels detail-pane content when listing text surrounds it', () => {
    const result = cleanDescription({
      visibleText: `levels.fyi Jobs
Zscaler
Cloud-based information security company.
Sr. Staff Technical Program Manager - DoW
Fully Remote · $200K
About Zscaler
This role offers the flexibility to work remotely within the United States, with a preference for candidates near our Washington, DC Metro Area office.
Role
We are looking for an experienced Sr. Staff Technical Program Manager.`,
    });

    assert.match(result, /Work arrangement: Remote/);
    assert.match(result, /About Zscaler/);
    assert.match(result, /Washington, DC Metro Area/);
  });

  it('captures Greenhouse structured job posting text', () => {
    const result = cleanDescription({
      visibleText: 'Careers page shell',
      structuredData: [{
        '@type': 'JobPosting',
        title: 'Senior Technical Program Manager',
        hiringOrganization: { name: 'ExampleCo' },
        jobLocation: { address: { addressLocality: 'Seattle', addressRegion: 'WA' } },
        baseSalary: { value: { minValue: 160000, maxValue: 220000, unitText: 'YEAR' }, currency: 'USD' },
        description: 'Lead platform programs across engineering teams.',
      }],
    });

    assert.match(result, /Senior Technical Program Manager/);
    assert.match(result, /Seattle, WA/);
    assert.match(result, /USD160000/);
    assert.match(result, /Lead platform programs/);
  });

  it('normalizes internal whitespace', () => {
    const result = cleanDescription({ visibleText: 'hello   world\n\n\nfoo' });
    assert.doesNotMatch(result, /  /);
  });

  it('trims leading and trailing whitespace', () => {
    const result = cleanDescription({ visibleText: '  hello world  ' });
    assert.equal(result.trim(), result);
  });

  it('returns empty string for no input', () => {
    const result = cleanDescription({});
    assert.equal(result, '');
  });

  it('prefers selected_text over structured data and visible_text', () => {
    const result = cleanDescription({
      selectedText: 'Selected',
      visibleText: 'Visible',
      structuredData: [{ '@type': 'JobPosting', description: 'Structured' }],
    });
    assert.equal(result, 'Selected');
  });
});
